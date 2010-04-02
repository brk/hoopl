{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE RankNTypes, ScopedTypeVariables, GADTs, EmptyDataDecls, PatternGuards, TypeFamilies, NamedFieldPuns #-}
module Test (parseTest, evalTest, optTest) where

import Control.Monad.Error

import ConstProp
import Eval  (evalProg, ErrorM)
import Hoopl
import IR
import Live
import OptSupport
import Parse (parseCode)
import Simplify

parse :: String -> String -> ErrorM [Proc]
parse file text =
  case parseCode file text of
    Left  err -> throwError $ show err
    Right p   -> return p

parseTest :: String -> IO ()
parseTest file =
  do text <- readFile file
     case parse file text of
       Left err -> putStrLn err
       Right p  -> mapM (putStrLn . showProc) p >> return ()

evalTest' :: String -> String -> ErrorM String
evalTest' file text =
  do procs   <- parse file text
     (_, vs) <- testProg procs
     return $ "returning: " ++ show vs
  where
    testProg procs@(Proc {name, args} : _) = evalProg procs vsupply name (toV args)
    testProg _ = throwError "No procedures in test program"
    toV args = [I n | (n, _) <- zip [3..] args]
    vsupply = [I x | x <- [5..]]

evalTest :: String -> IO ()
evalTest file =
  do text    <- readFile file
     case evalTest' file text of
       Left err -> putStrLn err
       Right  s -> putStrLn s

optTest' :: String -> String -> ErrorM [Proc]
optTest' file text =
  do procs  <- parse file text
     mapM optProc procs
  where
    optProc proc@(Proc {body}) = return $ proc { body = body'' }
      where
        fuel        = 999999999
        rewriteFwd  = analyseAndRewriteFwd constLattice varHasLit
                          (combine constProp simplify) RewriteDeep 
                          (fact_bot constLattice) body
        (_, body')  = runFuelMonad rewriteFwd fuel 0
        rewriteBwd  = analyseAndRewriteBwd liveLattice liveness deadAsstElim RewriteDeep
                          (mkFactBase []) body'
        (_, body'') = runFuelMonad rewriteBwd fuel 0

optTest :: String -> IO ()
optTest file =
  do text    <- readFile file
     case optTest' file text of
       Left err -> putStrLn err
       Right p  -> mapM (putStrLn . showProc) p >> return ()



{-- Properties to test:

  0. Is the fixpoint complete (maps all blocks to facts)?
  1. Is the computed fixpoint actually a fixpoint?
  2. All code in paper run.
  3. Michael Franz (UCI) random test generating.

--}