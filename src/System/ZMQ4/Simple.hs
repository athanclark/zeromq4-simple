{-# LANGUAGE
    MultiParamTypeClasses
  , FunctionalDependencies
  , GeneralizedNewtypeDeriving
  , DeriveGeneric
  , OverloadedStrings
  #-}

module System.ZMQ4.Simple where

import System.ZMQ4.Monadic
  ( ZMQ, Socket, Flag (SendMore), Req (..), Router (..))
import qualified System.ZMQ4.Monadic as Z

import Data.Hashable (Hashable)
import Data.ByteString (ByteString)
import GHC.Generics (Generic)



-- * Types

newtype ZMQIdent = ZMQIdent {getZMQIdent :: ByteString}
  deriving (Show, Eq, Ord, Generic, Hashable)


class Sendable from to aux | from to -> aux where
  send :: from -> to -> aux -> Socket z from -> ByteString -> ZMQ z ()

instance Sendable Req Router () where
  send Req Router () s x = do
    Z.send s [SendMore] ""
    Z.send s [] x

instance Sendable Router Req ZMQIdent where
  send Router Req (ZMQIdent addr) s x = do
    Z.send s [SendMore] addr
    Z.send s [SendMore] ""
    Z.send s [] x
