{-# LANGUAGE ScopedTypeVariables, TemplateHaskell #-}

import Database.Cassandra.CQL as CQL
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Serialize as S
import Data.Word (Word8)
import Control.Concurrent (threadDelay)
import Control.Applicative ((<$>))
import System.Process (runCommand, terminateProcess)
import System.Environment (getExecutablePath, getArgs)

import Codeec.Types
import Codeec.Shim
import Codeec.Client
import Codeec.Marshall
import Codeec.NameService.SimpleBroker

data BankAccount = Deposit_ Int | Withdraw_ Int | GetBalance_ deriving Show

instance Serialize BankAccount_ where
  put (Deposit_ v) = putTwoOf S.put S.put (0::Word8, v)
  put (Withdraw_ v) = putTwoOf S.put S.put (1::Word8, v)
  put (GetBalance_) = error "serializing GetBalance"
  get = do
    (i::Word8,v::Int) <- getTwoOf S.get S.get
    case i of
      0 -> return $ Deposit_ v
      1 -> return $ Withdraw_ v
      otherwise -> error "deserializing GetBalance"

instance CasType BankAccount_ where
  getCas = do
    r <- decode . unBlob <$> getCas
    case r of
      Left _ -> error "Parse fail"
      Right v -> return $ v
  putCas = putCas . Blob . encode
  casType _ = CBlob

instance Storable BankAccount_ where

type Res a = (a, Maybe BankAccount_)

deposit :: [BankAccount_] -> Int -> Res ()
deposit _ amt = ((), Just $ Deposit_ amt)

withdraw :: [BankAccount_] -> Int -> Res Bool
withdraw ctxt amt =
  let (bal, _) = getBalance ctxt ()
  in if bal > amt
     then (True, Just $ Withdraw_ amt)
     else (False, Nothing)

getBalance :: [BankAccount_] -> () -> Res Int
getBalance ops () =
  let v = foldl acc 0 ops
  in (v, Nothing)
  where
    acc s (Deposit_ i) = s + i
    acc s (Withdraw_ i) = s - i
    acc s GetBalance_ = s


data Kind = B | C | S | D deriving (Read, Show)

fePort :: Int
fePort = 5558

bePort :: Int
bePort = 5559


mkRDT ''BankAccount_
-- data BankAccount = BankAccount deriving Show
-- instance OTC BankAccount where

main :: IO ()
main = do
  (kindStr:_) <- getArgs
  let k :: Kind = read kindStr
  case k of
    B -> startBroker (Frontend $ "tcp://*:" ++ show fePort)
                     (Backend $ "tcp://*:" ++ show bePort)
    S -> do
      let dtLib = Map.fromList [(BankAccount,
                    Map.fromList [(Deposit,  (mkGeneric deposit, Un)),
                                  (Withdraw, (mkGeneric withdraw, Un)),
                                  (GetBalance, (mkGeneric getBalance, Un))])]
      runShimNode dtLib (Backend $ "tcp://localhost:" ++ show bePort) 5560
    C -> do
      sess <- beginSession $ Frontend $ "tcp://localhost:" ++ show fePort

      putStrLn "Client : performing deposit"
      r::() <- invoke sess BankAccount Deposit (100::Int)

      putStrLn "Client : performing withdraw"
      r::(Maybe Int) <- invoke sess BankAccount Withdraw (10::Int)
      putStrLn $ show r

      putStrLn "Client : performing getBalance"
      r::Int <- invoke sess BankAccount GetBalance ()
      putStrLn $ show r
      endSession sess
    D -> do
      progName <- getExecutablePath
      putStrLn "Driver : Starting broker"
      b <- runCommand $ progName ++ " B"
      putStrLn "Driver : Starting server"
      s <- runCommand $ progName ++ " S"
      putStrLn "Driver : Starting client"
      c <- runCommand $ progName ++ " C"
      threadDelay 5000000
      mapM_ terminateProcess [b,s,c]
