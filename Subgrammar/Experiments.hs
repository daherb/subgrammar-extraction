module Subgrammar.Experiments where

import System.Random (mkStdGen)
import Data.List
import Data.Maybe
import Test.QuickCheck
import PGF
import Subgrammar.Common
import Subgrammar.GFSubtree
import Control.Monad
import Data.LinearProgram.GLPK.IO
import System.IO

-- global parameters
-- Enables debugging
debug = False
-- how many times reshuffle the sentences
reshufflingCount = 3
-- how many examples in total
maxExampleCount = 10
-- lower bound for the set of examples
minExampleCount = 1

-- | Returns the rules and the associated precision and recall
recreateFromExamples :: Grammar -> Language -> Grammar -> [Example] -> Int -> ObjectiveFunction [(String, [String])] -> IO (Integer,[String],Double,Double)
recreateFromExamples g_r lang_r g_0 examples maxSubtreeSize ofun =
  do
    start <- startTimer
    -- putStrLn $ ">>> Working on " ++ show examples
    let forests = examplesToForests g_r lang_r examples
    -- create csp
    when debug $ putStrLn $ ">>> Create problem"
    let problem = forestsToProblem forests maxSubtreeSize ofun
    -- solve problem
    when debug $ putStrLn $ ">>> Solve problem"
    when debug $ writeLP "/tmp/problem.lp" problem
    solution <- solve problem
    -- get the results
    when debug $ putStrLn $ ">>> Analyze results"
    let splitted = filter (/= hole) $ concat [split "#" r|r <- snd solution]
    -- Only look at the "rules" in the results that are actually in the resource grammar
    let precision = (fromIntegral $ length (intersect (map showCId $ functions $ pgf g_0) splitted)) / (fromIntegral $ length (intersect (map showCId $ functions $ pgf g_r) splitted))
    let recall = (fromIntegral $ length (intersect (map showCId $ functions $ pgf g_0) splitted)) / (fromIntegral $ length (functions $ pgf g_0))
    timer <- stopTimer start
    return (timer,splitted, precision,recall)

-- | Return the examples used, the rules created, precision and recall
recreateGrammar :: Grammar -> Language -> Grammar -> Int -> Int -> Int -> ObjectiveFunction [(String, [String])] -> IO [(Int,Int,Integer,[String],[String],Double,Double)]
recreateGrammar g_r lang_r g_0 treeDepth maxSubtreeSize repetitions ofun = do
  let gen = mkStdGen 4 -- chosen by a fair dice role
  when debug $ putStrLn "  >>> Generate trees"
  let trees = take maxExampleCount $ nub $ generateRandomDepth gen (pgf g_0) (startCat $ pgf g_0) (Just treeDepth)
  when debug $ putStrLn "  >>> Linearize trees"
  let sentences = [linearize (pgf g_r) lang_r t | t <- trees]
  when debug $ putStrLn "  >>> Randomize sentences"
  shuffledSentences <- sequence (replicate (fromIntegral repetitions) (generate (shuffle sentences)))
  when debug (putStrLn $ show shuffledSentences)
  when debug $ putStrLn "  >>> Start process"
  sequence [(\(timer,rules,prec,recall) -> (count,exampleCount,timer,examples,rules,prec,recall)) <$> recreateFromExamples g_r lang_r g_0 examples maxSubtreeSize ofun
           | (count,shuffled) <- zip [1..] shuffledSentences,
             exampleCount <- [minExampleCount..length shuffled],
             let examples = (take exampleCount shuffled)
           ]

recreateExemplum :: FilePath -> IO ()
recreateExemplum outFile = 
  do
    putStrLn ">>> Load RGL"
    pgf_r_eng <- readPGF "pgfs/LangEng.pgf"
    pgf_r_ger <- readPGF "pgfs/LangGer.pgf"
    pgf_r_fin <- readPGF "pgfs/LangFin.pgf"
    pgf_r_swe <- readPGF "pgfs/LangSwe.pgf"
    when debug $ putStrLn ">>> Load Exemplum"
    pgf_0_eng <- readPGF $ "pgfs/ExemplumEng.pgf"
    pgf_0_ger <- readPGF $ "pgfs/ExemplumGer.pgf"
    pgf_0_fin <- readPGF $ "pgfs/ExemplumFin.pgf"
    pgf_0_swe <- readPGF $ "pgfs/ExemplumSwe.pgf"
    when debug $ putStrLn ">>> Work Work Work"
    withFile outFile WriteMode
      (\handle ->
          do
            hSetBuffering handle NoBuffering
            hPutStrLn handle "Language;ShuffleNo;ExampleCount;TreeDepth;SubtreeSize;ObjectiveFunction;Time;Precision;Recall;Rules;Examples"
            sequence 
              [(recreateGrammar (Grammar lpgf_r []) (fromJust $ readLanguage lname) (Grammar lpgf_0 []) treeDepth maxSubtreeSize reshufflingCount ofun >>=
                 (\results ->
                    hPutStrLn handle $ unlines
                      [(lname ++ ";" ++ show shuffleNo ++ ";" ++ show exampleCount ++ ";" ++ show treeDepth ++ ";" ++
                        show maxSubtreeSize ++ ";" ++ oname ++ ";" ++ show time ++ ";" ++ show prec ++ ";" ++
                        show recall ++ ";" ++ show rules ++ ";" ++ show examples)
                      | (shuffleNo,exampleCount,time,examples,rules,prec,recall) <- results]
                 )
               )
              | treeDepth <- [4..5], maxSubtreeSize <- [1..2],
                (oname,ofun) <- [("numTrees",numTrees)], -- ("numRules",numRules)]
                (lname,lpgf_r,lpgf_0) <- [("LangEng",pgf_r_eng,pgf_0_eng)]] -- ("LangGer",pgf_r_ger,pgf_0_ger),("LangFin",pgf_r_fin,pgf_0_fin),("LangSwe",pgf_r_swe,pgf_0_swe)]
      )
    return ()
      
compareTreebank :: Grammar -> Language -> [(String,Tree)] -> Int -> ObjectiveFunction [(String,[String])] -> IO (Double,Double)
compareTreebank g_r lang_r treeBank maxSubtreeSize ofun =
  do
    let
      examples = map fst treeBank
      forests = examplesToForests g_r lang_r examples
      problem = forestsToProblem forests maxSubtreeSize ofun
    solution <- solve problem
    g' <- generateGrammar g_r solution
    let results = [t `elem` parse (pgf g') lang_r (startCat $ pgf g') e | (e,t) <- treeBank]
    -- TODO: Compute results
    return (0,0)
