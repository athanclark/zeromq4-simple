{-# LANGUAGE
    MultiParamTypeClasses
  , FunctionalDependencies
  , GeneralizedNewtypeDeriving
  , DeriveGeneric
  , TupleSections
  , OverloadedStrings
  , DataKinds
  , KindSignatures
  , TypeFamilies
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

-- | The numerity of `from`
type family Ordinance from to :: Ordinal where
  Ordinance Pub Sub    = Ord1
  Ordinance XPub Sub   = Ord1
  Ordinance Sub Pub    = OrdN
  Ordinance Sub XPub   = OrdN
  Ordinance Req Rep    = Ord1
  Ordinance Rep Req    = Ord1
  Ordinance Req Router = OrdN
  Ordinance Router Req = Ord1
  Ordinance Rep Dealer = OrdN
  Ordinance Dealer Rep = Ord1



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
class Sendable from to aux
  | from to -> aux where
  send :: to -> aux -> Socket z from -> NonEmpty ByteString -> ZMQ z ()

instance Sendable Pub Sub () where
  send Sub () s xs = Z.sendMulti s xs

instance Sendable XPub Sub () where
  send Sub () s xs = Z.sendMulti s xs

instance Sendable Req Rep () where
  send Rep () s xs = Z.sendMulti s xs

instance Sendable Req Router () where
  send Router () s xs = Z.sendMulti s xs

instance Sendable Router Req ZMQIdent where
  send Req (ZMQIdent addr) s (x:|xs) = Z.sendMulti s (addr :| "":x:xs)

instance Sendable Rep Dealer () where
  send Dealer () s xs = Z.sendMulti s xs

instance Sendable Dealer Rep () where
  send Rep () s (x:|xs) = Z.sendMulti s ("" :| x:xs)


-- | Receive a message over a ZMQ socket
class Receivable from to aux
  | from to -> aux where
  receive :: to -> Socket z from -> ZMQ z (Maybe (aux, NonEmpty ByteString))

instance Receivable Sub Pub () where
  receive Pub s = receiveBasic s

instance Receivable Sub XPub () where
  receive XPub s = receiveBasic s

instance Receivable Req Rep () where
  receive Rep s = receiveBasic s

instance Receivable Req Router () where
  receive Router s = receiveBasic s

instance Receivable Router Req ZMQIdent where
  receive Req s = do
    xs <- Z.receiveMulti s
    case xs of
      (addr:_:x:xs') -> pure (Just (ZMQIdent addr, x :| xs'))
      _ -> pure Nothing

instance Receivable Rep Dealer () where
  receive Dealer s = receiveBasic s

instance Receivable Dealer Rep () where
  receive Rep s = do
    xs <- Z.receiveMulti s
    case xs of
      (_:x:xs') -> pure (Just ((), x :| xs'))
      _ -> pure Nothing




receiveBasic :: Z.Receiver t => Socket s t -> ZMQ s (Maybe ((), NonEmpty ByteString))
receiveBasic s = do
  xs <- Z.receiveMulti s
  case xs of
    (x:xs') -> pure (Just ((), x :| xs'))
    _ -> pure Nothing
