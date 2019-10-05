{-# LANGUAGE PolyKinds    #-}
{-# LANGUAGE TypeFamilies #-}
module Barbies.Internal.Traversable
  ( TraversableB(..)
  , btraverse_
  , bsequence
  , bsequence'
  , bfoldMap

  , CanDeriveTraversableB
  , GTraversableB(..)
  , gbtraverseDefault
  )

where

import Barbies.Internal.Functor(FunctorB (..))

import Data.Functor           (void)
import Data.Functor.Compose   (Compose (..))
import Data.Functor.Const     (Const (..))
import Data.Functor.Identity  (Identity (..))
import Data.Functor.Product   (Product (..))
import Data.Functor.Sum       (Sum (..))
import Data.Kind              (Type)
import Data.Generics.GenericN
import Data.Proxy             (Proxy (..))

-- | Barbie-types that can be traversed from left to right. Instances should
--   satisfy the following laws:
--
-- @
--  t . 'btraverse' f   = 'btraverse' (t . f)  -- naturality
-- 'btraverse' 'Data.Functor.Identity' = 'Data.Functor.Identity'           -- identity
-- 'btraverse' ('Compose' . 'fmap' g . f) = 'Compose' . 'fmap' ('btraverse' g) . 'btraverse' f -- composition
-- @
--
-- There is a default 'btraverse' implementation for 'Generic' types, so
-- instances can derived automatically.
class FunctorB b => TraversableB (b :: (k -> Type) -> Type) where
  btraverse :: Applicative t => (forall a . f a -> t (g a)) -> b f -> t (b g)

  default btraverse
    :: ( Applicative t, CanDeriveTraversableB b f g)
    => (forall a . f a -> t (g a)) -> b f -> t (b g)
  btraverse = gbtraverseDefault



-- | Map each element to an action, evaluate these actions from left to right,
--   and ignore the results.
btraverse_ :: (TraversableB b, Applicative t) => (forall a. f a -> t c) -> b f -> t ()
btraverse_ f
  = void . btraverse (fmap (const $ Const ()) . f)


-- | Evaluate each action in the structure from left to right,
--   and collect the results.
bsequence :: (Applicative f, TraversableB b) => b (Compose f g) -> f (b g)
bsequence
  = btraverse getCompose

-- | A version of 'bsequence' with @g@ specialized to 'Identity'.
bsequence' :: (Applicative f, TraversableB b) => b f -> f (b Identity)
bsequence'
  = btraverse (fmap Identity)


-- | Map each element to a monoid, and combine the results.
bfoldMap :: (TraversableB b, Monoid m) => (forall a. f a -> m) -> b f -> m
bfoldMap f
  = execWr . btraverse_ (tell . f)


-- | @'CanDeriveTraversableB' B f g@ is in practice a predicate about @B@ only.
--   It is analogous to 'Barbies.Internal.Functor.CanDeriveFunctorB', so it
--   essentially requires the following to hold, for any arbitrary @f@:
--
--     * There is an instance of @'Generic' (B f)@.
--
--     * @B f@ can contain fields of type @b f@ as long as there exists a
--       @'TraversableB' b@ instance. In particular, recursive usages of @B f@
--       are allowed.
--
--     * @B f@ can also contain usages of @b f@ under a @'Traversable' h@.
--       For example, one could use @'Maybe' (B f)@ when defining @B f@.
type CanDeriveTraversableB b f g
  = ( GenericN (b f)
    , GenericN (b g)
    , GTraversableB 0 f g (RepN (b f)) (RepN (b g))
    )

-- | Default implementation of 'btraverse' based on 'Generic'.
gbtraverseDefault
  :: forall b f g t
  .  (Applicative t, CanDeriveTraversableB b f g)
  => (forall a . f a -> t (g a))
  -> b f -> t (b g)
gbtraverseDefault h
  = fmap toN . gbtraverse (Proxy @0) h . fromN
{-# INLINE gbtraverseDefault #-}


class GTraversableB n f g repbf repbg where
  gbtraverse
    :: Applicative t
    => Proxy n
    -> (forall a . f a -> t (g a))
    -> repbf x
    -> t (repbg x)

-- ----------------------------------
-- Trivial cases
-- ----------------------------------

instance GTraversableB n f g bf bg => GTraversableB n f g (M1 i c bf) (M1 i c bg) where
  gbtraverse pn h = fmap M1 . gbtraverse pn h . unM1
  {-# INLINE gbtraverse #-}

instance GTraversableB n f g V1 V1 where
  gbtraverse _ _ _ = undefined
  {-# INLINE gbtraverse #-}

instance GTraversableB n f g U1 U1 where
  gbtraverse _ _ = pure
  {-# INLINE gbtraverse #-}

instance (GTraversableB n f g l l', GTraversableB n f g r r') => GTraversableB n f g (l :*: r) (l' :*: r') where
  gbtraverse pn h (l :*: r)= (:*:) <$> gbtraverse pn h l <*> gbtraverse pn h r
  {-# INLINE gbtraverse #-}

instance (GTraversableB n f g l l', GTraversableB n f g r r') => GTraversableB n f g (l :+: r) (l' :+: r') where
  gbtraverse pn h = \case
    L1 l -> L1 <$> gbtraverse pn h l
    R1 r -> R1 <$> gbtraverse pn h r
  {-# INLINE gbtraverse #-}

-- --------------------------------
-- The interesting cases
-- --------------------------------

type P = Param

instance GTraversableB n f g (Rec (P n f a) (f a))
                             (Rec (P n g a) (g a)) where
  gbtraverse _ h = fmap (Rec . K1) . h . unK1 . unRec
  {-# INLINE gbtraverse #-}

instance
  ( SameOrParam b b'
  , TraversableB b'
  ) => GTraversableB 0 f g (Rec (b (P 0 f)) (b' f))
                           (Rec (b (P 0 g)) (b' g)) where
  gbtraverse _ h
    = fmap (Rec . K1) . btraverse h . unK1 . unRec
  {-# INLINE gbtraverse #-}

instance
   ( SameOrParam h h'
   , SameOrParam b b'
   , Traversable h'
   , TraversableB b'
   ) => GTraversableB 0 f g (Rec (h (b (P 0 f))) (h' (b' f)))
                            (Rec (h (b (P 0 g))) (h' (b' g))) where
  gbtraverse _ h
    = fmap (Rec . K1) . traverse (btraverse h) . unK1 . unRec
  {-# INLINE gbtraverse #-}


instance GTraversableB n f g (Rec a a) (Rec a a) where
  gbtraverse _ _ = pure
  {-# INLINE gbtraverse #-}



-- We roll our own State/efficient-Writer monad, not to add dependencies

newtype St s a
  = St (s -> (a, s))

runSt :: s -> St s a -> (a, s)
runSt s (St f)
  = f s

instance Functor (St s) where
  fmap f (St g)
    = St $ (\(a, s') -> (f a, s')) . g
  {-# INLINE fmap #-}

instance Applicative (St s) where
  pure
    = St . (,)
  {-# INLINE pure #-}

  St l <*> St r
    = St $ \s ->
        let (f, s')  = l s
            (x, s'') = r s'
        in (f x, s'')
  {-# INLINE (<*>) #-}

type Wr = St

execWr :: Monoid w => Wr w a -> w
execWr
  = snd . runSt mempty

tell :: Monoid w => w -> Wr w ()
tell w
  = St (\s -> ((), s `mappend` w))


-- Instances for base types

instance TraversableB Proxy where
  btraverse _ _ = pure Proxy
  {-# INLINE btraverse #-}

instance (TraversableB a, TraversableB b) => TraversableB (Product a b) where
  btraverse f (Pair x y) = Pair <$> btraverse f x <*> btraverse f y
  {-# INLINE btraverse #-}

instance (TraversableB a, TraversableB b) => TraversableB (Sum a b) where
  btraverse f (InL x) = InL <$> btraverse f x
  btraverse f (InR x) = InR <$> btraverse f x
  {-# INLINE btraverse #-}

instance TraversableB (Const a) where
  btraverse _ (Const x) = pure (Const x)
  {-# INLINE btraverse #-}

instance (Traversable f, TraversableB b) => TraversableB (f `Compose` b) where
  btraverse h (Compose x)
    = Compose <$> traverse (btraverse h) x
  {-# INLINE btraverse #-}
