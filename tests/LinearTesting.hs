{-# LANGUAGE FlexibleInstances, BangPatterns, Rank2Types, StandaloneDeriving #-}

module LinearTesting where

import Test.QuickCheck
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector.Storable as S
import Numeric.AD
import GHC.IO                   (unsafePerformIO)
import Data.Traversable
import Data.List (transpose, intersperse)
import Control.Applicative
import Numeric.MaxEnt.Linear
import qualified Data.Packed.Matrix as M
import Numeric.LinearAlgebra
import Numeric
import Debug.Trace
import qualified Data.Vector.Storable as S
import Foreign.Storable

class Approximate a where
    (=~=) :: a -> a -> Bool

data InvalidLinearConstraints a = InvalidLinearConstraints {
        imatrix :: [[a]],
        ioutput :: [a]
    }
    deriving(Eq, Show)

instance Arbitrary (InvalidLinearConstraints Double) where
    arbitrary = sized $ \size -> do
    
        matrix <- vectorOf size (vector size)
        unnormalizedProbs <- vector size
        
        badSum <- suchThat arbitrary (/= 1.0) 
        
        let probs    = let total = sum unnormalizedProbs in 
                                map (\x -> badSum * (x/total)) unnormalizedProbs
            hmatrix     = M.fromLists matrix
            hprobs      = M.fromLists $ transpose [probs]
            inputVector = hmatrix `multiply` hprobs
            
        return . InvalidLinearConstraints matrix . (map head) . M.toLists $ inputVector

data ValidLinearConstraints = VLC
  { unVLC :: forall a. Floating a => ([[a]], [a]) }

toLC :: ValidLinearConstraints -> LinearConstraints
toLC vlc = LC $ unVLC vlc

deriving instance Eq ValidLinearConstraints
    
instance Approximate Double where
    x =~= y = abs (x - y) < 0.1

instance Approximate a => Approximate [a] where
    xs =~= ys = all id . zipWith (=~=) xs $ ys
    
instance (Approximate a, Storable a) => Approximate (S.Vector a) where
    xs =~= ys = S.all id . S.zipWith (=~=) xs $ ys
    
instance Approximate (ValidLinearConstraints) where
    (VLC (mx, ox)) =~= (VLC (my, oy)) =
        (mx :: [[Double]]) =~= my && (ox :: [Double]) =~= oy

traceIt x = trace (show x) x

printRow :: [Double] -> String
printRow xs = "[" ++ 
   concat (intersperse "," (map (\x -> showFFloat (Just 6) x "") xs)) ++ "]"

instance Show (ValidLinearConstraints) where
   show (VLC (xss, xs)) = "matrix = [" ++ 
       concat (intersperse "," $ map printRow xss) ++ "]\n output = " ++ printRow xs

normalize xs = let total = sum xs in map (/total) xs

instance Arbitrary (ValidLinearConstraints) where
    arbitrary = sized $ \size' -> do
        
        let size = size' + 1
        
        matrix <- vectorOf size (vectorOf size (suchThat arbitrary (>0.0))) :: Gen [[Double]]
        unnormalizedProbs <- vectorOf size (suchThat arbitrary (>0.0)) :: Gen [Double]
        
        let probs       = normalize unnormalizedProbs
            --matrix' :: (Floating a) => [a]
            matrix'     = map normalize matrix
            hmatrix     = M.fromLists matrix'
            hprobs      = M.fromLists $ transpose [probs]
            inputVector = hmatrix `multiply` hprobs
            output = map head $ M.toLists inputVector
            
        return $ VLC (map (map (fromRational . toRational)) matrix', map (fromRational . toRational) output)
        
--
--toPoly :: RealFloat a => LinearConstraints Double -> LinearConstraints a
--toPoly (LC x y) =
--     LC (map (map (fromRational . toRational)) x) 
--                        (map (fromRational . toRational) y)

solvableSystemsAreSolvable :: ValidLinearConstraints -> Bool
solvableSystemsAreSolvable vlc =
    case linear 0.0000005 (toLC vlc) of
        Right _ -> True
        Left  _ -> False
      
traceItNote msg x = trace (msg ++ " " ++ show x) x

probsSumToOne :: ValidLinearConstraints -> Bool
probsSumToOne vlc =
    case linear 0.000005 (toLC vlc) of
        Right ps -> case 1.0 =~= S.sum ps of
            True -> True
            False -> trace ("new probs" ++ show ps) False
        Left _   -> False
        
solutionFitsConstraints :: ValidLinearConstraints -> Bool
solutionFitsConstraints vlc = let lc = toLC vlc in
    case linear 0.000005 lc of
        Right ps -> result where
            (x, y) = unLC lc
            result = ((map head) . M.toLists $ inputVector) =~= y
    
            hmatrix     = M.fromLists x
            hprobs      = M.fromLists $ transpose [S.toList ps]
            inputVector = hmatrix <> hprobs
            
            
        Left _   -> False

--This is not the test I want ..  but it does seem to work
-- TODO you want to test against the original probs which should 
-- have less then or equal to the estimated
entropyIsGreaterOrEqual :: ValidLinearConstraints -> Bool
entropyIsGreaterOrEqual vlc = let lc = toLC vlc in
    case linear 0.000005 lc of
        Right ps -> result where
            entropy xs = negate . sum . map (\x -> x * log x) $ xs
            
            yEntropy         = entropy . snd $ unLC lc
            estimatedEntropy = entropy $ S.toList ps
            
            result = yEntropy >= estimatedEntropy
        Left  _  -> error "failed!"


--probabilityNeighborhood ps = 

-- TODO make this
entropyIsMaximum :: ValidLinearConstraints -> Bool
entropyIsMaximum vlc = let lc = toLC vlc in
    case linear 0.000005 lc of
        Right ps -> result where
            entropy xs = negate . sum . map (\x -> x * log x) $ xs
            
            yEntropy         = entropy . snd $ unLC lc
            estimatedEntropy = entropy $ S.toList ps
            
            result = yEntropy >= estimatedEntropy
        Left  _  -> error "failed!"


-- also if it is a maximum a small change in either direction that still fits the constraints
-- should not lower the entropy
-- 

     
    

--main = quickCheck probsSumToOne
