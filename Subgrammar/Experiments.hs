module Subgrammar.Experiments where

import System.Random (mkStdGen)
import Data.List
import Data.Maybe
-- import System.FilePath((</>))
-- import Control.Concurrent.ParallelIO
import Control.Concurrent.ParallelIO.Local
-- import System.Random.Shuffle
import Test.QuickCheck
import PGF
import Subgrammar.Common
import Subgrammar.GFSubtree

-- | Returns the rules and the associated precision and recall
recreateFromExamples :: Grammar -> Language -> Grammar -> [Example] -> Int -> ObjectiveFunction [(String, [String])] -> IO ([String],Double,Double)
recreateFromExamples g_r lang_r g_0 examples maxSubtreeSize ofun =
  do
    -- putStrLn $ ">>> Working on " ++ show examples
    let forests = examplesToForests g_r lang_r examples
    -- create csp
    -- putStrLn $ ">>> Create problem"
    let problem = forestsToProblem forests maxSubtreeSize ofun
    -- solve problem
    -- putStrLn $ ">>> Solve problem"
    solution <- solve problem
    -- get the results
    -- putStrLn $ ">>> Analyze results"
    let splitted = filter (/= hole) $ concat [split "#" r|r <- snd solution]
    let precision = (fromIntegral $ length (intersect (map showCId $ functions $ pgf g_0) splitted)) / (fromIntegral $ length splitted)
    let recall = (fromIntegral $ length (intersect (map showCId $ functions $ pgf g_0) splitted)) / (fromIntegral $ length (functions $ pgf g_0))
    return (splitted, precision,recall)

-- | Return the examples used, the rules created, precision and recall
recreateGrammar :: Grammar -> Language -> Grammar -> Int -> Int -> Int -> Int -> ObjectiveFunction [(String, [String])] -> IO [([String],[String],Double,Double)]
recreateGrammar g_r lang_r g_0 exampleCount treeDepth maxSubtreeSize repetitions ofun = do
  let gen = mkStdGen 4 -- chosen by a fair dice role
  putStrLn "  >>> Generate trees"
  let trees = take exampleCount $ generateRandomDepth gen (pgf g_0) (startCat $ pgf g_0) (Just treeDepth)
  putStrLn "  >>> Linearize trees"
  let sentences = [linearize (pgf g_r) lang_r t | t <- trees]
  putStrLn "  >>> Randomize sentences"
--  let shuffledSentences = if repetitions > 1 then map (\l -> shuffle' l (length l) gen) $ replicate repetitions sentences else [sentences]
  shuffledSentences <- sequence (replicate (fromIntegral repetitions) (generate (shuffle sentences)))
  putStrLn "  >>> Start process"
  -- sequence
  withPool 4 $ \p -> parallel p [(\(r,prec,re) -> (es,r,prec,re)) <$> recreateFromExamples g_r lang_r g_0 es maxSubtreeSize ofun | shuffled <- shuffledSentences,
                                 l <- [1..length shuffled-1], let es = (take l shuffled)]

recreateExemplum :: FilePath -> IO ()
recreateExemplum outFile = 
  do
    putStrLn ">>> Load RGL"
    pgf_r_eng <- readPGF "pgfs/LangEng.pgf"
    pgf_r_ger <- readPGF "pgfs/LangGer.pgf"
    pgf_r_fin <- readPGF "pgfs/LangFin.pgf"
    pgf_r_swe <- readPGF "pgfs/LangSwe.pgf"
    putStrLn ">>> Load Exemplum"
    pgf_0_eng <- readPGF $ "pgfs/ExemplumEng.pgf"
    pgf_0_ger <- readPGF $ "pgfs/ExemplumGer.pgf"
    pgf_0_fin <- readPGF $ "pgfs/ExemplumFin.pgf"
    pgf_0_swe <- readPGF $ "pgfs/ExemplumSwe.pgf"
    putStrLn ">>> Work Work Work"
    writeFile outFile =<< ("\"ExampleCount\";\"TreeDepth\",\"SubtreeSize\";\"ObjectiveFunction\";\"Precission\";\"Recall\";\"Rules\";\"Examples\"\n" ++) <$> unlines <$> sequence
      [(recreateGrammar (Grammar lpgf_r []) (fromJust $ readLanguage lname) (Grammar lpgf_0 []) exampleCount treeDepth maxSubtreeSize repetitions ofun >>=
         (\results -> return $ concat
                      [(show exampleCount ++ ";" ++ show treeDepth ++ ";" ++ show maxSubtreeSize ++ ";" ++ show repetitions ++ ";" ++ show oname ++ ";" ++
                        show prec ++ ";" ++ show recall ++ ";" ++ (show $ show rules) ++ ";" ++ (show $ show examples)) | (examples,rules,prec,recall) <- results]
         )
       ) :: IO String
      | exampleCount <- [1..20], treeDepth <- [4..6], maxSubtreeSize <- [1..3], repetitions <- [1..5],
        (oname,ofun) <- [("numTrees",numTrees),("numRules",numRules)], (lname,lpgf_r,lpgf_0) <- [("LangEng",pgf_r_eng,pgf_0_eng),("LangGer",pgf_r_ger,pgf_0_ger),("LangFin",pgf_r_fin,pgf_0_fin),("LangSwe",pgf_r_swe,pgf_0_swe)]]
      -- | exampleCount <- [1..10], treeDepth <- [4..5], maxSubtreeSize <- [1..2], repetitions <- [1..2],
      --   (oname,ofun) <- [("numRules",numRules)],(lname,lpgf_r,lpgf_0) <- [("LangEng",pgf_r_eng,pgf_0_eng),("LangGer",pgf_r_ger,pgf_0_ger),("LangFin",pgf_r_fin,pgf_0_fin),("LangSwe",pgf_r_swe,pgf_0_swe)]]

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
