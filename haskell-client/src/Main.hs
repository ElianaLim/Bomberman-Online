{-# LANGUAGE NoFieldSelectors #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE CPP #-}

module Main where

import qualified Miso as M

import Model
import Update
import View
import Miso.Subscription.Keyboard as KE

main :: IO ()
main = do
  M.run $ M.startApp app
  where
    app = (M.component initModel update view)
      { M.initialAction = Just MsgAppStart
      , M.subs = [ KE.keyboardSub MsgHandleInput ]
      , M.events = M.defaultEvents <> M.keyboardEvents
      }