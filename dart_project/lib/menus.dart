import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/services.dart';

import "game/bomberman_game.dart";
import "server/bomberman_server.dart";


// -------------------------- Main Menu --------------------------


class MainMenuOverlay extends StatefulWidget {
  final BombermanGame game;

  const MainMenuOverlay({super.key, required this.game});

  @override
  State<MainMenuOverlay> createState() => _MainMenuOverlayState();

}

class _MainMenuOverlayState extends State<MainMenuOverlay> {
  int _selectedIndex = 0; // let 0 for host and 1 for join
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() => _selectedIndex = 0);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() => _selectedIndex = 1);
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        _selectItem();
      }
    }
  }

  void _selectItem() {
    widget.game.overlays.remove('MainMenu');
    if (_selectedIndex == 0) {
      widget.game.overlays.add('HostMenu');
    } else {
      widget.game.overlays.add('JoinMenu');
    }
  }

  Widget _buildMenuItem(int index, String text) {
    final isSelected = _selectedIndex == index;
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: isSelected ? 24 : 16),
      decoration: BoxDecoration(
        color: isSelected ? Colors.yellow.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isSelected ? Colors.yellow : Colors.white,
          fontSize: 24,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'Daydream',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.fromRGBO(0, 0, 0, 1),
      body: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: _handleKeyEvent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset("assets/images/Logo.png", width: 360, height: 60,),
              const SizedBox(height: 16),


              // host button
              _buildMenuItem(0, "Host Game"),
              const SizedBox(height: 8),

              // join button
              _buildMenuItem(1, "Join Game"),
            ],
          ),
        ),
      ),
    );
  }
}

// class MainMenuOverlay extends StatelessWidget {
//   final BombermanGame game;

//   const MainMenuOverlay({super.key, required this.game});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       color: Color.fromRGBO(0, 0, 0, 1),
//       child: Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Image.asset(
//               "assets/images/Logo.png",
//               width: 360,
//               height: 60,
//               ),
//             const SizedBox(height: 16),
//             TextButton(
//               onPressed: () {
//                 game.overlays.remove('MainMenu');
//                 game.overlays.add('HostMenu');
//               },
//               style: ButtonStyle(
//                 backgroundColor: WidgetStateProperty.resolveWith((states) {
//                   return Colors.transparent;
//                 }),
//                 foregroundColor: WidgetStateProperty.resolveWith((states) {
//                       return states.contains(WidgetState.focused)
//                           ? Colors.yellow
//                           : Colors.white;
//                 }),
//               ),
//               child: Text("Host Game"),
//             ),
//             TextButton(
//               onPressed: () {
//                 game.overlays.remove('MainMenu');
//                 game.overlays.add('JoinMenu');
//               },
//               style: ButtonStyle(
//                 backgroundColor: WidgetStateProperty.resolveWith((states) {
//                   return Colors.transparent;
//                 }),
//                 foregroundColor: WidgetStateProperty.resolveWith((states) {
//                       return states.contains(WidgetState.focused)
//                           ? Colors.yellow
//                           : Colors.white;
//                 }),
//               ),
//               child: Text("Join Game"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// -------------------------- Host Menu --------------------------

class HostMenuOverlay extends StatelessWidget {
  final BombermanGame game;
  final TextEditingController portController;
  final TextEditingController playersController;
  final TextEditingController timerController;
  final GlobalKey<FormState> formKey;

  const HostMenuOverlay({
    super.key,
    required this.game,
    required this.portController,
    required this.playersController,
    required this.timerController,
    required this.formKey,
  }); // constructor

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.fromRGBO(0, 0, 0, 1),
      child: Center(
        child: Card(
          elevation: 8,
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Host Game",
                    style: TextStyle(
                      fontSize: 36,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<String>(
                    future: getLocalIpAddress(), 
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Text(
                          "Your IP: ${snapshot.data}",
                          style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold),
                        );
                      }
                      return const Text("Fetching IP...", style: TextStyle(color: Colors.grey));
                    }
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Port Number",
                      labelStyle: TextStyle(
                        color: Colors.white,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter a port number';
                      }
                      final num? port = int.tryParse(value);
                      if (port == null || port < 1024 || port > 65535) {
                        return 'Enter a valid port (1024-65535)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: playersController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Number of Players",
                      labelStyle: TextStyle(
                        color: Colors.white,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter number of players';
                      }
                      final num? players = int.tryParse(value);
                      if (players == null || players < 2 || players > 4) {
                        return 'There can only be 2 to 4 players';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: timerController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Timer (seconds)",
                      labelStyle: TextStyle(
                        color: Colors.white,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter timer';
                      }
                      final num? timer = int.tryParse(value);
                      if (timer == null || timer < 30 || timer > 600) {
                        return 'Enter valid time (30s to 600s)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _returnToMain,
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            return Colors.transparent;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((states) {
                                return states.contains(WidgetState.focused)
                                    ? Colors.yellow
                                    : Colors.white;
                          }),
                        ),
                        child: const Text("Back"),
                      ),
                      TextButton(
                        onPressed: _initiateServer,
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            return Colors.transparent;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((states) {
                                return states.contains(WidgetState.focused)
                                    ? Colors.yellow
                                    : Colors.white;
                          }),
                        ),
                        child: const Text("Confirm Settings"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _returnToMain() {
    game.overlays.remove('HostMenu');
    game.overlays.add('MainMenu');
  }

  void _initiateServer() async {
    if (!formKey.currentState!.validate()) return;
    final int port = int.parse(portController.text);
    final int players = int.parse(playersController.text);
    final int timer = int.parse(timerController.text);
    late final channel;

    game.totalPlayers = players;
    String myIp = await getLocalIpAddress();

    BombermanServer().start(players, timer, port);

    await Future.delayed(const Duration(milliseconds: 500));
    
    print("==============================================");
    print("       SERVER STARTED ON PORT $port");
    print("----------------------------------------------");
    print("     FOR OTHER COMPUTERS, CONNECT TO:");
    print("                 $myIp");
    print("==============================================");
    print("Attempting connection to ws://127.0.0.1:$port");

    try { 
      final socket = await WebSocket.connect('ws://127.0.0.1:$port');
      channel = IOWebSocketChannel(socket);
      game.channel = channel;
    } catch (e) {
    print("Connection failed: $e");
    }

    // listens to server
    channel.stream.listen((data) {
      final msg = jsonDecode(data);
      switch (msg['tag']){
        case 'ASSIGN_ID':
          game.overlays.remove('HostMenu');
          game.overlays.add('Lobby');
          game.assignLocalId(msg);
          break;
        case 'LOBBY_STATUS':
          game.totalPlayers = msg['total_players'];
          game.connectedPlayers.value = List<int>.from(msg['connected_players']);
          break;
        case 'COUNTDOWN_STATUS':
          game.countdown.value = msg['count'];
          break;
        case 'START_GAME':
          game.overlays.remove('CountDown');
          game.add(HudComponent());
          game.add(game.minutesOnesDigit);
          game.add(game.minutesTensDigit);
          game.add(game.colon);
          game.add(game.secondsTensDigit);
          game.add(game.secondsOnesDigit);
          break;
        case 'UPDATE':
          game.updateGameState(msg);
          break;
        case 'GAME_OVER':
          game.triggerGameOver(msg);
          break;
        }
      }
    );
  }
}

// -------------------------- Join Menu --------------------------

class JoinMenuOverlay extends StatelessWidget {
  final BombermanGame game;
  final TextEditingController ipController;
  final TextEditingController portController;
  final GlobalKey<FormState> formKey;

  const JoinMenuOverlay({
    super.key,
    required this.game,
    required this.ipController,
    required this.portController,
    required this.formKey,
  }); // constructor

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.fromRGBO(0, 0, 0, 1),
      child: Center(
        child: Card(
          elevation: 8,
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Join Game",
                    style: TextStyle(
                      fontSize: 36,
                      color: Colors.white,
                      ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ipController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true
                      ),
                    style: TextStyle(
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Host IP address",
                      labelStyle: TextStyle(
                        color: Colors.white,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter host IP address';
                      }
                      return null;
                    }
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Port Number",
                      labelStyle: TextStyle(
                        color: Colors.white,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter a port number';
                      }
                      final num? port = int.tryParse(value);
                      if (port == null || port < 1024 || port > 65535) {
                        return 'Enter a valid port (1024 - 65535)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _returnToMain,
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            return Colors.transparent;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((states) {
                                return states.contains(WidgetState.focused)
                                    ? Colors.yellow
                                    : Colors.white;
                          }),
                        ),
                        child: const Text("Back"),
                      ),
                      TextButton(
                        onPressed: _initiateConnection,
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            return Colors.transparent;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((states) {
                                return states.contains(WidgetState.focused)
                                    ? Colors.yellow
                                    : Colors.white;
                          }),
                        ),
                        child: const Text("Confirm Settings"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  void _returnToMain() {
    game.overlays.remove('JoinMenu');
    game.overlays.add('MainMenu');
  }

  void _initiateConnection() async {
    if (!formKey.currentState!.validate()) return;
    final String ip = ipController.text;
    final int port = int.parse(portController.text);
    late final channel;
    try {
      final socket = await WebSocket.connect('ws://$ip:$port');
      channel = IOWebSocketChannel(socket);
      game.channel = channel;
    } catch (e) {
      print("Connection failed: $e");
    }

    // listens to server
    channel.stream.listen((data) {
      final msg = jsonDecode(data);
      switch (msg['tag']){
        case 'ASSIGN_ID':
          game.overlays.remove('JoinMenu');
          game.overlays.add('Lobby');
          game.assignLocalId(msg);
          break;
        case 'LOBBY_STATUS':
          game.totalPlayers = msg['total_players'];
          game.connectedPlayers.value = List<int>.from(msg['connected_players']);
          break;
        case 'COUNTDOWN_STATUS':
          game.countdown.value = msg['count'];
          break;
        case 'START_GAME':
          game.overlays.remove('CountDown');
          game.add(HudComponent());
          game.add(game.minutesOnesDigit);
          game.add(game.minutesTensDigit);
          game.add(game.colon);
          game.add(game.secondsTensDigit);
          game.add(game.secondsOnesDigit);
          break;
        case 'UPDATE':
          game.updateGameState(msg);
          break;
        case 'GAME_OVER':
          game.triggerGameOver(msg);
          break;
        }
      }
    );
  }
}

// -------------------------- Lobby --------------------------

class LobbyOverlay extends StatelessWidget {
  final BombermanGame game;
  const LobbyOverlay({
    super.key,
    required this.game,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromRGBO(0, 0, 0, 1),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Lobby',
              style: TextStyle(
                fontSize: 36,
                color: Colors.white
                ),
              
            ),

            ValueListenableBuilder<List<int>>(
              valueListenable: game.connectedPlayers,
              builder: (context, players, child) {
                final bool isReady = players.length == game.totalPlayers;
                return Column(
                  children: [
                    ...players
                      .map((p) => Text(
                            "${p.toString()} connected.",
                            style: const TextStyle(color: Colors.white),
                          )
                        ),
                    const SizedBox(height: 30),

                    if (!isReady) 
                      Text(
                        "Waiting for players (${players.length}/${game.totalPlayers})",
                        style: const TextStyle(color: Colors.grey)
                      ),

                    if (isReady)
                      TextButton(
                        onPressed: () {
                          game.overlays.remove('Lobby');
                          game.overlays.add('CountDown');
                          game.channel.sink.add(jsonEncode({"tag": "PLAYER_CONFIRM"}));
                        },
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            return Colors.transparent;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((states) {
                                return states.contains(WidgetState.focused)
                                    ? Colors.yellow
                                    : Colors.white;
                          }),
                        ),
                        child: const Text("Start Game"),
                      ),
                    ]
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------- Count Down --------------------------

class CountDownOverlay extends StatelessWidget {
  final BombermanGame game;
  const CountDownOverlay({super.key, required this.game});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.fromRGBO(0, 0, 0, 1),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: game.countdown,
              builder: (context, players, child) {
                return Text(
                  game.countdown.value != 0 ? "${game.countdown.value}" : "Waiting for other players...",
                  style: TextStyle(
                    fontSize: 48,
                    color: Colors.white
                    ),
                  );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------- Game Over --------------------------

class GameOverOverlay extends StatelessWidget {
  final BombermanGame game;

  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.fromRGBO(0, 0, 0, 1),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Game Over!',
              style: TextStyle(
                fontSize: 36,
                color: Colors.white
                ), 
            ),
            Text(
              game.winner != null ? "Player ${game.winner} won" : "Draw",
              style: const TextStyle(
                color: Colors.white
                ), 
            ),
          ],
        ),
      ),
    );
  }
}


Future<String> getLocalIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    for (var interface in interfaces) {
      for (var addr in interface.addresses) {
        if (!addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return "Unknown IP";
  } catch (e) {
    return "Error getting IP";
  }
}