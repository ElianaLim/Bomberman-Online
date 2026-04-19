{-# LANGUAGE NoFieldSelectors #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE RecordWildCards #-}

module View where

import qualified Miso as M
import qualified Miso.Html as H
import qualified Miso.Html.Property as P
import qualified Miso.String as MS
import qualified Miso.CSS as CSS
import qualified Data.Map as Map


import Model
import Update
import Types

gameWidth, gameHeight :: Int
gameWidth = 768
gameHeight = 792

numCols, numRows :: Int
numCols = 15
numRows = 13

cellWidth, cellHeight :: Double
cellWidth = 720 / fromIntegral numCols
cellHeight = 720 / fromIntegral numRows

view :: Model -> M.View Model Msg
view model = H.div_ 
    [ CSS.style_ 
        [ CSS.width (CSS.px gameWidth)
        , CSS.height (CSS.px gameHeight)
        , CSS.display "flex"
        , CSS.flexDirection "column"
        , CSS.margin "auto"
        , CSS.position "relative"
        , CSS.backgroundColor (CSS.rgba 99 97 99 1) ] ] 
    [ viewAudio
    , H.div_ [] 
        [ viewHUD 
        , case model.gameState of
            Just gs -> viewTimer gs.time_left
            Nothing -> M.text ""
        , H.div_ [
            CSS.style_ 
                [ CSS.position "relative"
                , CSS.width (CSS.px 720)
                , CSS.height (CSS.px 720)
                , CSS.display "block"
                , CSS.margin "auto"
                ]
            ] 
            [
            case model.gameState of
                Nothing ->
                    case model.localPlayerId of
                    Nothing -> M.text "Connecting to server..."
                    Just pid -> M.text $ "Hello Player " <> MS.ms (show pid) <> "! Waiting for other players to join..."
                Just gs -> case gs.status of
                    "waiting" -> viewWaitingScreen
                    "playing" -> viewGameScreen model
                    "game_over" -> viewGameScreen model
                    _          -> M.text "Unknown game state"
            ]
        , case model.gameState of
              Just gs | gs.status == "game_over" -> viewGameOverScreen model
              _ -> M.text ""
        ]
    , playWinnerAudio model
    ]

viewHUD :: M.View Model Msg
viewHUD = H.img_ 
            [ P.src_ "assets/images/HUD.png"
            , CSS.style_ 
                [ CSS.width (CSS.px gameWidth)
                , CSS.margin "auto"
                , CSS.position "relative"
                , CSS.top (CSS.px 0)
                , CSS.display "block"
                , CSS.imageRendering "pixelated"
                ]
            ]

viewWaitingScreen :: M.View Model Msg
viewWaitingScreen = 
    H.div_
    [ CSS.style_
        [ CSS.display "flex"
        , CSS.flexDirection "column"
        , CSS.justifyContent "center"
        , CSS.alignItems "center"
        , CSS.height (CSS.px gameHeight)
        , CSS.width (CSS.px gameWidth)
        , CSS.textAlign "center"
        ]] [M.text "Waiting for players to join..."]

viewGameScreen :: Model -> M.View Model Msg
viewGameScreen model = 
    case model.gameState of
    Just gs ->
      let
        -- destructure the map
        GameMap {..} = gs.map
        cells   = concat grid
        bombs   = gs.bombs
        playersList = Map.elems gs.players
      in
        H.div_ [ CSS.style_
            [ CSS.position "relative"
            , CSS.width (CSS.px 720)
            , CSS.height (CSS.px 720)
            , CSS.margin "auto"
            ]
        ]
          [ viewMap cells
          , viewBombs bombs
          , viewPlayers playersList
          ]
    Nothing -> M.text "Error: No game state for playing screen."

viewMap :: [CellType] -> M.View Model Msg
viewMap cells =
    H.div_ []
        (zipWith viewCell [0..] cells)

viewCell :: Int -> CellType -> M.View Model Msg
viewCell idx cellType =
    let
        (row, col) = idx `divMod` numCols

        x = fromIntegral col * cellWidth
        y = fromIntegral row * cellHeight
    in
    case cellType of
        Empty ->
            H.img_
                [ P.src_ "assets/images/walkable_block.png"
                , blockStyle x y cellWidth cellHeight
                ]

        HardBlock ->
            H.img_
                [ P.src_ "assets/images/hard_block.png"
                , blockStyle x y cellWidth cellHeight
                ]

        SoftBlock ->
            H.img_
                [ P.src_ "assets/images/soft_block.png"
                , blockStyle x y cellWidth cellHeight
                ]

        Bomb ->
            H.img_
                [ P.src_ "assets/images/walkable_block.png"
                , blockStyle x y cellWidth cellHeight
                ]

        Explosion ->
            H.img_
                [ P.src_ "assets/images/explosion.png"
                , blockStyle x y cellWidth cellHeight
                ]

        FireUp ->
            H.img_
                [ P.src_ "assets/images/fireUp.png"
                , blockStyle x y cellWidth cellHeight
                ]

        BombUp ->
            H.img_
                [ P.src_ "assets/images/bombUp.png"
                , blockStyle x y cellWidth cellHeight
                ]

        SpeedUp ->
            H.img_
                [ P.src_ "assets/images/speedUp.png"
                , blockStyle x y cellWidth cellHeight
                ]

blockStyle :: Double -> Double -> Double -> Double -> M.Attribute Msg
blockStyle x y w h =
    CSS.style_
        [ CSS.position "absolute"
        , CSS.left (M.ms (show x) <> "px")
        , CSS.top (M.ms (show y) <> "px")
        , CSS.width (M.ms (show w) <> "px")
        , CSS.height (M.ms (show h) <> "px")
        , CSS.imageRendering "pixelated"
        ]

viewPlayers :: [Player] -> M.View Model Msg
viewPlayers players =
    H.div_ []
        (map viewPlayer players)

viewPlayer :: Player -> M.View Model Msg
viewPlayer player =
    if not player.is_alive then
        M.text ""
    else
        let
            x = player.x * cellWidth
            y = player.y * cellHeight
            playerImg =
                "assets/images/Player_" <> MS.ms (show player.id) <> ".png"
        in
        H.div_
            [ CSS.style_
                [ CSS.position "absolute"
                , CSS.left (MS.ms (show x) <> "px")
                , CSS.top  (MS.ms (show y) <> "px")
                , CSS.width  (MS.ms (show cellWidth) <> "px")
                , CSS.height (MS.ms (show cellHeight) <> "px")
                , CSS.display "flex"
                , CSS.justifyContent "center"
                , CSS.alignItems "center"
                ]
            ]
            [ H.img_
                [ P.src_ playerImg
                , CSS.style_
                    [ CSS.width "100%"
                    , CSS.height "100%"
                    , CSS.imageRendering "pixelated"
                    ]
                ]
            , H.div_
                [ CSS.style_
                    [ CSS.position "absolute"
                    , CSS.top "-14px"
                    , CSS.fontSize "12px"
                    , CSS.color (CSS.rgb 255 255 255)
                    , CSS.whiteSpace "nowrap"
                    ]
                ]
                [ M.text ("P" <> MS.ms (show player.id)) ]
            ]

viewBombs :: [BombData] -> M.View Model Msg
viewBombs bombs =
    H.div_ []
        (map viewBomb bombs)

viewBomb :: BombData -> M.View Model Msg
viewBomb bomb =
    let
        x = bomb.x * cellWidth
        y = bomb.y * cellHeight
    in
    H.img_
        [ P.src_ "assets/images/bomb.png"
        , CSS.style_
            [ CSS.position "absolute"
            , CSS.left (MS.ms (show x) <> "px")
            , CSS.top  (MS.ms (show y) <> "px")
            , CSS.width  (MS.ms (show cellWidth) <> "px")
            , CSS.height (MS.ms (show cellHeight) <> "px")
            , CSS.imageRendering "pixelated"
            ]
        ]

viewTimer :: Int -> M.View Model Msg
viewTimer timeLeft =
    let
        timeLeftInSeconds = timeLeft `div` 1000
        minutes = timeLeftInSeconds `div` 60
        seconds = timeLeftInSeconds `mod` 60

        minutesTens  = minutes `div` 10
        minutesOnes  = minutes `mod` 10
        secondsTens  = seconds `div` 10
        secondsOnes  = seconds `mod` 10
    in
    H.div_
        [ CSS.style_
            [ CSS.position "absolute"
            , CSS.top "27px"
            , CSS.left "104px"
            , CSS.display "flex"
            , CSS.alignItems "center"
            , CSS.gap "0px"
            ]
        ]
        [ viewDigit minutesTens
        , viewDigit minutesOnes
        , viewColon
        , viewDigit secondsTens
        , viewDigit secondsOnes
        ]

viewDigit :: Int -> M.View Model Msg
viewDigit d =
    H.img_
        [ P.src_ ("assets/images/" <> MS.ms (show d) <> ".png")
        , CSS.style_
            [ CSS.width "16px"
            , CSS.height "16px"
            , CSS.imageRendering "pixelated"
            ]
        ]

viewColon :: M.View Model Msg
viewColon =
    H.img_
        [ P.src_ "assets/images/10.png"
        , CSS.style_
            [ CSS.width "16px"
            , CSS.height "16px"
            , CSS.imageRendering "pixelated"
            ]
        ]

viewGameOverScreen :: Model -> M.View Model Msg
viewGameOverScreen model =
    H.div_
        [ CSS.style_
            [ CSS.position "absolute"
            , CSS.top "0"
            , CSS.left "0"
            , CSS.width (CSS.px gameWidth)
            , CSS.height (CSS.px gameHeight)
            , CSS.backgroundColor (CSS.rgba 0 0 0 0.5)
            , CSS.display "flex"
            , CSS.flexDirection "column"
            , CSS.justifyContent "center"
            , CSS.alignItems "center"
            , CSS.zIndex "100"
            ]
        ]
        [ H.div_
            [ CSS.style_
                [ CSS.color (CSS.rgb 255 255 255)
                , CSS.fontSize "32px"
                , CSS.fontWeight "bold"
                , CSS.marginBottom "16px"
                ]
            ]
            [ M.text "Game Over!" ]
        , H.div_
            [ CSS.style_
                [ CSS.color (CSS.rgb 255 255 255)
                , CSS.fontSize "20px"
                ]
            ]
            [ M.text $
                case model.gameState >>= \gs -> gs.winner of
                    Just winnerId ->
                        if Just winnerId == model.localPlayerId then
                            "You won!"
                        else
                            "Player " <> MS.ms (show winnerId) <> " won"
                    Nothing -> "Draw"
            ]
        ]

playWinnerAudio :: Model -> M.View Model Msg
playWinnerAudio model =
    case model.gameState of
        Just gs | gs.status == "game_over" ->
            let audioFile = case gs.winner of
                    Just winnerId
                        | model.localPlayerId == Just winnerId -> "assets/audio/win.mp3"
                        | otherwise -> "assets/audio/lose.mp3"
                    Nothing -> "assets/audio/draw.mp3"
            in H.audio_
                [ P.src_ audioFile
                , P.autoplay_ True
                , P.controls_ False
                ]
                []
        _ -> M.text ""