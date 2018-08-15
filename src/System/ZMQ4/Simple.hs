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
  , ConstraintKinds
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
import Data.Constraint (Constraint)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)

import GHC.Generics (Generic)



-- * Types

data Ordinal = Ord1 | OrdN | Ord1OrN

-- | The numerity of `from`
type family Ordinance from to :: Ordinal where
  Ordinance Pub Sub       = 'Ord1
  Ordinance XPub Sub      = 'Ord1
  Ordinance Sub Pub       = 'OrdN
  Ordinance Sub XPub      = 'OrdN
  Ordinance Req Rep       = 'Ord1
  Ordinance Rep Req       = 'Ord1
  Ordinance Req Router    = 'OrdN
  Ordinance Router Req    = 'Ord1
  Ordinance Rep Dealer    = 'OrdN
  Ordinance Dealer Rep    = 'Ord1
  Ordinance Dealer Router = 'Ord1OrN
  Ordinance Router Dealer = 'Ord1OrN


type family NeedsIdentity from to :: Constraint where
  NeedsIdentity Req Router = ()
  NeedsIdentity Dealer Rep = ()
  NeedsIdentity Dealer Router = ()



newtype ZMQIdent = ZMQIdent {getZMQIdent :: ByteString}
  deriving (Show, Eq, Ord, Generic, Hashable)

newUUIDIdentity :: IO ZMQIdent
newUUIDIdentity =
  (ZMQIdent . LBS.toStrict . UUID.toByteString) <$> nextRandom


setIdentity :: NeedsIdentity from to => to -> Socket z from -> ZMQIdent -> ZMQ z Bool
setIdentity _ s (ZMQIdent clientId) =
  case toRestricted clientId of
    Nothing -> pure False
    Just ident -> True <$ Z.setIdentity ident s

setUUIDIdentity :: NeedsIdentity from to => to -> Socket z from -> ZMQ z ()
setUUIDIdentity to s = do
  ident <- liftIO newUUIDIdentity
  worked <- setIdentity to s ident
  when (not worked) (error "couldn't restrict uuid")



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

instance Sendable Dealer Router () where
  send Router () s (x:|xs) = Z.sendMulti s ("" :| x:xs)

instance Sendable Router Dealer ZMQIdent where
  send Dealer (ZMQIdent addr) s (x:|xs) = Z.sendMulti s (addr :| "":x:xs)


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

instance Receivable Dealer Router () where
  receive Router s = do
    xs <- Z.receiveMulti s
    case xs of
      (_:x:xs') -> pure (Just ((), x :| xs'))
      _ -> pure Nothing

instance Receivable Router Dealer ZMQIdent where
  receive Dealer s = do
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
