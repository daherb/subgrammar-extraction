module Subgrammar.Common where

import PGF
-- import qualified GF.Grammar.Canonical
import qualified GF
import GF.Support
import System.FilePath
import System.Directory
import Canonical
import System.FilePath((</>),(<.>))
import Filesystem (isDirectory)
import Control.Monad.LPMonad
import Data.LinearProgram
import Data.LinearProgram.GLPK
import qualified Data.Map.Lazy as Map

import System.Clock

-- | Examples are strings
type Example = String

-- | Forests are lists of trees
type Forest = [Tree]

-- | A grammar is a combination of a pgf file and the pathes to the concrete syntaxes
data Grammar = Grammar { pgf :: PGF, concs :: [FilePath]} -- The PGF and file pathes to all concrete syntaxes

-- | A solution is the score of the optimal solution together with the list of included rules
type Solution = (Double,[String])

-- | An objective function is a combination of a function and a direction
data ObjectiveFunction = OF { fun :: Problem -> ObjectiveFunc String Int, direction :: Direction }

-- | A problem contains trees, rules and a linear programming logical formula
data Problem = Problem { trees :: [(String,[String])], rules :: [String] , formula :: LPM String Int ()}

instance Show Problem where
  show p = showProblem p

showProblem :: Problem -> String
showProblem (Problem ts rs f) = "Problem { trees = " ++ show ts ++ ", rules = " ++ show rs ++ ", ++ formula = " ++ (show $ execLPM f) ++ "}"

-- | Objective function counting the number of trees
numTrees :: ObjectiveFunction
numTrees = OF numTreesOF Max
  where
    numTreesOF :: Problem -> ObjectiveFunc String Int
    numTreesOF (Problem trees _ _) = linCombination [(1,t) | (s,ts) <- trees,t <- ts]

-- | Solves a problem using a given objective function
solve :: Problem -> ObjectiveFunction -> IO Solution
solve problem (OF fun direction) =
  do
    let lp = execLPM $
          do
            setDirection direction
            setObjective (fun problem)
            formula problem
    (code,solution) <- glpSolveVars simplexDefaults lp
    return $ maybe (-1,[]) (\(val,vars) -> (val,[var | (var,vval) <- Map.toList vars,vval == 1])) solution

-- | Given a grammar translate an example into a set of syntax trees
examplesToForests :: Grammar -> Language -> [Example] -> [Forest]
examplesToForests grammar language examples =
  [parse (pgf grammar) language (startCat $ pgf grammar) example | example <- examples]

-- | Function to create a new grammar from an old grammar and a solution
generateGrammar :: Grammar -> Solution -> IO Grammar
generateGrammar grammar solution =
  do
    let rgl_path = "/home/herb/src/foreign/gf/gf-rgl/src"
    let subdirs = "abstract common prelude english"
    let lib_path = ".":rgl_path:[rgl_path</>subdir | subdir <- words subdirs] :: [FilePath]
    putStrLn $ "###" ++ show lib_path
    -- read old concrete syntax
    let options = modifyFlags (\f -> f { optLibraryPath = lib_path
                                       })
    (utc,(concname,gfgram)) <- GF.batchCompile options $ concs grammar
    let absname = GF.srcAbsName gfgram concname
        canon = GF.grammar2canonical noOptions absname gfgram
        -- filter the grammar
        canon' = filterGrammar (snd solution) canon
        -- rename the grammar
        canon'' = renameGrammar (getAbsName canon ++ "Sub") canon'
        concs' = getConcNames canon''
    -- write new concrete syntax
    outdir <- fst <$> splitFileName <$> (canonicalizePath $ head $ concs grammar)
    let outdir' = outdir </> "sub"
    writeGrammar outdir' canon''
    -- compile and load new pgf
    pgf' <- GF.compileToPGF options [outdir' </> c <.> "gf" | c <- concs']
    let options' = modifyFlags (\f -> f { optOutputDir = Just outdir' })
    GF.writePGF options' pgf'
    return $ Grammar pgf' concs'

-- | Helper function to time computations
time :: IO () -> IO Integer
time f =
  do
    putStrLn ">Timer> Start"
    t1 <- getTime ProcessCPUTime
    f
    t2 <- getTime ProcessCPUTime
    putStrLn ">Timer> Stop"
    let diff = fromIntegral (sec $ diffTimeSpec t1 t2)
    putStrLn $ ">Timer> Difference " ++ (show diff)
    return diff
    
