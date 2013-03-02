{-# LANGUAGE TupleSections, Rank2Types #-}
module MaxEnt.Internal where
import Numeric.Optimization.Algorithms.HagerZhang05
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector.Storable as S
import Numeric.AD
import GHC.IO                   (unsafePerformIO)
import Data.Traversable
import Numeric.AD.Types
import Numeric.AD.Internal.Classes
import Data.List (transpose)
--import Numeric.AD.Lagrangian

sumMap :: Num b => (a -> b) -> [a] -> b 
sumMap f = sum . map f

sumWith :: Num c => (a -> b -> c) -> [a] -> [b] -> c 
sumWith f xs = sum . zipWith f xs

pOfK :: Floating a => [a] -> [ExpectationFunction a] -> [a] -> Int -> a
pOfK values fs ls k = exp (negate . sumWith (\l f -> l * f (values !! k)) ls $ fs) / 
    partitionFunc values fs ls 

pOfKLinear :: Floating a => [[a]] -> [a] -> Int -> a
pOfKLinear matrix ls k = 
    exp (dot (matrix !! k) ls) / 
        partitionFuncLinear matrix ls

probs :: (Floating b)
      => [b] 
      -> [ExpectationFunction b] 
      -> [b] 
      -> [b]    
probs values fs ls = map (pOfK values fs ls) [0..length values - 1] 

partitionFunc :: Floating a
              => [a] 
              -> [ExpectationFunction a]
              -> [a] 
              -> a
partitionFunc values fs ls = sum $ [ exp ((-l) * f x) | 
                                x <- values, 
                                (f, l) <- zip fs ls]

objectiveFunc :: Floating a
              => [a] 
              -> [ExpectationFunction a] 
              -> [a] 
              -> [a] 
              -> a
objectiveFunc values fs moments ls = log (partitionFunc values fs ls) 
                                   + sumWith (*) ls moments


dot :: Num a => [a] -> [a] -> a
dot x y = sum . zipWith (*) x $ y

-- have the column and rows backwards
partitionFuncLinear :: Floating a
             => [[a]]
             -> [a] 
             -> a
partitionFuncLinear matrix ws = sum $ [ exp (dot as ws) | as <- transpose matrix]

-- This is almost the sam as the objectiveFunc                                   
objectiveFuncLinear :: Floating a
             => [[a]] 
             -> [a] 
             -> [a] 
             -> a
objectiveFuncLinear as moments ls = 
    log (partitionFuncLinear as ls) - dot ls moments


linProbs :: (Floating b)
      => [[b]] 
      -> [b] 
      -> [b]    
linProbs matrix ls = 
    map (pOfKLinear matrix ls) [0..length matrix - 1]

entropy :: Floating a => [a] -> a
entropy = negate . sumMap (\p -> p * log p) 


-- This a functions that takes in a list of values and 
-- a list of probabilities
type GeneralConstraint a = [a] -> [a] -> a


lagrangian :: Floating a
             => ([a], [GeneralConstraint a], [a]) 
             -> [a] 
             -> a
lagrangian (values, fs, constants) lamsAndProbs = result where
    result = entropy ps + (sum $ zipWith (*) lams constraints)
    constraints        = zipWith (-) appliedConstraints constants
    appliedConstraints = map (\f -> f values ps) fs
        
    -- split the args list
    ps   = take (length values) lamsAndProbs
    lams = drop (length values) lamsAndProbs

squaredGrad :: Num a 
            => (forall s. Mode s => [AD s a] -> AD s a) -> [a] -> a
squaredGrad f vs = sumMap (\x -> x*x) (grad f vs)

generalObjectiveFunc :: Floating a => (forall b. Floating b => 
             ([b], [GeneralConstraint b], [b]))
             -> [a] 
             -> a
generalObjectiveFunc params lamsAndProbs = 
    squaredGrad lang lamsAndProbs  where
        
    lang :: Floating a => (forall s. Mode s => [AD s a] -> AD s a)
    lang = lagrangian params


toFunction :: (forall a. Floating a => [a] -> a) -> Function Simple
toFunction f = VFunction (f . U.toList)

toGradient :: (forall a. Floating a => [a] -> a) -> Gradient Simple
toGradient f = VGradient (U.fromList . grad f . U.toList)

toDoubleF :: (forall a. Floating a => [a] -> a) -> [Double] -> Double
toDoubleF f x = f x 



-- make a constraint from function and constant
constraint :: Floating a => ExpectationFunction a -> a -> Constraint a
constraint = (,)

-- The average constraint
average :: Floating a => a -> Constraint a
average m = constraint id m

-- The variance constraint
variance :: Floating a => a -> Constraint a
variance sigma = constraint (^(2 :: Int)) sigma

-- | Most general solver
--   This will solve the langrangian by added the constraint that the 
--   probabilities must add up to zero.
--   This is the slowest but most flexible method. 

generalMaxent :: (forall a. Floating a => ([a], [(GeneralConstraint a, a)])) -- ^ A pair of values that the distributions is over and the constraints
       -> Either (Result, Statistics) [Double] -- ^ Either the a discription of what wrong or the probability distribution
generalMaxent params = result where
   obj :: Floating a => [a] -> a
   obj = generalObjectiveFunc objInput

   values :: Floating a => [a]
   values = fst params

   constraints :: Floating a => [(GeneralConstraint a, a)]
   constraints = snd params

   fsmoments :: Floating a => ([GeneralConstraint a], [a])
   fsmoments = unzip constraints 
   
   --The new constraint is always needed for probability problems
   
   sumToOne :: Floating a => GeneralConstraint a
   sumToOne _ xs = sumMap id xs
   
   gcons' :: Floating a => [GeneralConstraint a]
   gcons' = fst fsmoments
   
   gcons :: Floating a => [GeneralConstraint a]
   gcons = sumToOne : gcons'
   
   moments :: Floating a => [a]
   moments = 1 : snd fsmoments
   
   
   objInput :: Floating b => ([b], [GeneralConstraint b], [b])
   objInput = (values, gcons, moments)

   fs :: [[Double] -> [Double] -> Double]
   fs = fst fsmoments

   --hmm maybe there is a better way to get rid of the defaulting
   guess = U.fromList $ replicate 
       (length fs) (1.0 :: Double) 

   result = case unsafePerformIO (optimize defaultParameters 0.00001 guess 
                        (toFunction obj)
                        (toGradient obj)
                       Nothing) of
       -- Not sure what is supposed to happen here
       -- I guess I can plug the lambdas back in
       (vs, ToleranceStatisfied, _) -> Right $  (S.toList vs)
       (_, x, y) -> Left (x, y)
       
       

-- | This is for the linear case Ax = b 
--   @x@ in this situation is the vector of probablities.
--  
--  For example.
-- 
-- @
--   maxentLinear ([[0.85, 0.1, 0.05], [0.25, 0.5, 0.25], [0.05, 0.1, 0.85]], [0.29, 0.42, 0.29])
-- @
--
-- Right [0.1, 0.8, 0.1]
-- 
-- To be honest I am not sure why I can't use the 'maxent' version to solve
-- this type of problem, but it doesn't work. I'm still learning
-- 
maxentLinear :: (forall a. Floating a => ([[a]], [a])) -- ^ a matrix A and column vector b
      -> Either (Result, Statistics) [Double] -- ^ Either the a discription of what wrong or the probability distribution 
maxentLinear params = result where
   obj :: Floating a => [a] -> a
   obj = uncurry objectiveFuncLinear params 

   fs :: [[Double]]
   fs = fst params

   -- hmm maybe there is a better way to get rid of the defaulting
   guess = U.fromList $ replicate 
       (length fs) ((1.0 :: Double) / (fromIntegral $ length fs)) 

   result = case unsafePerformIO (optimize (defaultParameters { printFinal = False } )
                       0.05 guess 
                       (toFunction obj)
                       (toGradient obj)
                       Nothing) of
       (vs, ToleranceStatisfied, _) -> Right $ linProbs fs (S.toList vs)
       (_, x, y) -> Left (x, y)


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
type Constraint a = (ExpectationFunction a, a)

-- | A function that takes an index and value and returns a value.
--   See 'average' and 'variance' for examples.
type ExpectationFunction a = (a -> a)

-- | The main entry point for computing discrete maximum entropy distributions.
--   Where the constraints are all moment constraints. 
maxent :: (forall a. Floating a => ([a], [Constraint a])) -- ^ A pair of values that the distributions is over and the constraints
       -> Either (Result, Statistics) [Double] -- ^ Either the a discription of what wrong or the probability distribution 
maxent params = result where
    obj :: Floating a => [a] -> a
    obj = uncurry (objectiveFunc values) fsmoments
    
    values :: Floating a => [a]
    values = fst params
    
    constraints :: Floating a => [(ExpectationFunction a, a)]
    constraints = snd params
    
    fsmoments :: Floating a => ([ExpectationFunction a], [a])
    fsmoments = unzip constraints 
    
    fs :: [Double -> Double]
    fs = fst fsmoments
    
    -- hmm maybe there is a better way to get rid of the defaulting
    guess = U.fromList $ replicate 
        (length fs) (1.0 :: Double) 
    
    result = case unsafePerformIO (optimize (defaultParameters { printFinal = False }) 
                        0.001 guess 
                        (toFunction obj)
                        (toGradient obj)
                        Nothing) of
        (vs, ToleranceStatisfied, _) -> Right $ probs values fs (S.toList vs)
        (_, x, y) -> Left (x, y)



    
    


  
