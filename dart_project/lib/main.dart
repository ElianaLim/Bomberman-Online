import 'package:flutter/material.dart';
import 'package:flame/game.dart';

import "game/bomberman_game.dart";
import '../menus.dart';
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final ipController = TextEditingController();
  final portController = TextEditingController();
  final playersController = TextEditingController();
  final timerController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  runApp(
    MaterialApp(
      theme: ThemeData(
        fontFamily: 'Daydream', 
        ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: 
          SizedBox(
            width: 768,
            height: 792,
            child: GameWidget(
              game: BombermanGame(),
              autofocus: true,
              overlayBuilderMap: {
                'MainMenu': (context, game) {
                  return SizedBox(
                    width: 768,
                    height: 792,
                    child: MainMenuOverlay(game: game as BombermanGame),
                  );
                },
                'HostMenu': (context, game) {
                  return SizedBox(
                    width: 768,
                    height: 792,
                    child: HostMenuOverlay(
                      game: game as BombermanGame,           
                      portController: portController,
                      playersController: playersController,
                      timerController: timerController,
                      formKey: formKey,
                    ),
                  );
                },
                'JoinMenu': (context, game) {
                  return SizedBox(
                    width: 768,
                    height: 792,
                    child: JoinMenuOverlay(
                      game: game as BombermanGame,     
                      ipController: ipController,      
                      portController: portController,
                      formKey: formKey,
                    ),
                  );
                },
                'Lobby': (context, game) {
                  return SizedBox(
                    width: 768,
                    height: 792,
                    child: LobbyOverlay(game: game as BombermanGame),
                  );
                },
                'CountDown': (context, game) {
                  return SizedBox(
                    width: 768,
                    height: 792,
                    child: CountDownOverlay(game: game as BombermanGame),
                  );
                },
                'GameOver': (context, game) {
                  return SizedBox(
                    width: 768,
                    height: 792,
                    child: GameOverOverlay(game: game as BombermanGame),
                  );
                },
              },
              initialActiveOverlays: const ['MainMenu'],
            )
          )
        ),
      ),
    ),
  );
}