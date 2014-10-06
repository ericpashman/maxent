{-# LANGUAGE Rank2Types, NoMonomorphismRestriction #-}

module Numeric.MaxEnt.Moment (
        ExpectationConstraint,
        (.=.),
        average,
        variance,
        maxent
    ) where

import qualified Data.Vector.Storable as S

import Numeric.Optimization.Algorithms.HagerZhang05 (Result, Statistics)
import Numeric.AD.Lagrangian
import Numeric.MaxEnt.General

-- | Constraint type. A function and the constant it equals.
-- 
--   Think of it as the pair @(f, c)@ in the constraint 
--
-- @
--     &#931; p&#8336; f(x&#8336;) = c
-- @
--
--  such that we are summing over all values .
--
--  For example, for a variance constraint the @f@ would be @(\\x -> x*x)@ and @c@ would be the variance.
newtype ExpectationConstraint = ExpCon
    { unExpCon :: forall a. (Floating a) => [a] -> ([a] -> a, a) }


infixr 1 .=.
(.=.) :: (forall a. (Floating a) => a -> a)
      -> (forall b. (Floating b) => b)
      -> ExpectationConstraint
f .=. c = ExpCon $ \vals -> (sum .zipWith (*) vals . map f , c)

expCon2Con :: (forall a. (Floating a) => [a])
           -> ExpectationConstraint
           -> Constraint
expCon2Con vals expCon = f <=> c where
    (f, c) = unExpCon expCon vals

-- The average constraint
average :: (forall a. (Floating a) => a) -> ExpectationConstraint
average m = id .=. m

-- The variance constraint
variance :: (forall a. (Floating a) => a) -> ExpectationConstraint
variance sigma = (^(2 :: Int)) .=. sigma

-- | Discrete maximum entropy solver where the constraints are all moment
-- constraints. 
maxent :: Double 
       -- ^ Tolerance for the numerical solver
       -> (forall a. (Floating a) => [a])
       -- ^ values that the distributions is over
       -> [ExpectationConstraint]
       -- ^ The constraints
       -> Either (Result, Statistics) (S.Vector Double) 
       -- ^ Either the a discription of what wrong or the probability distribution 
maxent tolerance values expConstraints = general tolerance n constraints where
    constraints = map (expCon2Con values) expConstraints 
    n = length values