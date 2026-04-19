{-# LANGUAGE NoFieldSelectors #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Model where

import Miso.WebSocket as WS
import Data.Map.Strict (Map)
import GHC.Generics
import Data.Aeson as Aeson
import qualified Data.IntSet as S

import Types

-- | Main application model
data Model = Model
    { gameState :: Maybe GameState
    , localPlayerId :: Maybe Int
    , wsConnection :: Maybe WS.WebSocket
    , lastInputKeys :: Maybe S.IntSet
    , wasAlive :: Bool
    , prevCells :: [CellType]
    } deriving (Eq)

data GameState = GameState
    { status :: String
    , map :: GameMap
    , players :: Map Int Player
    , bombs :: [BombData]
    , time_left :: Int
    , winner :: Maybe Int
    } deriving (Eq, Show, Generic, ToJSON, FromJSON)

initModel :: Model
initModel = Model
    { gameState = Nothing
    , localPlayerId = Nothing
    , wsConnection = Nothing
    , lastInputKeys = Nothing
    , wasAlive = True
    , prevCells = []
    }