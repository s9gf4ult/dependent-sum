{-# LANGUAGE GADTs, TypeOperators, RankNTypes, TypeFamilies, FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# OPTIONS_GHC -fno-warn-deprecated-flags #-}
{-# LANGUAGE CPP #-}
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 708
{-# LANGUAGE PolyKinds #-}
#endif
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Safe #-}
#endif
{-# LANGUAGE ScopedTypeVariables #-}

module Data.GADT.Compare
    ( module Data.GADT.Compare
#if MIN_VERSION_base(4,7,0)
    , (:~:)(Refl)
#endif
    ) where

import Data.Maybe
import Data.GADT.Show
import Data.Typeable

#if MIN_VERSION_base(4,7,0)
-- |Backwards compatibility alias; as of GHC 7.8, this is the same as `(:~:)`.
type (:=) = (:~:)

#else

-- |A GADT witnessing equality of two types.  Its only inhabitant is 'Refl'.
data a := b where
    Refl :: a := a
    deriving Typeable

instance Eq (a := b) where
    Refl == Refl = True

instance Ord (a := b) where
    compare Refl Refl = EQ

instance Show (a := b) where
    showsPrec _ Refl = showString "Refl"

instance Read (a := a) where
    readsPrec _ s = case con of
        "Refl"  -> [(Refl, rest)]
        _       -> []
        where (con,rest) = splitAt 4 s

#endif

instance GShow ((:=) a) where
    gshowsPrec _ Refl = showString "Refl"

instance GRead ((:=) a) where
    greadsPrec p s = readsPrec p s >>= f
        where
            f :: forall x. (x := x, String) -> [(GReadResult ((:=) x), String)]
            f (Refl, rest) = return (GReadResult (\x -> x Refl) , rest)

-- |A class for type-contexts which contain enough information
-- to (at least in some cases) decide the equality of types
-- occurring within them.
class GEq (f :: k -> *) where
    -- |Produce a witness of type-equality, if one exists.
    --
    -- A handy idiom for using this would be to pattern-bind in the Maybe monad, eg.:
    --
    -- > extract :: GEq tag => tag a -> DSum tag -> Maybe a
    -- > extract t1 (t2 :=> x) = do
    -- >     Refl <- geq t1 t2
    -- >     return x
    --
    -- Or in a list comprehension:
    --
    -- > extractMany :: GEq tag => tag a -> [DSum tag] -> [a]
    -- > extractMany t1 things = [ x | (t2 :=> x) <- things, Refl <- maybeToList (geq t1 t2)]
    --
    -- (Making use of the 'DSum' type from "Data.Dependent.Sum" in both examples)
    geq :: f a -> f b -> Maybe (a := b)

-- |If 'f' has a 'GEq' instance, this function makes a suitable default
-- implementation of '(==)'.
defaultEq :: GEq f => f a -> f b -> Bool
defaultEq x y = isJust (geq x y)

-- |If 'f' has a 'GEq' instance, this function makes a suitable default
-- implementation of '(/=)'.
defaultNeq :: GEq f => f a -> f b -> Bool
defaultNeq x y = isNothing (geq x y)

instance GEq ((:=) a) where
    geq (Refl :: a := b) (Refl :: a := c) = Just (Refl :: b := c)

-- This instance seems nice, but it's simply not right:
--
-- > instance GEq StableName where
-- >     geq sn1 sn2
-- >         | sn1 == unsafeCoerce sn2
-- >             = Just (unsafeCoerce Refl)
-- >         | otherwise     = Nothing
--
-- Proof:
--
-- > x <- makeStableName id :: IO (StableName (Int -> Int))
-- > y <- makeStableName id :: IO (StableName ((Int -> Int) -> Int -> Int))
-- >
-- > let Just boom = geq x y
-- > let coerce :: (a := b) -> a -> b; coerce Refl = id
-- >
-- > coerce boom (const 0) id 0
-- > let "Illegal Instruction" = "QED."
--
-- The core of the problem is that 'makeStableName' only knows the closure
-- it is passed to, not any type information.  Together with the fact that
-- the same closure has the same StableName each time 'makeStableName' is
-- called on it, there is serious potential for abuse when a closure can
-- be given many incompatible types.


-- |A type for the result of comparing GADT constructors; the type parameters
-- of the GADT values being compared are included so that in the case where
-- they are equal their parameter types can be unified.
data GOrdering a b where
    GLT :: GOrdering a b
    GEQ :: GOrdering t t
    GGT :: GOrdering a b
    deriving Typeable

-- |TODO: Think of a better name
--
-- This operation forgets the phantom types of a 'GOrdering' value.
weakenOrdering :: GOrdering a b -> Ordering
weakenOrdering GLT = LT
weakenOrdering GEQ = EQ
weakenOrdering GGT = GT

instance Eq (GOrdering a b) where
    x == y =
        weakenOrdering x == weakenOrdering y

instance Ord (GOrdering a b) where
    compare x y = compare (weakenOrdering x) (weakenOrdering y)

instance Show (GOrdering a b) where
    showsPrec _ GGT = showString "GGT"
    showsPrec _ GEQ = showString "GEQ"
    showsPrec _ GLT = showString "GLT"

instance GShow (GOrdering a) where
    gshowsPrec = showsPrec

instance GRead (GOrdering a) where
    greadsPrec _ s = case con of
        "GGT"   -> [(GReadResult (\x -> x GGT), rest)]
        "GEQ"   -> [(GReadResult (\x -> x GEQ), rest)]
        "GLT"   -> [(GReadResult (\x -> x GLT), rest)]
        _       -> []
        where (con, rest) = splitAt 3 s

-- |Type class for comparable GADT-like structures.  When 2 things are equal,
-- must return a witness that their parameter types are equal as well ('GEQ').
class GEq f => GCompare (f :: k -> *) where
    gcompare :: f a -> f b -> GOrdering a b

instance GCompare ((:=) a) where
    gcompare Refl Refl = GEQ

defaultCompare :: GCompare f => f a -> f b -> Ordering
defaultCompare x y = weakenOrdering (gcompare x y)
