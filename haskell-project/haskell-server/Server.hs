{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Network.WebSockets (Connection, PendingConnection, receiveDataMessage, sendTextData, acceptRequest, runServer, sendClose, DataMessage(..))
import Data.Aeson (decode, encode, FromJSON(..), ToJSON(..), Value(..), (.=))
import Data.Aeson.Types (Parser, withObject, withText, (.:), (.:?))
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Text (Text, unpack, pack)
import qualified Data.ByteString.Lazy as BL
import GHC.Generics (Generic)
import Control.Monad (forever, forM_, when, void)
import Control.Concurrent (forkIO, threadDelay, MVar, newMVar, takeMVar, putMVar, modifyMVar, modifyMVar_, readMVar)
import System.Random (randomRIO)
import Control.Exception (finally, SomeException, catch)
import Data.Maybe (fromMaybe, isJust, fromJust)
import Data.IntMap (IntMap)
import qualified Data.IntMap as IntMap
import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Game.Types
import Game.State

-- | Message tags
data MessageTag
    = ASSIGN_ID
    | PLACE_SOFT
    | PLAYER_MOVE
    | PLACE_BOMB
    | UPDATE
    | BOMB_EXPLODE
    | START_GAME
    | ERROR
    | GAME_OVER
    deriving (Show, Eq, Generic)

-- | Game message data type
data GameMessage = GameMessage
    { tag :: MessageTag
    , payload :: MessagePayload
    } deriving (Show, Generic)

-- | Payload types for each message
data MessagePayload
    = AssignIdPayload { assignId :: Int }
    | PlaceSoftPayload { cells :: [Int] }
    | PlayerMovePayload { direction :: Text }
    | PlaceBombPayload
    | UpdatePayload { gameState :: Value }
    | BombExplodePayload { x :: Int, y :: Int }
    | StartGamePayload { timer :: Int }
    | ErrorPayload { errorMessage :: Text }
    | GameOverPayload { winnerId :: Maybe Int }
    deriving (Show, Generic)

-- | Handler functions type
data MessageHandlers = MessageHandlers
    { onAssignId :: IORef GameState -> ServerState -> Connection -> Int -> IO ()
    , onPlaceSoft :: IORef GameState -> ServerState -> Connection -> [Int] -> IO ()
    , onPlayerMove :: IORef GameState -> ServerState -> Connection -> Text -> Int -> IO ()
    , onPlaceBomb :: IORef GameState -> ServerState -> Connection -> Int -> IO ()
    , onUpdate :: IORef GameState -> ServerState -> Connection -> Value -> IO ()
    , onBombExplode :: IORef GameState -> ServerState -> Connection -> Int -> Int -> IO ()
    , onStartGame :: IORef GameState -> ServerState -> Connection -> Int -> IO ()
    , onError :: IORef GameState -> ServerState -> Connection -> Text -> IO ()
    , onGameOver :: IORef GameState -> ServerState -> Connection -> Maybe Int -> IO ()
    }

-- | Default handlers that do nothing
defaultHandlers :: MessageHandlers
defaultHandlers = MessageHandlers
    { onAssignId = \_ _ _ _ -> pure ()
    , onPlaceSoft = \_ _ _ _ -> pure ()
    , onPlayerMove = \_ _ _ _ _ -> pure ()
    , onPlaceBomb = \_ _ _ _ -> pure ()
    , onUpdate = \_ _ _ _ -> pure ()
    , onBombExplode = \_ _ _ _ _ -> pure ()
    , onStartGame = \_ _ _ _ -> pure ()
    , onError = \_ _ _ _ -> pure ()
    , onGameOver = \_ _ _ _ -> pure ()
    }

-- | Game handlers
gameHandlers :: MessageHandlers
gameHandlers = MessageHandlers
    { onAssignId = \gameStateRef serverState conn idVal -> do
        putStrLn $ "Client assigned ID: " ++ show idVal
        -- Add player to game state
        modifyIORef' gameStateRef $ \gs ->
            addPlayer gs idVal (getSpawnPosition idVal)
        -- Send confirmation back to client
        sendTextData conn $ encode $ GameMessage ASSIGN_ID (AssignIdPayload idVal)
        -- Broadcast updated game state
        broadcastGameState gameStateRef serverState

    , onPlaceSoft = \_ serverState conn cells -> do
        putStrLn $ "Place soft blocks at: " ++ show cells

    , onPlayerMove = \gameStateRef serverState conn dir playerId -> do
        gs <- readIORef gameStateRef
        -- Only process movement if game is still playing
        if gameStatus gs == "playing"
            then do
                putStrLn $ "Player " ++ show playerId ++ " moved: " ++ unpack dir
                -- Update game state
                newGs <- processPlayerMove gs playerId (unpack dir)
                writeIORef gameStateRef newGs
                -- Broadcast updated game state
                broadcastGameState gameStateRef serverState
            else
                putStrLn "Game has ended - ignoring player movement"

    , onPlaceBomb = \gameStateRef serverState conn playerId -> do
        gs <- readIORef gameStateRef
        -- Only allow bomb placement if game is still playing
        if gameStatus gs == "playing"
            then do
                putStrLn $ "Player " ++ show playerId ++ " placed bomb"
                -- Handle bomb logic
                modifyIORef' gameStateRef $ \gs ->
                    placeBomb gs playerId
                -- Broadcast updated game state
                broadcastGameState gameStateRef serverState
            else
                putStrLn "Game has ended - ignoring bomb placement"

    , onUpdate = \_ serverState conn state -> do
        putStrLn "Game state updated"
        -- Broadcast state to all clients

    , onBombExplode = \_ serverState conn x y -> do
        putStrLn $ "Bomb exploded at (" ++ show x ++ ", " ++ show y ++ ")"
        -- Handle explosion effects

    , onStartGame = \gameStateRef serverState conn timer -> do
        putStrLn $ "Game starting with timer: " ++ show timer ++ " seconds"
        -- Initialize game state
        modifyIORef' gameStateRef $ \gs ->
            gs { gameStatus = "playing", timeLeft = timer * 1000 }

    , onError = \_ serverState conn msg -> do
        putStrLn $ "Error: " ++ show msg
        -- Send error back to client
        sendTextData conn $ encode $ GameMessage ERROR (ErrorPayload msg)

    , onGameOver = \_ serverState conn winner -> do
        putStrLn $ "Game over! Winner: " ++ show winner
        -- Send game over to all clients
        sendTextData conn $ encode $ GameMessage GAME_OVER (GameOverPayload winner)
    }

-- | Parse MessageTag from JSON
instance FromJSON MessageTag where
    parseJSON = withText "tag" $ \t -> case t of
        "ASSIGN_ID"    -> pure ASSIGN_ID
        "PLACE_SOFT"   -> pure PLACE_SOFT
        "PLAYER_MOVE"  -> pure PLAYER_MOVE
        "PLACE_BOMB"   -> pure PLACE_BOMB
        "UPDATE"       -> pure UPDATE
        "BOMB_EXPLODE" -> pure BOMB_EXPLODE
        "START_GAME"   -> pure START_GAME
        "ERROR"        -> pure ERROR
        "GAME_OVER"    -> pure GAME_OVER
        _              -> fail $ "Unknown tag: " ++ show t

instance ToJSON MessageTag where
    toJSON ASSIGN_ID    = "ASSIGN_ID"
    toJSON PLACE_SOFT   = "PLACE_SOFT"
    toJSON PLAYER_MOVE  = "PLAYER_MOVE"
    toJSON PLACE_BOMB   = "PLACE_BOMB"
    toJSON UPDATE       = "UPDATE"
    toJSON BOMB_EXPLODE = "BOMB_EXPLODE"
    toJSON START_GAME   = "START_GAME"
    toJSON ERROR        = "ERROR"
    toJSON GAME_OVER    = "GAME_OVER"

-- | Parse GameMessage from JSON
instance FromJSON GameMessage where
    parseJSON = withObject "GameMessage" $ \obj -> do
        msgTag <- obj .: "tag"
        payload <- case msgTag of
            ASSIGN_ID -> do
                idVal <- obj .: "id"
                pure $ AssignIdPayload idVal
            PLACE_SOFT -> do
                cellsVal <- obj .: "cells"
                pure $ PlaceSoftPayload cellsVal
            PLAYER_MOVE -> do
                dirVal <- obj .: "direction"
                pure $ PlayerMovePayload dirVal
            PLACE_BOMB ->
                pure PlaceBombPayload
            UPDATE -> do
                stateVal <- obj .: "state"
                pure $ UpdatePayload stateVal
            BOMB_EXPLODE -> do
                xVal <- obj .: "x"
                yVal <- obj .: "y"
                pure $ BombExplodePayload xVal yVal
            START_GAME -> do
                timerVal <- obj .: "timer"
                pure $ StartGamePayload timerVal
            ERROR -> do
                msgVal <- obj .: "message"
                pure $ ErrorPayload msgVal
            GAME_OVER -> do
                winnerVal <- obj .: "winner"
                pure $ GameOverPayload winnerVal
        pure $ GameMessage msgTag payload

-- | Convert GameMessage to JSON
instance ToJSON GameMessage where
    toJSON (GameMessage tag payload) = Object $ case payload of
        AssignIdPayload idVal ->
            KeyMap.fromList [ "tag" .= tag, "id" .= idVal ]
        PlaceSoftPayload cellsVal ->
            KeyMap.fromList [ "tag" .= tag, "cells" .= cellsVal ]
        PlayerMovePayload dirVal ->
            KeyMap.fromList [ "tag" .= tag, "direction" .= dirVal ]
        PlaceBombPayload ->
            KeyMap.fromList [ "tag" .= tag ]
        UpdatePayload stateVal ->
            KeyMap.fromList [ "tag" .= tag, "state" .= stateVal ]
        BombExplodePayload xVal yVal ->
            KeyMap.fromList [ "tag" .= tag, "x" .= xVal, "y" .= yVal ]
        StartGamePayload timerVal ->
            KeyMap.fromList [ "tag" .= tag, "timer" .= timerVal ]
        ErrorPayload msgVal ->
            KeyMap.fromList [ "tag" .= tag, "message" .= msgVal ]
        GameOverPayload winnerVal ->
            KeyMap.fromList [ "tag" .= tag, "winner" .= winnerVal ]

-- | State to track connected clients and game state
data ServerState = ServerState
    { clients :: IntMap Connection
    , nextClientId :: Int
    , gameStateRef :: IORef GameState
    , expectedPlayerCount :: Int
    , gameTimerSeconds :: Int
    }

-- | Initial server state
initialServerState :: Int -> Int -> IO ServerState
initialServerState playerCount timerSeconds = do
    gs <- initializeGameState
    gameRef <- newIORef gs
    pure $ ServerState IntMap.empty 1 gameRef playerCount timerSeconds


serverApp :: Int -> ServerState -> MVar ServerState -> PendingConnection -> IO ServerState
serverApp clientId state serverStateMVar pending = do
    -- Accept the WebSocket handshake and establish connection
    conn <- acceptRequest pending
    putStrLn $ "Client " ++ show clientId ++ " connected"
    
    -- Add player to game state
    modifyIORef' (gameStateRef state) $ \gs ->
        addPlayer gs clientId (getSpawnPosition clientId)
    
    -- Add client to state
    let newState = state
            { clients = IntMap.insert clientId conn (clients state)
            }
    

    modifyMVar_ serverStateMVar $ \_ -> return newState
    
    sendTextData conn $ encode $ GameMessage ASSIGN_ID (AssignIdPayload clientId)
    
    -- Start game when expected number of players are connected
    gs <- readIORef (gameStateRef newState)
    let connectedPlayers = IntMap.size (players gs)
    when (connectedPlayers >= expectedPlayerCount newState && gameStatus gs == "waiting") $ do
        putStrLn $ show connectedPlayers ++ " players connected - starting game!"
        let startMsg = GameMessage START_GAME (StartGamePayload (gameTimerSeconds newState))
        broadcastMessage newState startMsg
        -- Update game state to playing
        modifyIORef' (gameStateRef newState) $ \gs' ->
            gs' { gameStatus = "playing", timeLeft = gameTimerSeconds newState * 1000 }
        -- Start game loop
        void $ forkIO $ gameLoop (gameStateRef newState) serverStateMVar
    
    -- Run message loop with cleanup on disconnect
    handleMessages newState clientId conn `finally` do
        putStrLn $ "Client " ++ show clientId ++ " disconnected"
        -- Remove player from game state
        modifyIORef' (gameStateRef newState) $ \gs ->
            removePlayer gs clientId
    -- Return the state without the disconnected client
    return $ newState { clients = IntMap.delete clientId (clients newState) }
  where
    -- | Infinite loop receiving and processing messages
    handleMessages st clientId conn = do
        msg <- receiveDataMessage conn
        
        case msg of
            Text rawMsg _ ->
                case decode rawMsg of
                    Just gameMsg -> do
                        putStrLn $ "Client " ++ show clientId ++ " sent: " ++ show (tag gameMsg)
                        handleGameMessage gameHandlers (gameStateRef st) st conn gameMsg clientId
                    Nothing -> do
                        putStrLn "Invalid JSON received from client"
                        sendTextData conn $ encode $ GameMessage ERROR (ErrorPayload "Invalid JSON format")
            
            Binary rawMsg ->
                case decode rawMsg of
                    Just gameMsg -> do
                        putStrLn $ "Client " ++ show clientId ++ " sent (binary): " ++ show (tag gameMsg)
                        handleGameMessage gameHandlers (gameStateRef st) st conn gameMsg clientId
                    Nothing -> do
                        putStrLn "⚠ Invalid JSON in binary frame"
                        sendTextData conn $ encode $ GameMessage ERROR (ErrorPayload "Invalid JSON in binary frame")
        
        -- Continue the loop
        handleMessages st clientId conn

-- | Handle decoded game messages
handleGameMessage :: MessageHandlers -> IORef GameState -> ServerState -> Connection -> GameMessage -> Int -> IO ()
handleGameMessage handlers gameStateRef serverState conn (GameMessage tag payload) clientId = case (tag, payload) of
    (ASSIGN_ID, AssignIdPayload idVal) ->
        onAssignId handlers gameStateRef serverState conn idVal
    (PLACE_SOFT, PlaceSoftPayload cellsVal) ->
        onPlaceSoft handlers gameStateRef serverState conn cellsVal
    (PLACE_BOMB, PlaceBombPayload) ->
        onPlaceBomb handlers gameStateRef serverState conn clientId
    (PLAYER_MOVE, PlayerMovePayload dirVal) ->
        onPlayerMove handlers gameStateRef serverState conn dirVal clientId
    (UPDATE, UpdatePayload stateVal) ->
        onUpdate handlers gameStateRef serverState conn stateVal
    (BOMB_EXPLODE, BombExplodePayload xVal yVal) ->
        onBombExplode handlers gameStateRef serverState conn xVal yVal
    (START_GAME, StartGamePayload timerVal) ->
        onStartGame handlers gameStateRef serverState conn timerVal
    (ERROR, ErrorPayload msgVal) ->
        onError handlers gameStateRef serverState conn msgVal
    (GAME_OVER, GameOverPayload winnerVal) ->
        onGameOver handlers gameStateRef serverState conn winnerVal
    _ ->
        putStrLn "Message tag and payload mismatch"

-- | Broadcast game state to all clients
broadcastGameState :: IORef GameState -> ServerState -> IO ()
broadcastGameState gameStateRef serverState = do
    gs <- readIORef gameStateRef
    let updateMsg = GameMessage UPDATE (UpdatePayload $ toJSON gs)
    broadcastMessage serverState updateMsg

-- | Global exception handler for the server
handleServerError :: SomeException -> IO ()
handleServerError e = putStrLn $ "Server error: " ++ show e

-- | Broadcast a message to all connected clients
broadcastMessage :: ServerState -> GameMessage -> IO ()
broadcastMessage st msg = do
    let msgBytes = encode msg
    forM_ (IntMap.elems $ clients st) $ \conn ->
        sendTextData conn msgBytes

-- | Send a message to a specific client
sendToClient :: ServerState -> Int -> GameMessage -> IO ()
sendToClient st clientId msg =
    case IntMap.lookup clientId (clients st) of
        Just conn -> sendTextData conn (encode msg)
        Nothing -> putStrLn $ "Client " ++ show clientId ++ " not found"


-- | Check win conditions
checkWinConditions :: GameState -> (GameState, Bool)
checkWinConditions gs =
    let alivePlayers = IntMap.filter playerAlive (players gs)
        aliveCount = IntMap.size alivePlayers
        currentTime = timeLeft gs
    in case aliveCount of
        0 -> (triggerGameOver gs { onePlayerSince = Nothing }, True)
        1 -> case onePlayerSince gs of
                Nothing -> (gs { onePlayerSince = Just currentTime }, False)
                Just startTime ->
                    if startTime - currentTime >= 1000
                        then (triggerGameOver gs, True)
                        else (gs, False)
        _ -> (gs { onePlayerSince = Nothing }, False)

-- | Trigger game over 
triggerGameOver :: GameState -> GameState
triggerGameOver gs =
    let alivePlayers = IntMap.filter playerAlive (players gs)
        winner = case IntMap.toList alivePlayers of
            [(playerId, _)] -> Just playerId
            _ -> Nothing
    in gs { gameStatus = "game_over", winner = winner, onePlayerSince = Nothing }

-- | Game loop running every 50ms
gameLoop :: IORef GameState -> MVar ServerState -> IO ()
gameLoop gameStateRef serverStateMVar = do
    gs <- readIORef gameStateRef
    
    when (gameStatus gs == "playing") $ do
        -- Update bombs and explosions
        gs' <- updateBombsAndExplosions gs
        
        -- Update timer
        let gs'' = gs' { timeLeft = timeLeft gs' - 50 }
        
        -- Check win conditions
        let (gsFinal, gameEnded) = checkWinConditions gs''
        
        -- Write back game state
        writeIORef gameStateRef gsFinal
        
        -- Get current server state and broadcast to all clients
        currentServerState <- readMVar serverStateMVar
        broadcastGameState gameStateRef currentServerState
        
        -- Broadcast game over message if game ended
        when gameEnded $ do
            let gameOverMsg = GameMessage GAME_OVER (GameOverPayload (winner gsFinal))
            broadcastMessage currentServerState gameOverMsg
        
        -- Continue loop
        threadDelay 50000  -- 50ms
        gameLoop gameStateRef serverStateMVar


-- | Server application entry point with shared game state
serverAppWithState :: MVar ServerState -> PendingConnection -> IO ()
serverAppWithState serverStateMVar pending = do
    -- Get the next client ID and update the state
    (clientId, updatedSt, shouldReject) <- modifyMVar serverStateMVar $ \st -> do
        let clientId = nextClientId st
        let newState = st { nextClientId = clientId + 1 }
        -- Check if we already have the expected number of players
        gs <- readIORef (gameStateRef st)
        let playerCount = IntMap.size (players gs)
        let reject = playerCount >= expectedPlayerCount st
        return (newState, (clientId, newState, reject))
    
    if shouldReject
        then do
            -- Accept connection just to send error message
            conn <- acceptRequest pending
            putStrLn $ "Rejecting client " ++ show clientId ++ " (max " ++ show (expectedPlayerCount updatedSt) ++ " players reached)"
            -- Send ERROR message
            sendTextData conn $ encode $ GameMessage ERROR (ErrorPayload (pack ("Server full - maximum " ++ show (expectedPlayerCount updatedSt) ++ " players allowed")))
            sendClose conn ("Server full" :: BL.ByteString)
        else do
            -- Handle the connection with the assigned client ID
            finalState <- serverApp clientId updatedSt serverStateMVar pending
            
            -- Update the shared state with the final state
            modifyMVar_ serverStateMVar $ \_ -> return finalState

main :: IO ()
main = do
    args <- getArgs
    case args of
        [playerCountStr, timerSecondsStr, "--host", portStr] -> do
            -- Validate player count (2, 3, or 4)
            let playerCount = read playerCountStr
            if playerCount `notElem` [2, 3, 4]
                then do
                    putStrLn "Error: Number of players must be 2, 3, or 4"
                    exitFailure
                else do
                    -- Validate timer seconds (30 to 600 inclusive)
                    let timerSeconds = read timerSecondsStr
                    if timerSeconds < 30 || timerSeconds > 600
                        then do
                            putStrLn "Error: Timer must be between 30 and 600 seconds (inclusive)"
                            exitFailure
                        else do
                            -- Parse port number
                            let port = read portStr
                            let host = "0.0.0.0"

                            putStrLn $ "Starting WebSocket server on ws://" ++ host ++ ":" ++ show port
                            putStrLn $ "Configuration: " ++ show playerCount ++ " players, " ++ show timerSeconds ++ " second timer"
                            
                            -- Create shared server state
                            serverStateMVar <- initialServerState playerCount timerSeconds >>= newMVar
                            
                            -- Run server with specified host and port
                            runServer host port (serverAppWithState serverStateMVar) `catch` handleServerError
        
        _ -> do
            putStrLn "Usage: cabal run server -- <players> <time> --host <port>"
            putStrLn ""
            exitFailure
