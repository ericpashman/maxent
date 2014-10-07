-- |
-- The maximum entropy method, or MAXENT, is variational approach for computing probability 
-- distributions given a list of moment, or expected value, constraints.
-- 
-- Here are some links for background info.
-- A good overview of applications:
-- <http://cmm.cit.nih.gov/maxent/letsgo.html>
-- On the idea of maximum entropy in general: 
-- <http://en.wikipedia.org/wiki/Principle_of_maximum_entropy>
--  
-- 
-- Use this package to compute discrete maximum entropy distributions over a list of values and
-- list of constraints.
-- 
-- Here is a the example from Probability the Logic of Science
-- 
-- >>> maxent 0.00001 [1,2,3] [average 1.5]
-- Right [0.61, 0.26, 0.11]
-- 
-- The classic dice example
--
-- >>> maxent 0.00001 [1,2,3,4,5,6] [average 4.5]
-- Right [.05, .07, 0.11, 0.16, 0.23, 0.34]
-- 
-- One can use different constraints besides the average value there.  
--
-- As for why you want to maximize the entropy to find the probability constraint, 
-- I will say this for now. In the case of the average constraint 
-- it is a kin to choosing a integer partition with the most interger compositions. 
-- I doubt that makes any sense, but I will try to explain more with a blog post soon.
-- 
module Numeric.MaxEnt (
    Constraint,
    (.=.),
    ExpectationConstraint,
    average,
    variance,
    -- ** Classic moment based
    maxent,
    -- ** General
    general, 
    -- ** Linear
    LinearConstraints(..),
    linear,
    linear',
    linear''
) where

import Numeric.MaxEnt.Internal (Constraint,
                        (.=.),
                        ExpectationConstraint,
                        average,
                        variance,
                        maxent,
                        general,
                        linear,
                        linear',
                        linear'',
                        LinearConstraints(..))
