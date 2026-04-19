-- Types.hs
{-# LANGUAGE NoFieldSelectors #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Types where

import Data.Aeson
import GHC.Generics
import Data.Scientific (toBoundedInteger)

newtype GameMap = GameMap {grid :: [[CellType]]}
    deriving (Eq, Show, Generic, ToJSON, FromJSON)

data CellType
    = Empty
    | HardBlock
    | SoftBlock
    | Bomb
    | Explosion
    | FireUp
    | BombUp
    | SpeedUp
    deriving (Eq, Show, Generic, ToJSON)

instance FromJSON CellType where
    parseJSON = withScientific "CellType" $ \n ->
        case toBoundedInteger n :: Maybe Int of
            Just 0 -> pure Empty
            Just 1 -> pure HardBlock
            Just 2 -> pure SoftBlock
            Just 3 -> pure Bomb
            Just 4 -> pure Explosion
            Just 5 -> pure FireUp
            Just 6 -> pure BombUp
            Just 7 -> pure SpeedUp
            _      -> fail $ "Unknown CellType: " ++ show n

data Player = Player
    { id :: Int
    , x :: Double
    , y :: Double
    , is_alive :: Bool
    } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data BombData = BombData
    { owner_id :: Int
    , x :: Double
    , y :: Double
    } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Direction
    = UP
    | DOWN
    | LEFT
    | RIGHT
    deriving (Eq, Show, Generic, ToJSON, FromJSON)