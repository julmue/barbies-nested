{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}
module Data.Barbie.Internal.ProofB
  ( ProofB(..)
  , buniqC
  , bmempty

  , CanDeriveProofB
  , GAllB
  , GProofB(..)
  , gbproofDefault
  )

where

import Data.Barbie.Internal.Constraints
import Data.Barbie.Internal.Dicts(ClassF, Dict(..), requiringDict)
import Data.Barbie.Internal.Functor(bmap)
import Data.Barbie.Internal.Product(ProductB(..))

import Data.Generics.GenericN

-- | Barbie-types with products have a canonical proof of instance.
--
-- There is a default 'bproof' implementation for 'Generic' types, so
-- instances can derived automatically.
class (ConstraintsB b, ProductB b) => ProofB b where
  bproof :: AllB c b => b (Dict c)

  default bproof :: (CanDeriveProofB c b, AllB c b) => b (Dict c)
  bproof = gbproofDefault

-- | Every type that admits a generic instance of 'ProductB' and
--   'ConstraintsB', has a generic instance of 'ProofB' as well.
type CanDeriveProofB c b
  = ( GenericN (b (Dict c))
    , AllB c b ~ GAllB c (GAllBRep b)
    , GProofB c (GAllBRep b) (RepN (b (Dict c)))
    )

-- | Like 'buniq' but an constraint is allowed to be required on
--   each element of @b@.
buniqC :: forall c f b . (AllB c b, ProofB b) => (forall a . c a => f a) -> b f
buniqC x
  = bmap (requiringDict @c x) bproof

-- | Builds a @b f@, bu applying 'mempty' on every field of @b@.
bmempty :: forall f b . (AllB (ClassF Monoid f) b, ProofB b) => b f
bmempty
  = buniqC @(ClassF Monoid f) mempty

-- ===============================================================
--  Generic derivations
-- ===============================================================

-- | Default implementation of 'bproof' based on 'Generic'.
gbproofDefault
  :: forall b c
  .  ( CanDeriveProofB c b
     , AllB c b
     )
  => b (Dict c)
gbproofDefault
  = toN $ gbproof @c @(GAllBRep b)
{-# INLINE gbproofDefault #-}


class GProofB c repbx repbd where
  gbproof
    :: GAllB c repbx => repbd x

-- ----------------------------------
-- Trivial cases
-- ----------------------------------

instance GProofB c repbx repbd => GProofB c (M1 i k repbx) (M1 i k repbd) where
  gbproof = M1 (gbproof @c @repbx)
  {-# INLINE gbproof #-}

instance GProofB c U1 U1 where
  gbproof = U1
  {-# INLINE gbproof #-}

instance
  ( GProofB c lx ld
  , GProofB c rx rd
  ) => GProofB c (lx :*: rx)
                 (ld :*: rd) where
  gbproof = gbproof @c @lx @ld :*: gbproof @c @rx @rd
  {-# INLINE gbproof #-}


-- --------------------------------
-- The interesting cases
-- --------------------------------

type P0 = Param 0

instance GProofB c (Rec (P0 X a) (X a))
                   (Rec (P0 (Dict c) a) (Dict c a)) where
  gbproof = Rec (K1 Dict)
  {-# INLINE gbproof #-}

instance (ProofB b', AllB c b')
  => GProofB c (Rec (Self b' (P0 X)) (b' X))
               (Rec (b' (P0 (Dict c))) (b' (Dict c))) where
  gbproof = Rec $ K1 $ bproof @b'

instance (ProofB b', AllB c b')
  => GProofB c (Rec (Other b' (P0 X)) (b' X))
               (Rec (b' (P0 (Dict c))) (b' (Dict c))) where
  gbproof = Rec $ K1 $ bproof @b'
