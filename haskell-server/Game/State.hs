{-# LANGUAGE OverloadedStrings #-}
 
module Game.State where

import qualified Data.Text as T
 
import Game.Types
import qualified Data.Vector as V
import qualified Data.IntMap as IntMap
import Data.IntMap (IntMap)
import qualified Data.Map as Map
import Data.Map (Map)
import System.Random (randomRIO, randomIO)
import Control.Monad (foldM)
import Data.List (find)

-- | Initialize a new game state with a 13x15 map
initializeGameState :: IO GameState
initializeGameState = do
    -- Create the game map with walls
    gameMap <- generateInitialMap
    
    pure $ GameState
        { gameStatus = "waiting"
        , players = IntMap.empty
        , bombs = []
        , explosions = []
        , onePlayerSince = Nothing
        , gameMap = gameMap
        , timeLeft = 600000  -- 10 minutes in milliseconds
        , winner = Nothing
        }
 
-- | Create a 15x13 game map
createGameMap :: Int -> Int -> IO GameMap
createGameMap width height = do
    let rows = V.generate height (\y -> V.generate width (\x -> getTileType x y))
    pure rows
  where
    getTileType x y
        -- Border walls
        | x == 0 || x == width - 1 || y == 0 || y == height - 1 = HardWall
        -- Alternating hard walls (checkerboard pattern)
        | even x && even y = HardWall
        -- Spawn areas (keep empty for player spawns)
        | isSpawnArea x y = Empty
        -- Random soft walls (40% chance)
        | otherwise = Empty  
    
    isSpawnArea x y =
        let topLeft = (x == 1 && y == 1) || (x == 1 && y == 2) || (x == 2 && y == 1)
            topRight = (x == 13 && y == 1) || (x == 12 && y == 1) || (x == 13 && y == 2)
            bottomLeft = (x == 1 && y == 11) || (x == 1 && y == 10) || (x == 2 && y == 11)
            bottomRight = (x == 13 && y == 11) || (x == 12 && y == 11) || (x == 13 && y == 10)
        in topLeft || topRight || bottomLeft || bottomRight


generateInitialMap :: IO GameMap
generateInitialMap = do
    let width = 15
        height = 13
    rows <- mapM (generateRow width) [0..height-1]
    pure $ V.fromList rows
  where
    generateRow :: Int -> Int -> IO (V.Vector TileType)
    generateRow width y = do
        row <- mapM (\x -> getTileTypeIO x y) [0..width-1]
        pure $ V.fromList row
    
    getTileTypeIO :: Int -> Int -> IO TileType
    getTileTypeIO x y
        -- Border walls (x: 0-14, y: 0-12)
        | x == 0 || x == 14 || y == 0 || y == 12 = pure HardWall
        -- Alternating hard walls
        | even x && even y = pure HardWall
        -- Spawn areas (keep empty for player spawns)
        | isSpawnArea x y = pure Empty
        -- Random soft walls (40% chance)
        | otherwise = do
            r <- randomIO :: IO Double
            pure $ if r < 0.4 then SoftWall else Empty
    
    isSpawnArea :: Int -> Int -> Bool
    isSpawnArea x y =
        let topLeft = (x == 1 && y == 1) || (x == 1 && y == 2) || (x == 2 && y == 1)
            topRight = (x == 13 && y == 1) || (x == 12 && y == 1) || (x == 13 && y == 2)
            bottomLeft = (x == 1 && y == 11) || (x == 1 && y == 10) || (x == 2 && y == 11)
            bottomRight = (x == 13 && y == 11) || (x == 12 && y == 11) || (x == 13 && y == 10)
        in topLeft || topRight || bottomLeft || bottomRight

-- | Add a player to the game state
addPlayer :: GameState -> Int -> (Float, Float) -> GameState
addPlayer gs playerId (x, y) =
    let player = Player
            { playerId = playerId
            , playerX = x
            , playerY = y
            , playerAlive = True
            , currentBombs = 0
            , maxBombs = 1
            , playerBombRange = 1
            , playerSpeed = 0.1
            , playerPoints = 0
            }
    in gs { players = IntMap.insert playerId player (players gs) }

-- | Update player position
updatePlayerPosition :: GameState -> Int -> (Float, Float) -> GameState
updatePlayerPosition gs playerId (newX, newY) =
    case IntMap.lookup playerId (players gs) of
        Just player -> 
            let updatedPlayer = player { playerX = newX, playerY = newY }
            in gs { players = IntMap.insert playerId updatedPlayer (players gs) }
        Nothing -> gs

-- | Remove a player from the game
removePlayer :: GameState -> Int -> GameState
removePlayer gs playerId =
    gs { players = IntMap.delete playerId (players gs) }

-- | Get tile at position
getTile :: GameMap -> Int -> Int -> Maybe TileType
getTile gameMap x y
    | x < 0 || y < 0 = Nothing
    | y >= V.length gameMap = Nothing
    | x >= V.length (gameMap V.! y) = Nothing
    | otherwise = Just (gameMap V.! y V.! x)

-- | Set tile at position
setTile :: GameMap -> Int -> Int -> TileType -> GameMap
setTile gameMap x y tileType
    | x < 0 || y < 0 || y >= V.length gameMap || x >= V.length (gameMap V.! y) = gameMap
    | otherwise = gameMap V.// [(y, (gameMap V.! y) V.// [(x, tileType)])]

-- | Check if position is valid for movement using checkpoint-based collision
-- Checks 2 points based on movement direction
isValidMove :: GameMap -> (Float, Float) -> String -> (Float, Float) -> Bool
isValidMove gameMap (currX, currY) direction (newX, newY) =
    let checkpoints = case direction of
            "UP"    -> [(newX - 0.3, newY - 0.3), (newX + 0.3, newY - 0.3)]
            "DOWN"  -> [(newX - 0.3, newY + 0.3), (newX + 0.3, newY + 0.3)]
            "LEFT"  -> [(newX - 0.3, newY - 0.3), (newX - 0.3, newY + 0.3)]
            "RIGHT" -> [(newX + 0.3, newY - 0.3), (newX + 0.3, newY + 0.3)]
            _       -> []
        isValidTile (cx, cy) =
            case getTile gameMap (round cx) (round cy) of
                Just HardWall -> False
                Just SoftWall -> False
                Just BombTile ->
                    round cx == round currX && round cy == round currY
                _ -> True  -- Allow Empty, Explosion, and power-ups
    in all isValidTile checkpoints

-- | Type for movement strategies
type MovementStrategy = Player -> GameMap -> IO ((Float, Float), Maybe TileType)

-- | Regular movement 
regularMovementStrategy :: String -> MovementStrategy
regularMovementStrategy direction player gameMap = do
    let (currX, currY) = (playerX player, playerY player)
        (newX, newY) = calculateNewPosition (currX, currY) direction (playerSpeed player)
        valid = isValidMove gameMap (currX, currY) direction (newX, newY)
    if valid
        then do
            let targetX = round newX
                targetY = round newY
                destTile = getTile gameMap targetX targetY
            pure ((newX, newY), destTile)
        else pure ((currX, currY), Nothing)

-- | Map of direction strings to movement strategies
movementStrategies :: Map String MovementStrategy
movementStrategies = Map.fromList
    [ ("UP", regularMovementStrategy "UP")
    , ("DOWN", regularMovementStrategy "DOWN")
    , ("LEFT", regularMovementStrategy "LEFT")
    , ("RIGHT", regularMovementStrategy "RIGHT")
    
    ]

-- | Process player movement 
processPlayerMove :: GameState -> Int -> String -> IO GameState
processPlayerMove gs playerId direction =
    case IntMap.lookup playerId (players gs) of
        Just player ->
            case Map.lookup direction movementStrategies of
                Just strategy -> do
                    ((newX, newY), destTile) <- strategy player (gameMap gs)
                    -- Update player position
                    let gs' = updatePlayerPosition gs playerId (newX, newY)
                    -- Handle destination tile (power-up, explosion, or nothing)
                    case destTile of
                        Just Explosion ->
                            -- Player moved into explosion 
                            pure $ killPlayer gs' playerId
                        Just tile | tile `elem` [FireUp, BombUp, SpeedUp] ->
                            let targetX = round newX
                                targetY = round newY
                                gs'' = applyPowerUpToPlayer gs' playerId tile
                            in pure $ gs'' { gameMap = setTile (gameMap gs'') targetX targetY Empty }
                        _ -> pure gs'
                Nothing -> pure gs 
        
        Nothing -> pure gs

-- | Apply power-up to player
applyPowerUpToPlayer :: GameState -> Int -> TileType -> GameState
applyPowerUpToPlayer gs playerId tileType =
    case IntMap.lookup playerId (players gs) of
        Just player ->
            let updatedPlayer = case tileType of
                    FireUp -> player { playerBombRange = playerBombRange player + 1 }
                    BombUp -> player { maxBombs = maxBombs player + 1 }
                    SpeedUp -> player { playerSpeed = playerSpeed player + 0.05 }
                    _ -> player
            in gs { players = IntMap.insert playerId updatedPlayer (players gs) }
        Nothing -> gs

-- | Calculate new position based on direction
calculateNewPosition :: (Float, Float) -> String -> Float -> (Float, Float)
calculateNewPosition (x, y) dir speed = case dir of
    "UP"    -> (x, y - speed)
    "DOWN"  -> (x, y + speed)
    "LEFT"  -> (x - speed, y)
    "RIGHT" -> (x + speed, y)
    _       -> (x, y)

-- | Place a bomb at player position
placeBomb :: GameState -> Int -> GameState
placeBomb gs playerId =
    case IntMap.lookup playerId (players gs) of
        Just player ->
            if playerAlive player && currentBombs player < maxBombs player
                then
                    let currX = round (playerX player)
                        currY = round (playerY player)
                        bomb = Bomb
                                { bombX = currX
                                , bombY = currY
                                , bombOwnerId = playerId
                                , bombTimer = 3000  -- 3 seconds in milliseconds
                                , bombRange = playerBombRange player
                                }
                        updatedPlayer = player { currentBombs = currentBombs player + 1 }
                        updatedPlayers = IntMap.insert playerId updatedPlayer (players gs)
                        updatedMap = setTile (gameMap gs) currX currY BombTile
                    in gs { players = updatedPlayers, bombs = bomb : bombs gs, gameMap = updatedMap }
                else gs
        Nothing -> gs

-- | Update all bombs (decrement timers) and explosions (clear after duration)
updateBombsAndExplosions :: GameState -> IO GameState
updateBombsAndExplosions gs = do
    -- Update bomb timers
    let updatedBombs = map (\bomb -> bomb { bombTimer = bombTimer bomb - 50 }) (bombs gs)
        activeBombs = filter (\bomb -> bombTimer bomb > 0) updatedBombs
        explodedBombs = filter (\bomb -> bombTimer bomb <= 0) updatedBombs
    
    -- Handle bomb explosions
    gsAfterExplosions <- foldM handleBombExplosion gs explodedBombs
    
    -- Update explosion timers and clear expired explosions
    let updatedExplosions = map (\exp -> exp { explosionTimer = explosionTimer exp - 50 }) (explosions gsAfterExplosions)
        activeExplosions = filter (\exp -> explosionTimer exp > 0) updatedExplosions
        
    -- Clear explosion tiles from map for expired explosions
    let expiredExplosions = filter (\exp -> explosionTimer exp <= 0) updatedExplosions
        gsFinal = foldl clearExplosionTile gsAfterExplosions expiredExplosions
        clearExplosionTile gsAcc exp =
            gsAcc { gameMap = setTile (gameMap gsAcc) (explosionX exp) (explosionY exp) Empty }
    
    pure $ gsFinal { bombs = activeBombs, explosions = activeExplosions }

-- | Handle bomb explosion with chain reactions
handleBombExplosion :: GameState -> Bomb -> IO GameState
handleBombExplosion gs bomb = do
    -- Remove bomb from map
    let gs' = gs { gameMap = setTile (gameMap gs) (bombX bomb) (bombY bomb) Empty }
    -- Explode and create explosion pattern
    gs'' <- explodeBomb gs' bomb
    -- Decrement player's bomb count
    case IntMap.lookup (bombOwnerId bomb) (players gs'') of
        Just player ->
            let updatedPlayer = player { currentBombs = max 0 (currentBombs player - 1) }
                updatedPlayers = IntMap.insert (bombOwnerId bomb) updatedPlayer (players gs'')
            in pure $ gs'' { players = updatedPlayers }
        Nothing -> pure gs''

-- | Create explosion pattern from bomb
explodeBomb :: GameState -> Bomb -> IO GameState
explodeBomb gs bomb = do
    -- First create explosion at bomb's position
    let centerX = bombX bomb
        centerY = bombY bomb
        gs' = gs { gameMap = setTile (gameMap gs) centerX centerY Explosion }
        explosionInfo = ExplosionInfo centerX centerY (bombOwnerId bomb) 1000
        gs'' = gs' { explosions = explosionInfo : explosions gs' }
        gs''' = playerHit gs'' centerX centerY
    
    -- Then explode in 4 directions
    let directions = [(1, 0), (-1, 0), (0, 1), (0, -1)]  -- right, left, down, up
    foldM (explodeDirection bomb) gs''' directions

-- | Explode in a specific direction
explodeDirection :: Bomb -> GameState -> (Int, Int) -> IO GameState
explodeDirection bomb gs (dx, dy) = do
    let centerX = bombX bomb
        centerY = bombY bomb
        range = bombRange bomb
    
    -- Iterate through each step in the direction (1 to range)
    let explodeStep i accGs
          | i > range = pure accGs
          | otherwise = do
              let nx = centerX + dx * i
                  ny = centerY + dy * i
              
              -- Check bounds
              if nx < 0 || nx >= 15 || ny < 0 || ny >= 13
                  then pure accGs
                  else do
                      case getTile (gameMap accGs) nx ny of
                          Just HardWall -> pure accGs  -- Stop at hard walls
                          Just SoftWall -> do
                              -- Destroy soft wall, possibly drop power-up
                              r <- randomIO :: IO Double
                              newTile <- if r < 0.1
                                  then do
                                      powerUpType <- randomRIO (0, 2) :: IO Int
                                      pure $ case powerUpType of
                                          0 -> FireUp
                                          1 -> BombUp
                                          _ -> SpeedUp
                                  else pure Empty
                              pure $ accGs { gameMap = setTile (gameMap accGs) nx ny newTile }
                          Just BombTile -> do
                              -- Chain reaction - explode other bombs
                              case findBombAt accGs nx ny of
                                  Just otherBomb -> do
                                      let bombs' = filter (\b -> not (bombX b == nx && bombY b == ny)) (bombs accGs)
                                      handleBombExplosion (accGs { bombs = otherBomb : bombs' }) otherBomb
                                  Nothing -> pure accGs
                          _ -> do
                              -- Create explosion
                              let gs' = accGs { gameMap = setTile (gameMap accGs) nx ny Explosion }
                              -- Create explosion info for tracking
                              let explosionInfo = ExplosionInfo nx ny (bombOwnerId bomb) 1000
                              let gs'' = gs' { explosions = explosionInfo : explosions gs' }
                              -- Check for player hits 
                              let gs''' = playerHit gs'' nx ny
                              explodeStep (i + 1) gs'''
    
    explodeStep 1 gs

-- | Find bomb at position
findBombAt :: GameState -> Int -> Int -> Maybe Bomb
findBombAt gs x y = find (\b -> bombX b == x && bombY b == y) (bombs gs)

-- | Check if player is hit by explosion 
-- This function removes players from the game completely when they die
playerHit :: GameState -> Int -> Int -> GameState
playerHit gs x y =
    let playersToRemove = IntMap.foldrWithKey (checkPlayerPosition x y) [] (players gs)
    in foldl (\gsAcc pId ->
                let expOwner = findExplosionOwner (explosions gsAcc) x y
                    gs' = case expOwner of
                           Just ownerId | ownerId /= pId -> awardPointToPlayer gsAcc ownerId
                           _ -> gsAcc
                in removePlayer gs' pId
            ) gs playersToRemove
  where
    checkPlayerPosition x y playerId player acc =
        if round (playerX player) == x && round (playerY player) == y
            then playerId : acc
            else acc
    
    findExplosionOwner :: [ExplosionInfo] -> Int -> Int -> Maybe Int
    findExplosionOwner explosions x y =
        case filter (\exp -> explosionX exp == x && explosionY exp == y) explosions of
            (exp:_) -> Just (explosionOwner exp)
            [] -> Nothing
    
    awardPointToPlayer :: GameState -> Int -> GameState
    awardPointToPlayer gs ownerId =
        case IntMap.lookup ownerId (players gs) of
            Just owner ->
                let updatedOwner = owner { playerPoints = playerPoints owner + 1 }
                in gs { players = IntMap.insert ownerId updatedOwner (players gs) }
            Nothing -> gs

-- | Check if player is hit by explosion
checkPlayerHit :: GameState -> Int -> Int -> GameState
checkPlayerHit gs x y =
    let playersToRemove = IntMap.foldrWithKey (checkPlayerPosition x y) [] (players gs)
    in foldl (\gsAcc playerId -> killPlayer gsAcc playerId) gs playersToRemove
  where
    checkPlayerPosition x y playerId player acc =
        if round (playerX player) == x && round (playerY player) == y
            then playerId : acc
            else acc

-- | Check if player is hit by explosion with owner tracking for scoring
checkPlayerHitWithOwner :: GameState -> Int -> Int -> Int -> GameState
checkPlayerHitWithOwner gs x y ownerId =
    let playersToKill = IntMap.foldrWithKey (checkPlayerPosition x y) [] (players gs)
    in foldl (\gsAcc playerId -> killPlayerAndAwardPoints gsAcc playerId ownerId) gs playersToKill
  where
    checkPlayerPosition x y playerId player acc =
        if round (playerX player) == x && round (playerY player) == y
            then playerId : acc
            else acc

-- | Kill a player and award points to the killer
killPlayerAndAwardPoints :: GameState -> Int -> Int -> GameState
killPlayerAndAwardPoints gs playerId ownerId =
    case IntMap.lookup playerId (players gs) of
        Just player ->
            let updatedPlayer = player { playerAlive = False, currentBombs = 0 }
                -- Award point to the owner (if owner exists and is not the player being killed)
                gs' = if ownerId /= playerId && IntMap.member ownerId (players gs)
                    then case IntMap.lookup ownerId (players gs) of
                        Just owner ->
                            let updatedOwner = owner { playerPoints = playerPoints owner + 1 }
                            in gs { players = IntMap.insert ownerId updatedOwner (players gs) }
                        Nothing -> gs
                    else gs
            in gs' { players = IntMap.insert playerId updatedPlayer (players gs') }
        Nothing -> gs

-- | Kill a player
killPlayer :: GameState -> Int -> GameState
killPlayer gs playerId =
    case IntMap.lookup playerId (players gs) of
        Just player ->
            let updatedPlayer = player { playerAlive = False, currentBombs = 0 }
            in gs { players = IntMap.insert playerId updatedPlayer (players gs) }
        Nothing -> gs

-- | Get spawn position for a player (returns (x, y) tuple)
getSpawnPosition :: Int -> (Float, Float)
getSpawnPosition playerId = case playerId of
    1 -> (1.0, 1.0)
    2 -> (13.0, 1.0)
    3 -> (1.0, 11.0)
    4 -> (13.0, 11.0)
    _ -> (7.0, 7.0)

