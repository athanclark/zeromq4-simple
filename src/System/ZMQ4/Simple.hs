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
  , UndecidableInstances
  #-}

{- |
Module: System.ZMQ4.Simple
Copyright: (c) 2018, 2019 Athan Clark
License: BSD-3
Maintainer: athan.clark@gmail.com
Portability: GHC

Some simple type-level constraints over the 'System.ZMQ4.Monadic' module - it uses
type families and phantom types to enforce semantically correct connections with
respect to ZeroMQ's design.
-}


module System.ZMQ4.Simple where

import System.ZMQ4.Monadic
  ( ZMQ, SocketType
  , Req (..), Rep (..), Dealer (..), Router (..)
  , Pub (..), Sub (..), XPub (..), XSub (..)
  , Pull (..), Push (..), Pair (..))
import qualified System.ZMQ4.Monadic as Z

import Data.Restricted (toRestricted)
import Data.Hashable (Hashable)
import Data.ByteString (ByteString)
import qualified Data.UUID as UUID
import Data.UUID.V4 (nextRandom)
import qualified Data.ByteString.Lazy as LBS
import Data.List.NonEmpty (NonEmpty (..))
import Data.Constraint (Constraint)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, decode)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)

import GHC.Generics (Generic)
import GHC.TypeLits (TypeError, ErrorMessage (..))



-- * Types

-- | A measure of how many peers a connection can have.
data Ordinal = Ord1 | OrdN

-- | How many `to`'s' a `from` can have.
type family Ordinance from to (loc :: Location) :: Ordinal where
  Ordinance Pair Pair     'Bound     = 'Ord1
  Ordinance Pair Pair     'Connected = 'Ord1
  Ordinance Pub Sub       'Bound     = 'Ord1
  Ordinance XPub Sub      'Bound     = 'Ord1
  Ordinance Sub Pub       'Connected = 'OrdN
  Ordinance Sub XPub      'Connected = 'OrdN
  Ordinance Pub XSub      'Connected = 'OrdN
  Ordinance XSub Pub      'Bound     = 'Ord1
  Ordinance Req Rep       'Connected = 'Ord1
  Ordinance Rep Req       'Bound     = 'Ord1
  Ordinance Req Router    'Connected = 'OrdN
  Ordinance Router Req    'Bound     = 'Ord1
  Ordinance Rep Dealer    'Connected = 'OrdN
  Ordinance Dealer Rep    'Bound     = 'Ord1
  Ordinance Dealer Router 'Connected = 'OrdN
  Ordinance Dealer Router 'Bound     = 'Ord1
  Ordinance Router Dealer 'Connected = 'OrdN
  Ordinance Router Dealer 'Bound     = 'Ord1
  Ordinance Pull Push     'Connected = 'OrdN
  Ordinance Pull Push     'Bound     = 'Ord1
  Ordinance Push Pull     'Connected = 'OrdN
  Ordinance Push Pull     'Bound     = 'Ord1

-- | Connections that need a 'ZMQIdent'.
type family NeedsIdentity from to :: Constraint where
  NeedsIdentity Req Router = ()
  NeedsIdentity Dealer Rep = ()
  NeedsIdentity Dealer Router = ()

-- | Whether a socket is a client or a server.
data Location = Connected | Bound

-- | The type of sockets that can be bound to a host.
type family Bindable from :: Constraint where
  Bindable Pair = ()
  Bindable Rep = ()
  Bindable Router = ()
  Bindable Dealer = ()
  Bindable Pub = ()
  Bindable XPub = ()
  Bindable XSub = ()
  Bindable Pull = ()
  Bindable Push = ()

-- | The kind of sockets that can be connected to a (remote) host.
type family Connectable from :: Constraint where
  Connectable Pair = ()
  Connectable Req = ()
  Connectable Rep = ()
  Connectable Router = ()
  Connectable Dealer = ()
  Connectable Sub = ()
  Connectable Pub = ()
  Connectable XSub = ()
  Connectable XPub = ()
  Connectable Pull = ()
  Connectable Push = ()

-- | Simple wrapper with extra phantom types.
newtype Socket z from to (loc :: Location)
  = Socket {getSocket :: Z.Socket z from}

-- | Legal socket connection combinations
type family IsLegal from to :: Constraint where
  IsLegal Pair Pair = ()
  IsLegal Sub Pub = ()
  IsLegal Pub Sub = ()
  IsLegal XSub Pub = TypeError ('Text "Not legal ZeroMQ socket: For some reason xsub/pub isn't working")
  IsLegal XPub Sub = ()
  IsLegal Pub XSub = TypeError ('Text "Not legal ZeroMQ socket: For some reason pub/xsub isn't working")
  IsLegal Sub XPub = ()
  IsLegal XPub XSub = ()
  IsLegal XSub XPub = ()
  IsLegal Push Pull = ()
  IsLegal Pull Push = ()
  IsLegal Req Rep = ()
  IsLegal Rep Req = ()
  IsLegal Req Router = ()
  IsLegal Router Req = ()
  IsLegal Rep Dealer = ()
  IsLegal Dealer Rep = ()
  IsLegal Router Dealer = ()
  IsLegal Dealer Router = ()
  IsLegal Router Router = ()
  IsLegal Dealer Dealer = ()
  IsLegal from to = TypeError ('Text "Not legal ZeroMQ socket")

-- | Build a socket.
socket :: SocketType from
       => IsLegal from to
       => from -> to -> ZMQ z (Socket z from to loc)
socket from _ = Socket <$> Z.socket from

-- | Bind that socket to a host.
bind :: Bindable from => Socket z from to 'Bound -> String -> ZMQ z ()
bind (Socket s) x = Z.bind s x

-- | Connect that socket to a (remote) host.
connect :: Connectable from => Socket z from to 'Connected -> String -> ZMQ z ()
connect (Socket s) x = Z.connect s x

-- | Represents some kind of identifier for a ZeroMQ socket.
newtype ZMQIdent = ZMQIdent {getZMQIdent :: ByteString}
  deriving (Show, Eq, Ord, Generic, Hashable)

-- | Generate a 'ZMQIdent' via UUID.
newUUIDIdentity :: IO ZMQIdent
newUUIDIdentity =
  (ZMQIdent . LBS.toStrict . UUID.toByteString) <$> nextRandom

-- | Tell ZeroMQ that you want your socket to be identified by this 'ZMQIdent'.
setIdentity :: NeedsIdentity from to
            => Socket z from to loc
            -> ZMQIdent -> ZMQ z Bool
setIdentity (Socket s) (ZMQIdent clientId) =
  case toRestricted clientId of
    Nothing -> pure False
    Just ident -> True <$ Z.setIdentity ident s

-- | Set a random 'ZMQIdent' via UUID.
setUUIDIdentity :: NeedsIdentity from to => Socket z from to loc -> ZMQ z ()
setUUIDIdentity s = do
  ident <- liftIO newUUIDIdentity
  worked <- setIdentity s ident
  when (not worked) (error "couldn't restrict uuid")


-- * Classes

-- | Send a message over a ZMQ socket - @aux@ is possibly necessary additional information to send.
class Sendable from to aux
  | from to -> aux where
  send :: aux -> Socket z from to loc -> NonEmpty ByteString -> ZMQ z ()

sendJson :: Sendable from to aux => ToJSON a => aux -> Socket z from to loc -> a -> ZMQ z ()
sendJson a s x = send a s (LBS.toStrict (encode x) :| [])

instance Sendable Pub Sub () where
  send () (Socket s) xs = Z.sendMulti s xs

instance Sendable XPub Sub () where
  send () (Socket s) xs = Z.sendMulti s xs

instance Sendable Pub XSub () where
  send () (Socket s) xs = Z.sendMulti s xs

instance Sendable Req Rep () where
  send () (Socket s) xs = Z.sendMulti s xs

instance Sendable Rep Req () where
  send () (Socket s) xs = Z.sendMulti s xs

instance Sendable Req Router () where
  send () (Socket s) xs = Z.sendMulti s xs

instance Sendable Router Req ZMQIdent where
  send (ZMQIdent addr) (Socket s) (x:|xs) = Z.sendMulti s (addr :| "":x:xs)

instance Sendable Rep Dealer () where
  send () (Socket s) xs = Z.sendMulti s xs

instance Sendable Dealer Rep () where
  send () (Socket s) (x:|xs) = Z.sendMulti s ("" :| x:xs)

instance Sendable Dealer Router () where
  send () (Socket s) (x:|xs) = Z.sendMulti s ("" :| x:xs)

instance Sendable Router Dealer ZMQIdent where
  send (ZMQIdent addr) (Socket s) (x:|xs) = Z.sendMulti s (addr :| "":x:xs)


-- | Receive a message over a ZMQ socket - @aux@ is possibly necessary additional information sent.
class Receivable from to aux
  | from to -> aux where
  receive :: Socket z from to loc -> ZMQ z (Maybe (aux, NonEmpty ByteString))

receiveJson :: Receivable from to aux => FromJSON a => Socket z from to loc -> ZMQ z (Maybe (aux, a))
receiveJson s = do
  mX <- receive s
  case mX of
    Nothing -> pure Nothing
    Just (aux, msg :| _) -> case decode (LBS.fromStrict msg) of
      Nothing -> pure Nothing
      Just x -> pure (Just (aux,x))

instance Receivable Sub Pub () where
  receive (Socket s) = receiveBasic s

instance Receivable Sub XPub () where
  receive (Socket s) = receiveBasic s

instance Receivable XSub Pub () where
  receive (Socket s) = receiveBasic s

instance Receivable Req Rep () where
  receive (Socket s) = receiveBasic s

instance Receivable Rep Req () where
  receive (Socket s) = receiveBasic s

instance Receivable Req Router () where
  receive (Socket s) = receiveBasic s

instance Receivable Router Req ZMQIdent where
  receive (Socket s) = do
    xs <- Z.receiveMulti s
    case xs of
      (addr:_:x:xs') -> pure (Just (ZMQIdent addr, x :| xs'))
      _ -> pure Nothing

instance Receivable Rep Dealer () where
  receive (Socket s) = receiveBasic s

instance Receivable Dealer Rep () where
  receive (Socket s) = do
    xs <- Z.receiveMulti s
    case xs of
      (_:x:xs') -> pure (Just ((), x :| xs'))
      _ -> pure Nothing

instance Receivable Dealer Router () where
  receive (Socket s) = do
    xs <- Z.receiveMulti s
    case xs of
      (_:x:xs') -> pure (Just ((), x :| xs'))
      _ -> pure Nothing

instance Receivable Router Dealer ZMQIdent where
  receive (Socket s) = do
    xs <- Z.receiveMulti s
    case xs of
      (addr:_:x:xs') -> pure (Just (ZMQIdent addr, x :| xs'))
      _ -> pure Nothing


receiveBasic :: Z.Receiver t => Z.Socket s t -> ZMQ s (Maybe ((), NonEmpty ByteString))
receiveBasic s = do
  xs <- Z.receiveMulti s
  case xs of
    (x:xs') -> pure (Just ((), x :| xs'))
    _ -> pure Nothing
