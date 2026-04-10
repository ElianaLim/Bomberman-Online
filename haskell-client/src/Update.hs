{-# LANGUAGE NoFieldSelectors #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Update where

import qualified Miso as M
import qualified Miso.String as MS
import Miso.WebSocket as WS
import qualified Data.IntSet as S
import qualified Data.Map as Map
import Data.Aeson as Aeson
import GHC.Generics
import qualified Data.Text.Encoding as TE
import qualified Data.Text as T
import Control.Monad (when)
import qualified Language.Javascript.JSaddle as JSaddle
import qualified Miso.Html as H
import qualified Miso.Html.Property as P

import Debug.Trace (trace)

import Language.Javascript.JSaddle (jsg, valToStr, liftJSM, (!))

import qualified Model
import Types


movementKeys :: [Int]
movementKeys = [37, 38, 39, 40] -- Left, Up, Right, Down

data ClientMsg
    = PLAYER_MOVE { direction :: Direction}
    | PLACE_BOMB
    deriving (Eq, Show, Generic, ToJSON)

data ServerMsg
    = ASSIGN_ID { id :: Int }
    | UPDATE { state :: Model.GameState }
    | GAME_OVER { winner :: Int}
    deriving (Eq, Show, Generic, FromJSON)

parseQuery :: String -> Map.Map MS.MisoString (Maybe MS.MisoString)
parseQuery s =
    Map.fromList $ map parsePair $ filter (/="") $ split '&' (dropWhile (=='?') s)
  where
    parsePair :: String -> (MS.MisoString, Maybe MS.MisoString)
    parsePair str =
        case break (=='=') str of
            (k, '=':v) -> (MS.pack k, Just (MS.pack v))  -- drop the '='
            (k, "")    -> (MS.pack k, Nothing)
            _          -> (MS.pack str, Nothing)

split :: Char -> String -> [String]
split _ "" = []
split c s =
  let (x,rest) = break (==c) s
  in x : case rest of
           [] -> []
           (_:xs) -> split c xs

decodeServerMsg :: MS.MisoString -> Either String ServerMsg
decodeServerMsg ms =
    Aeson.eitherDecodeStrict' (TE.encodeUtf8 (T.pack (MS.unpack ms)))

data Msg
    = MsgAppStart
    | MsgHandleInput S.IntSet
    | MsgNoOp
    | WSOnOpen WS.WebSocket
    | WSOnClosed WS.Closed
    | WSConnect MS.MisoString
    | WSOnMessage MS.MisoString
    | WSSendMessage MS.MisoString
    | WSOnError MS.MisoString
    deriving (Eq)

viewAudio :: M.View Model.Model Msg
viewAudio =
  H.div_ []
    [ H.audio_
        [ P.src_ "assets/audio/explosion.mp3"
        , P.id_ "explosionAudio"
        , P.preload_ "auto"
        , P.volume_ 0.5
        ]
        []
    , H.audio_
        [ P.src_ "assets/audio/death.mp3"
        , P.id_ "deathAudio"
        , P.preload_ "auto"
        , P.volume_ 1.0
        ]
        []
    , H.audio_
        [ P.src_ "assets/audio/powerup.mp3"
        , P.id_ "powerupAudio"
        , P.preload_ "auto"
        , P.volume_ 1.0
        ]
        []
    ]

update :: Msg -> M.Transition Model.Model Msg
update MsgAppStart = do
    M.io $ do
        _ <- JSaddle.eval (MS.ms $ unlines
            [ "document.getElementById('explosionAudio').load();"
            , "document.getElementById('deathAudio').load();"
            , "document.getElementById('powerupAudio').load();"
            ])
        pure MsgNoOp

    M.io $ do
        search <- liftJSM $ valToStr =<< (jsg ("window" :: MS.MisoString) ! ("location" :: MS.MisoString) ! ("search" :: MS.MisoString))
        let searchStr = MS.unpack search
            queryMap  = parseQuery searchStr
            ip = case Map.lookup "ip" queryMap of
                   Just (Just v) -> v
                   _             -> "localhost"
            port = case Map.lookup "port" queryMap of
                     Just (Just v) -> v
                     _             -> "15000"
            url = "ws://" <> ip <> ":" <> port <> "/"
        pure $ trace ("Connecting to WebSocket at: " ++ MS.unpack url) $ WSConnect url
update (WSConnect url) =
  WS.connectText
    url
    WSOnOpen
    WSOnClosed
    WSOnMessage
    WSOnError
update (WSOnOpen ws) = do
    model <- M.get
    M.put model { Model.wsConnection = Just ws }
update (WSOnClosed _) = do
    model <- M.get
    M.put model { Model.wsConnection = Nothing }
update (WSOnMessage msg) = do
    model <- M.get
    case decodeServerMsg msg of
        Right (ASSIGN_ID newId) -> do
            -- traceM ("Assigned Player ID: " ++ show newId)
            M.put model { Model.localPlayerId = Just newId }

        Right (UPDATE newState) -> do
            -- traceM ("Received game state update: " ++ show newState)
            let localId = model.localPlayerId
                wasAliveBefore = model.wasAlive

                isAliveNow =
                    case (localId, Map.lookup <$> localId <*> Just newState.players) of
                    (Just _, Just (Just p)) -> p.is_alive
                    _ -> False

                oldCells = model.prevCells
                newCells = concat newState.map.grid

            do
                -- 🔊 death
                when (wasAliveBefore && not isAliveNow) playDeathAudio

                -- 💥 explosion
                when (not (null oldCells) && detectExplosion oldCells newCells) playExplosionAudio

                -- ⭐ power-up spawn
                when (not (null oldCells) && detectPowerupCollected oldCells newCells) playPowerupAudio

            M.put model
                { Model.gameState = Just newState
                , Model.wasAlive  = isAliveNow
                , Model.prevCells = newCells
                }

        Right (GAME_OVER winnerId) ->
            let updatedGameState = case model.gameState of
                    Just gs -> Just gs { Model.winner = Just winnerId }
                    Nothing -> Nothing
            in M.put model { Model.gameState = updatedGameState }

        Left _err -> do
            -- traceM ("Failed to decode server message: " ++ show msg)
            pure ()
update (WSOnError _) = pure ()
update (WSSendMessage msg) = do
    model <- M.get
    case model.wsConnection of
        Just ws -> WS.sendJSON ws msg
        Nothing -> pure ()
update (MsgHandleInput inputKeys) = do
    model <- M.get

    case model.wsConnection of
        Just ws -> do
            let pressedMovements =
                    filter (`S.member` inputKeys) movementKeys

            case pressedMovements of
                [37] -> WS.sendJSON ws (PLAYER_MOVE { direction = LEFT })
                [38] -> WS.sendJSON ws (PLAYER_MOVE { direction = UP })
                [39] -> WS.sendJSON ws (PLAYER_MOVE { direction = RIGHT })
                [40] -> WS.sendJSON ws (PLAYER_MOVE { direction = DOWN })
                _    -> pure ()

            let spaceNow  = S.member 32 inputKeys
                spacePrev = maybe False (S.member 32) model.lastInputKeys

            when (spaceNow && not spacePrev) $
                WS.sendJSON ws PLACE_BOMB

            M.put model { Model.lastInputKeys = Just inputKeys }

        Nothing ->
            pure ()
update MsgNoOp = pure ()

playDeathAudio :: M.Transition Model.Model Msg
playDeathAudio =
  M.io $ do
    _ <- JSaddle.eval (MS.ms ("let a = document.getElementById('deathAudio'); a.currentTime = 0; a.play();" :: String))
    pure MsgNoOp

playExplosionAudio :: M.Transition Model.Model Msg
playExplosionAudio =
  M.io $ do
    _ <- JSaddle.eval
      (MS.ms ("let a = document.getElementById('explosionAudio'); a.volume = 0.5; a.play();" :: String))
    pure MsgNoOp

detectExplosion :: [CellType] -> [CellType] -> Bool
detectExplosion oldCells newCells =
    or $ zipWith isExplosion oldCells newCells
    where
    isExplosion old new =
        new == Explosion && old /= Explosion

playPowerupAudio :: M.Effect parent model Msg
playPowerupAudio =
  M.io $ do
    _ <- JSaddle.eval (MS.ms ("let a = document.getElementById('powerupAudio'); a.currentTime = 0; a.play();" :: String))
    pure MsgNoOp


isPowerup :: CellType -> Bool
isPowerup FireUp  = True
isPowerup BombUp  = True
isPowerup SpeedUp = True
isPowerup _       = False

detectPowerupCollected :: [CellType] -> [CellType] -> Bool
detectPowerupCollected oldCells newCells =
    or $ zipWith collected oldCells newCells
  where
    collected old new =
        isPowerup old && new == Empty