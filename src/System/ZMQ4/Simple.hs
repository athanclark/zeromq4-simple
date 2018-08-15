{-# LANGUAGE
    MultiParamTypeClasses
  , FunctionalDependencies
  , GeneralizedNewtypeDeriving
  , DeriveGeneric
  , TupleSections
  , OverloadedStrings
  , DataKinds
  , KindSignatures
  #-}

module System.ZMQ4.Simple where

import System.ZMQ4.Monadic
  ( ZMQ, Socket, Flag (SendMore)
  , Req (..), Rep (..), Dealer (..), Router (..)
  , Pub (..), Sub (..), XPub (..), XSub (..)
  , Pull (..), Push (..))
import qualified System.ZMQ4.Monadic as Z

import Data.Restricted (toRestricted)
import Data.Hashable (Hashable)
import Data.ByteString (ByteString)
import qualified Data.UUID as UUID
import Data.UUID.V4 (nextRandom)
import qualified Data.ByteString.Lazy as LBS
import Data.List.NonEmpty (NonEmpty (..))
import Control.Monad.IO.Class (liftIO)

import GHC.Generics (Generic)



-- * Types

data Ordinal = Ord1 | OrdN


newtype ZMQIdent = ZMQIdent {getZMQIdent :: ByteString}
  deriving (Show, Eq, Ord, Generic, Hashable)

setRandomIdentity :: Socket z from -> ZMQ z ()
setRandomIdentity s = do
  clientId <- liftIO nextRandom

  case toRestricted $ LBS.toStrict $ UUID.toByteString clientId of
    Nothing -> error "couldn't restrict uuid"
    Just ident -> Z.setIdentity ident s



-- * Classes

-- | Send a message over a ZMQ socket
class Sendable from (fromOrd :: Ordinal) to (toOrd :: Ordinal) aux
  | from to -> fromOrd toOrd aux where
  send :: to -> aux -> Socket z from -> NonEmpty ByteString -> ZMQ z ()

instance Sendable Pub Ord1 Sub OrdN () where
  send Sub () s xs = Z.sendMulti s xs

instance Sendable XPub Ord1 Sub OrdN () where
  send Sub () s xs = Z.sendMulti s xs

instance Sendable Req Ord1 Rep Ord1 () where
  send Rep () s xs = Z.sendMulti s xs

instance Sendable Req OrdN Router Ord1 () where
  send Router () s xs = Z.sendMulti s xs

instance Sendable Router Ord1 Req OrdN ZMQIdent where
  send Req (ZMQIdent addr) s (x:|xs) = Z.sendMulti s (addr :| "":x:xs)


-- | Receive a message over a ZMQ socket
class Receivable from (fromOrd :: Ordinal) to (toOrd :: Ordinal) aux
  | from to -> fromOrd toOrd aux where
  receive :: to -> Socket z from -> ZMQ z (Maybe (aux, NonEmpty ByteString))

instance Receivable Sub OrdN Pub Ord1 () where
  receive Pub s = receiveBasic s

instance Receivable Sub OrdN XPub Ord1 () where
  receive XPub s = receiveBasic s

instance Receivable Req Ord1 Rep Ord1 () where
  receive Rep s = receiveBasic s

instance Receivable Req OrdN Router Ord1 () where
  receive Router s = receiveBasic s

instance Receivable Router Ord1 Req OrdN ZMQIdent where
  receive Req s = do
    xs <- Z.receiveMulti s
    case xs of
      (addr:_:x:xs') -> pure (Just (ZMQIdent addr, x :| xs'))
      _ -> pure Nothing


receiveBasic :: Z.Receiver t => Socket s t -> ZMQ s (Maybe ((), NonEmpty ByteString))
receiveBasic s = do
  xs <- Z.receiveMulti s
  case xs of
    (x:xs') -> pure (Just ((), x :| xs'))
    _ -> pure Nothing
