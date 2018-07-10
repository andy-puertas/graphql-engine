{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}

module Hasura.GraphQL.Transport.WebSocket.Protocol
  ( OperationId(..)
  , StartMsg(..)
  , StopMsg(..)
  , ClientMsg(..)
  , ServerMsg(..)
  , encodeServerMsg
  , DataMsg(..)
  , ErrorMsg(..)
  , ConnErrMsg(..)
  , CompletionMsg(..)
  ) where

import qualified Data.Aeson                             as J
import qualified Data.Aeson.Casing                      as J
import qualified Data.Aeson.TH                          as J
import qualified Data.ByteString.Lazy                   as BL

import           Hasura.GraphQL.Transport.HTTP.Protocol
import           Hasura.Prelude

newtype OperationId
  = OperationId { unOperationId :: Text }
  deriving (Show, Eq, J.ToJSON, J.FromJSON, Hashable)

data StartMsg
  = StartMsg
  { _smId      :: !OperationId
  , _smPayload :: !GraphQLRequest
  } deriving (Show, Eq)
$(J.deriveFromJSON (J.aesonDrop 3 J.snakeCase) ''StartMsg)

data StopMsg
  = StopMsg
  { _stId :: OperationId
  } deriving (Show, Eq)
$(J.deriveFromJSON (J.aesonDrop 3 J.snakeCase) ''StopMsg)

data ClientMsg
  = CMConnInit
  | CMStart !StartMsg
  | CMStop !StopMsg
  | CMConnTerm
  deriving (Show, Eq)

instance J.FromJSON ClientMsg where
  parseJSON = J.withObject "ClientMessage" $ \obj -> do
    t <- obj J..: "type"
    case t of
      "connection_init" -> return CMConnInit
      "start" -> CMStart <$> J.parseJSON (J.Object obj)
      "stop" -> CMStop <$> J.parseJSON (J.Object obj)
      "connection_terminate" -> return CMConnTerm
      _ -> fail $ "unexpected type for ClientMessage: " <> t

-- server to client messages

data DataMsg
  = DataMsg
  { _dmId      :: !OperationId
  , _dmPayload :: !GQResp
  } deriving (Show, Eq)

data ErrorMsg
  = ErrorMsg
  { _emId      :: !OperationId
  , _emPayload :: !J.Value
  } deriving (Show, Eq)

newtype CompletionMsg
  = CompletionMsg { unCompletionMsg :: OperationId }
  deriving (Show, Eq)

newtype ConnErrMsg
  = ConnErrMsg { unConnErrMsg :: Text }
  deriving (Show, Eq, J.ToJSON, J.FromJSON)

data ServerMsg
  = SMConnAck
  | SMConnKeepAlive
  | SMConnErr !ConnErrMsg
  | SMData !DataMsg
  | SMErr !ErrorMsg
  | SMComplete !CompletionMsg
  deriving (Show, Eq)

data ServerMsgType
  = SMT_GQL_CONNECTION_ACK
  | SMT_GQL_CONNECTION_KEEP_ALIVE
  | SMT_GQL_CONNECTION_ERROR
  | SMT_GQL_DATA
  | SMT_GQL_ERROR
  | SMT_GQL_COMPLETE
  deriving (Eq)

instance Show ServerMsgType where
  show = \case
    SMT_GQL_CONNECTION_ACK        -> "connection_ack"
    SMT_GQL_CONNECTION_KEEP_ALIVE -> "ka"
    SMT_GQL_CONNECTION_ERROR      -> "connection_error"
    SMT_GQL_DATA                  -> "data"
    SMT_GQL_ERROR                 -> "error"
    SMT_GQL_COMPLETE              -> "complete"

instance J.ToJSON ServerMsgType where
  toJSON = J.toJSON . show

encodeServerMsg :: ServerMsg -> BL.ByteString
encodeServerMsg msg =
  mkJSONObj $ case msg of

  SMConnAck ->
    [encTy SMT_GQL_CONNECTION_ACK]

  SMConnKeepAlive ->
    [encTy SMT_GQL_CONNECTION_KEEP_ALIVE]

  SMConnErr connErr ->
    [ encTy SMT_GQL_CONNECTION_ERROR
    , ("payload", J.encode connErr)
    ]

  SMData (DataMsg opId payload) ->
    [ encTy SMT_GQL_DATA
    , ("id", J.encode opId)
    , ("payload", encodeGQResp payload)
    ]

  SMErr (ErrorMsg opId payload) ->
    [ encTy SMT_GQL_ERROR
    , ("id", J.encode opId)
    , ("payload", J.encode payload)
    ]

  SMComplete compMsg ->
    [ encTy SMT_GQL_COMPLETE
    , ("id", J.encode $ unCompletionMsg compMsg)
    ]

  where
    encTy ty = ("type", J.encode ty)
