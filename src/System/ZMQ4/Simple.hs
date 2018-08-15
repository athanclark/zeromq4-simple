{-# LANGUAGE
    MultiParamTypeClasses
  , FunctionalDependencies
  , GeneralizedNewtypeDeriving
  , DeriveGeneric
  , OverloadedStrings
  #-}

module System.ZMQ4.Simple where

import System.ZMQ4.Monadic
  ( ZMQ, Socket, Flag (SendMore)
  , Req (..), Router (..))
import qualified System.ZMQ4.Monadic as Z

import Data.Hashable (Hashable)
import Data.ByteString (ByteString)
import GHC.Generics (Generic)



-- * Types

newtype ZMQIdent = ZMQIdent {getZMQIdent :: ByteString}
  deriving (Show, Eq, Ord, Generic, Hashable)


class Sendable from to aux | from to -> aux where
  send :: to -> aux -> Socket z from -> ByteString -> ZMQ z ()

instance Sendable Req Router () where
  send Router () s x = do
    Z.send s [SendMore] ""
    Z.send s [] x

instance Sendable Router Req ZMQIdent where
  send Req (ZMQIdent addr) s x = do
    Z.send s [SendMore] addr
    Z.send s [SendMore] ""
    Z.send s [] x


class Receivable from to aux | from to -> aux where
  receive :: to -> Socket z from -> ZMQ z (aux, ByteString)

instance Receivable Req Router () where
  receive Router s = do
    _ <- Z.receive s
    (\x -> ((), x)) <$> Z.receive s

instance Receivable Router Req ZMQIdent where
  receive Req s = do
    addr <- ZMQIdent <$> Z.receive s
    _ <- Z.receive s
    x <- Z.receive s
    pure (addr, x)
