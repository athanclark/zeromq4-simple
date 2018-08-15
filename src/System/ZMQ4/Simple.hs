{-# LANGUAGE
    MultiParamTypeClasses
  , FunctionalDependencies
  , GeneralizedNewtypeDeriving
  , DeriveGeneric
  , TupleSections
  , OverloadedStrings
  #-}

module System.ZMQ4.Simple where

import System.ZMQ4.Monadic
  ( ZMQ, Socket, Flag (SendMore)
  , Req (..), Rep (..), Dealer (..), Router (..))
import qualified System.ZMQ4.Monadic as Z

import Data.Restricted (toRestricted)
import Data.Hashable (Hashable)
import Data.ByteString (ByteString)
import qualified Data.UUID as UUID
import Data.UUID.V4 (nextRandom)
import qualified Data.ByteString.Lazy as LBS
import Control.Monad.IO.Class (liftIO)

import GHC.Generics (Generic)



-- * Types

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
class Sendable from to aux | from to -> aux where
  send :: to -> aux -> Socket z from -> ByteString -> ZMQ z ()

instance Sendable Req Rep () where
  send Rep () s x = Z.send s [] x

instance Sendable Req Router () where
  send Router () s x = do
    Z.send s [SendMore] ""
    Z.send s [] x

instance Sendable Router Req ZMQIdent where
  send Req (ZMQIdent addr) s x = do
    Z.send s [SendMore] addr
    Z.send s [SendMore] ""
    Z.send s [] x


-- | Receive a message over a ZMQ socket
class Receivable from to aux | from to -> aux where
  receive :: to -> Socket z from -> ZMQ z (aux, ByteString)

instance Receivable Req Rep () where
  receive Rep s = ((),) <$> Z.receive s

instance Receivable Req Router () where
  receive Router s = do
    _ <- Z.receive s
    ((),) <$> Z.receive s

instance Receivable Router Req ZMQIdent where
  receive Req s = do
    addr <- ZMQIdent <$> Z.receive s
    _ <- Z.receive s
    x <- Z.receive s
    pure (addr, x)
