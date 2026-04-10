{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Game state data types and JSON serialization
module Game.Types where

import GHC.Generics (Generic)
import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), (.=), object, (.:))
import Data.Aeson.Key (fromString)
import Data.Aeson.Types (Parser, withObject, withText, (.:?), typeMismatch)
import Data.Text (Text)
import Data.Vector (Vector)
import qualified Data.Vector as V
import Data.IntMap (IntMap)
import qualified Data.IntMap as IntMap
import Data.Maybe (fromMaybe)

-- | Tile types in the game
data TileType
    = Empty      -- ^ 0 = Empty space
    | HardWall   -- ^ 1 = Indestructible wall
    | SoftWall   -- ^ 2 = Destructible wall
    | BombTile   -- ^ 3 = Bomb
    | Explosion  -- ^ 4 = Explosion
    | FireUp     -- ^ 5 = Fire power-up
    | BombUp     -- ^ 6 = Bomb power-up
    | SpeedUp    -- ^ 7 = Speed power-up
    deriving (Show, Eq, Enum, Generic)

-- | Power-up types
data PowerUp = FireUpPU | BombUpPU | SpeedUpPU
    deriving (Show, Eq)

-- | Apply power-up to player
applyPowerUp :: PowerUp -> Player -> Player
applyPowerUp FireUpPU player = player { playerBombRange = playerBombRange player + 1 }
applyPowerUp BombUpPU player = player { maxBombs = maxBombs player + 1 }
applyPowerUp SpeedUpPU player = player { playerSpeed = playerSpeed player + 0.05 }

-- | Map tile type to power-up
tileToPowerUp :: TileType -> Maybe PowerUp
tileToPowerUp FireUp  = Just FireUpPU
tileToPowerUp BombUp  = Just BombUpPU
tileToPowerUp SpeedUp = Just SpeedUpPU
tileToPowerUp _       = Nothing

-- Custom JSON instances for TileType
instance FromJSON TileType where
    parseJSON (Number n) = case n of
        0 -> return Empty
        1 -> return HardWall
        2 -> return SoftWall
        3 -> return BombTile
        4 -> return Explosion
        5 -> return FireUp
        6 -> return BombUp
        7 -> return SpeedUp
        _ -> fail $ "Unknown tile type: " ++ show n
    parseJSON invalid = typeMismatch "TileType (integer)" invalid

instance ToJSON TileType where
    toJSON Empty     = toJSON (0 :: Int)
    toJSON HardWall  = toJSON (1 :: Int)
    toJSON SoftWall  = toJSON (2 :: Int)
    toJSON BombTile  = toJSON (3 :: Int)
    toJSON Explosion = toJSON (4 :: Int)
    toJSON FireUp    = toJSON (5 :: Int)
    toJSON BombUp    = toJSON (6 :: Int)
    toJSON SpeedUp   = toJSON (7 :: Int)

-- | Player data type
data Player = Player
    { playerId      :: Int           -- ^ Unique player ID
    , playerX       :: Float         -- ^ X coordinate
    , playerY       :: Float         -- ^ Y coordinate
    , playerAlive   :: Bool          -- ^ Is player alive
    , maxBombs      :: Int           -- ^ Maximum bombs allowed
    , currentBombs  :: Int           -- ^ Current bomb count
    , playerBombRange :: Int         -- ^ Explosion range
    , playerSpeed   :: Float         -- ^ Movement speed
    , playerPoints  :: Int           -- ^ Player score 
    } deriving (Show, Eq, Generic)


instance FromJSON Player where
    parseJSON = withObject "Player" $ \obj -> do
        idVal        <- obj .: "id"
        xVal         <- obj .: "x"
        yVal         <- obj .: "y"
        aliveVal     <- obj .: "is_alive"
        maxBombsVal  <- obj .: "max_bombs"
        currBombsVal <- obj .: "current_bombs"
        rangeVal     <- obj .: "bomb_range"
        speedVal     <- obj .: "speed"
        pointsVal    <- obj .: "points"
        return $ Player idVal xVal yVal aliveVal maxBombsVal currBombsVal rangeVal speedVal pointsVal

instance ToJSON Player where
    toJSON player = object
        [ "id"             .= playerId player
        , "x"              .= playerX player
        , "y"              .= playerY player
        , "is_alive"       .= playerAlive player
        , "max_bombs"      .= maxBombs player
        , "current_bombs"  .= currentBombs player
        , "bomb_range"     .= playerBombRange player
        , "speed"          .= playerSpeed player
        , "points"         .= playerPoints player
        ]

-- | Bomb data type
data Bomb = Bomb
    { bombX       :: Int         -- ^ X coordinate
    , bombY       :: Int         -- ^ Y coordinate
    , bombOwnerId :: Int         -- ^ Player ID who placed the bomb
    , bombTimer   :: Int         -- ^ Time until explosion
    , bombRange   :: Int         -- ^ Explosion range
    } deriving (Show, Eq, Generic)

-- Custom JSON instances for Bomb
instance FromJSON Bomb where
    parseJSON = withObject "Bomb" $ \obj -> do
        xVal      <- obj .: "x"
        yVal      <- obj .: "y"
        ownerVal  <- obj .: "owner_id"
        timerVal  <- obj .: "timer"
        rangeVal  <- obj .: "range"
        return $ Bomb xVal yVal ownerVal timerVal rangeVal

instance ToJSON Bomb where
    toJSON bomb = object
        [ "x"        .= bombX bomb
        , "y"        .= bombY bomb
        , "owner_id" .= bombOwnerId bomb
        , "timer"    .= bombTimer bomb
        , "range"    .= bombRange bomb
        ]

-- | Game map as a 2D vector of tiles
type GameMap = Vector (Vector TileType)

-- | Explosion tracking data (for scoring and duration)
data ExplosionInfo = ExplosionInfo
    { explosionX     :: Int     -- ^ X coordinate
    , explosionY     :: Int     -- ^ Y coordinate
    , explosionOwner :: Int     -- ^ Player ID who caused the explosion
    , explosionTimer :: Int     -- ^ Time until explosion clears (milliseconds)
    } deriving (Show, Eq, Generic)

-- Custom JSON instances for ExplosionInfo
instance FromJSON ExplosionInfo where
    parseJSON = withObject "ExplosionInfo" $ \obj -> do
        xVal     <- obj .: "x"
        yVal     <- obj .: "y"
        ownerVal <- obj .: "owner"
        timerVal <- obj .: "timer"
        return $ ExplosionInfo xVal yVal ownerVal timerVal

instance ToJSON ExplosionInfo where
    toJSON exp = object
        [ "x"      .= explosionX exp
        , "y"      .= explosionY exp
        , "owner"  .= explosionOwner exp
        , "timer"  .= explosionTimer exp
        ]

-- | Game state
data GameState = GameState
    { gameStatus    :: String          -- ^ "waiting", "playing", "game_over"
    , gameMap       :: GameMap         -- ^ Game map
    , players       :: IntMap Player   -- ^ All players in the game
    , bombs         :: [Bomb]          -- ^ Active bombs
    , explosions    :: [ExplosionInfo] -- ^ Active explosions
    , onePlayerSince:: Maybe Int       -- ^ Time when only one player left (milliseconds)
    , timeLeft      :: Int             -- ^ Time remaining (milliseconds)
    , winner        :: Maybe Int       -- ^ Winner ID (if game over)
    } deriving (Show, Eq, Generic)

-- Custom JSON instances for GameState
instance FromJSON GameState where
    parseJSON = withObject "GameState" $ \obj -> do
        statusVal     <- obj .: "status"
        mapVal        <- obj .: "map"
        playersVal    <- obj .: "players"
        bombsVal      <- obj .: "bombs"
        explosionsVal <- obj .: "explosions"
        onePlayerVal  <- obj .: "one_player_since"
        timeVal       <- obj .: "time_left"
        winnerVal     <- obj .:? "winner"
        return $ GameState statusVal mapVal playersVal bombsVal explosionsVal onePlayerVal timeVal winnerVal

instance ToJSON GameState where
    toJSON gs = object
        [ "status"           .= gameStatus gs
        , "map"              .= object ["grid" .= gameMap gs]
        , "players"          .= intMapToJsonObject (players gs)
        , "bombs"            .= bombs gs
        , "explosions"       .= explosions gs
        , "one_player_since" .= onePlayerSince gs
        , "time_left"        .= timeLeft gs
        , "winner"           .= winner gs
        ]
      where
        intMapToJsonObject :: ToJSON v => IntMap v -> Value
        intMapToJsonObject im = object $ map (\(k, v) -> fromString (show k) .= v) (IntMap.toList im)