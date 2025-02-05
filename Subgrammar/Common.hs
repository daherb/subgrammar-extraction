module Subgrammar.Common where

import PGF
import qualified GF
import GF.Support
import System.FilePath
import System.Directory
import Canonical
import System.FilePath((</>),(<.>))
import Data.LinearProgram
import qualified Data.Map.Lazy as Map
import Data.List
import qualified Text.XML.Expat.SAX as X
import qualified Data.ByteString.Lazy as BS
import System.Clock
import System.Process( callCommand )
import System.IO.Temp (emptySystemTempFile )
import Data.Char

-- | Enable debug output
debug :: Bool
debug = True

-- | Character to mark a hole in a tree
hole :: String
hole = "0"

-- | Examples are strings
type Example = String

-- | Forests are lists of trees
type Forest = [Tree]

-- | A grammar is a combination of a pgf file and the pathes to the concrete syntaxes
data Grammar = Grammar { pgf :: PGF, concs :: [FilePath]} -- The PGF and file pathes to all concrete syntaxes

-- | A solution is the score of the optimal solution together with the list of included rules
type Solution = (Double,[String])

-- | An objective function is a combination of a function and a direction
data ObjectiveFunction a = OF { fun :: [(String,[(String,a)])] -> ObjectiveFunc String Int, direction :: Direction }

-- | A problem contains trees, rules and a linear programming logical formula
type Problem = LP String Int -- Problem { trees :: [(String,[String])], rules :: [String] , formula :: LPM String Int ()}

problemConstraints :: Problem -> [Constraint String Int]
problemConstraints = constraints

-- Constants -> Have to be updated
path_to_exemplum :: String
path_to_exemplum = "../mulle-grammars/Exemplum"
rgl_path :: String
rgl_path = "../gf-rgl/src"
rgl_subdirs :: String
rgl_subdirs = "abstract common prelude english"


{- | Taken from MissingH:Data.String.Utils:
Given a delimiter and a list of items (or strings), join the items
by using the delimiter.

Example:

> join "|" ["foo", "bar", "baz"] -> "foo|bar|baz"
-}
join :: [a] -> [[a]] -> [a]
join delim l = concat (intersperse delim l)

-- | Splits a list at a delimiter element
split :: Eq a => [a] -> [a] -> [[a]]
split delim l =
  split' l []
  where
    split' [] [] = []
    split' [] acc = [reverse acc]
    split' l'@(hd:tl) acc
      | isPrefixOf delim l' = (reverse acc):(split' (drop (length delim) l') [])
      | otherwise = split' tl (hd:acc)

-- | Converts a GF tree to a list of rules
flatten :: Tree -> [String]
flatten tree = maybe [] (\(f,ts) -> (showCId f):(concatMap flatten ts)) $ unApp tree

-- | Objective function counting the number of trees
numTrees :: ObjectiveFunction a
numTrees = OF numTreesOF Min
  where
    numTreesOF :: [(String,[(String,a)])] -> ObjectiveFunc String Int
    numTreesOF tags = linCombination $ nub [(1,t) | (_,ts) <- tags,(t,_) <- ts]

-- | Solves a problem using a given objective function
solve :: Problem ->  IO Solution
solve problem =
  do
    -- Uses the MIP solver to get real binary variables, the simplex solver can return numbers between 0 and 1
    (_,solution) <- glpSolveVars mipDefaults problem
    return $ maybe (-1,[]) (\(val,vars) -> (val,[var | (var,vval) <- Map.toList vars,vval > 0])) solution

solveCPLEX :: Problem -> IO Solution
solveCPLEX problem =
  do
    lpFile <- emptySystemTempFile "problem.lp"
    writeLP lpFile problem
    solution <- runCPLEX "~/opt/cplex/cplex/bin/x86-64_linux/cplex" lpFile
    return $ solution Map.! 0
    
-- | Given a grammar translate an example into a set of syntax trees
examplesToForests :: Grammar -> Language -> [Example] -> [Forest]
examplesToForests grammar language examples =
  [parse (pgf grammar) language (startCat $ pgf grammar) example | example <- examples]


-- | Function to create a new grammar from an old grammar and a solution
generateGrammar :: Grammar -> Solution -> Bool -> IO Grammar
generateGrammar grammar solution merge =
  do
    let lib_path = ".":rgl_path:[rgl_path</>subdir | subdir <- words rgl_subdirs] :: [FilePath]
        options = modifyFlags (\f -> f { optLibraryPath = lib_path })    
        -- read old concrete syntax
    canon <- loadCanonicalGrammar lib_path $ concs grammar
    let
        -- filter the grammar
        canon' = if merge then
                   mergeRules [split "#" r | r <- snd solution, '#' `elem` r] canon -- (filterGrammar (snd solution) [] canon)
                   else filterGrammar (snd solution) [] canon
        -- rename the grammar
        canon'' = renameGrammar (getAbsName canon ++ "Sub") canon'
        concs' = getConcNames canon''
    -- write new concrete syntax
    outdir <- fst <$> splitFileName <$> (canonicalizePath $ head $ concs grammar)
    let outdir' = outdir </> "subgrammar"
    createDirectoryIfMissing True outdir'
    writeGrammar outdir' canon''
    -- compile and load new pgf
    pgf' <- GF.compileToPGF options [outdir' </> c <.> "gf" | c <- concs']
    let options' = modifyFlags (\f -> f { optOutputDir = Just outdir' })
    GF.writePGF options' pgf'
    return $ Grammar pgf' concs'

-- | Helper function to time computations
startTimer :: IO TimeSpec
startTimer =
  getTime ProcessCPUTime

stopTimer :: TimeSpec -> IO Integer
stopTimer start =
  do
    stop <- getTime ProcessCPUTime
    return $ fromIntegral (sec $ diffTimeSpec start stop)
  
time :: IO () -> IO Integer
time f =
  do
    putStrLn ">Timer> Start"
    t1 <- startTimer
    f
    putStrLn ">Timer> Stop"
    diff <- stopTimer t1
    putStrLn $ ">Timer> Difference " ++ (show diff)
    return diff
    
-- | Function to check if a variable is a rule, i.e. if it is neither a variable for a sentence, a tree or a constraint
isRule :: String -> Bool
isRule = not . isId
  where
    isId [] = True
    isId ('s':is) = isId is
    isId ('t':is) = isId is
    isId ('p':is) = isId is
    isId (c  :is) | isDigit c = isId is
    isId _  = False

-- Functions to use CPLEX as a solver
-- | Function to run cplex on a LP problem
runCPLEX :: FilePath -> FilePath -> IO (Map.Map Int (Double,[String]))
runCPLEX cplex lpFile = 
  do
    infile <- emptySystemTempFile "cplex.in"
    outfile <- emptySystemTempFile "cplex.sol"
    cplexOut <- emptySystemTempFile "cplex.out"
    writeFile infile $ unlines $
      [ "r " ++ lpFile
      , "opt"
--      , "display solution variables *"
      , "xecute rm -f " ++ outfile
      , "write " ++ outfile ++ " all"
      , "quit"
      ]
    putStrLn $ "+++ Starting CPLEX... " ++ infile
    callCommand $ cplex ++ " < " ++ infile ++ " > " ++ cplexOut ++ " 2>&1"
    putStrLn $ "+++ Reading solution... " ++ outfile
    s <- BS.readFile outfile
    return $ xmlToRules s

-- | Function to parse a CPLEX solution from a XML file
xmlToRules :: BS.ByteString -> Map.Map Int (Double,[String])
xmlToRules s =
  saxToRules $ X.parse X.defaultParseOptions s
  where
    saxToRules :: [X.SAXEvent String String] -> Map.Map Int (Double,[String])
    saxToRules = findSolution
    findSolution :: [X.SAXEvent String String] -> Map.Map Int (Double,[String])
    findSolution [] = Map.empty
    findSolution (X.StartElement "CPLEXSolution" _:es) =
      findHeader es
    findSolution (_:es) =
      findSolution es
    findHeader :: [X.SAXEvent String String] -> Map.Map Int (Double,[String])
    findHeader (X.StartElement "header" as:es)
      | not $ elem ("solutionName","incumbent") as =
        let
          Just index = read <$> lookup "solutionIndex" as
          Just obj = read <$> lookup "objectiveValue" as
        in
          findVariable (index,obj) es
      | otherwise = findSolution es
    findHeader (_:es) =
      findHeader  es
    findVariable :: (Int,Double) -> [X.SAXEvent String String] -> Map.Map Int (Double,[String])
    findVariable (ct,obj) (X.StartElement "variable" as:es)
      | elem ("value","1") as = 
        let 
          rs = findVariable (ct,obj) es
          Just v = read <$> lookup "name" as
        in Map.alter (Just . maybe (obj,[v]) (\(o,l) -> (o,v:l))) ct rs        
      | otherwise = findVariable (ct,obj) es
    findVariable _ (X.EndElement "CPLEXSolution":es) =
      findSolution es
    findVariable p (e:es) =
      findVariable p es
