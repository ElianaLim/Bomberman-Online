import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum CellType {
  empty,
  hardBlock,
  softBlock,
  bomb,
  explosionEpicenter,
  explosionMiddle,
  explosionTip,
  fireUp,
  bombUp,
  speedUp,
}

Map<CellType, PowerUp> powerupMapping = {
  CellType.fireUp: FireUp(),
  CellType.bombUp: BombUp(),
  CellType.speedUp: SpeedUp(),
};


abstract class PowerUp {
  void apply(Player player);
}

class FireUp implements PowerUp {
  @override
  void apply(Player player) {
    player.bombRange += 1;
  }
}

class BombUp implements PowerUp {
  @override
  void apply(Player player) {
    player.maxBombs += 1;
  }
}

class SpeedUp implements PowerUp {
  @override
  void apply(Player player) {
    player.speed += 0.05;
  }
}


abstract class GameCommand {
  void execute(BombermanServer server, Player player, Map<String, dynamic> data);
}

class MoveCommand implements GameCommand {
  @override
  void execute(BombermanServer server, Player player, Map<String, dynamic> data) {
    if (!player.isAlive) return;
    final direction = data['direction'];
    final double speed = player.speed;
    final double offset = 0.3;
    GameMap map = server.map;

    double currX = player.x;
    double currY = player.y;

    double newX = currX;
    double newY = currY;

    switch (direction) {
      case 'UP': newY -= speed; break;
      case 'DOWN': newY += speed; break;
      case 'LEFT': newX -= speed; break;
      case 'RIGHT': newX += speed; break;
    }

    List<List<double>> checkpoints = [];

    if (direction == 'UP') {
      checkpoints = [
        [newX - offset, newY - offset],
        [newX + offset, newY - offset],
      ];
    } else if (direction == 'DOWN') {
      checkpoints = [
        [newX - offset, newY + offset],
        [newX + offset, newY + offset],
      ];
    } else if (direction == 'LEFT') {
      checkpoints = [
        [newX - offset, newY - offset],
        [newX - offset, newY + offset],
      ];
    } else if (direction == 'RIGHT') {
      checkpoints = [
        [newX + offset, newY - offset],
        [newX + offset, newY + offset],
      ];
    }

    bool canMove = true;

    for (var point in checkpoints) {
      CellType type = map.getCell(point[0].round(), point[1].round());
      if (type == CellType.hardBlock || type == CellType.softBlock) {
        canMove = false;
        break;
      }

      if (type == CellType.bomb) {
        if (point[0].round() != currX.round() || point[1].round() != currY.round()) {
          canMove = false;
          break;
        }
      }
    }

    if (!canMove) return;

    player.x = newX;
    player.y = newY;

    CellType targetCell = map.getCell(player.x.round(), player.y.round());
    if (powerupMapping.containsKey(targetCell)) {
      powerupMapping[targetCell]!.apply(player);
      map.setCell(player.x.round(), player.y.round(), CellType.empty);
    }

    if (targetCell == CellType.explosionEpicenter || targetCell == CellType.explosionMiddle || targetCell == CellType.explosionTip) {
      server.playerHit(player.x.round(), player.y.round());
    }
  }
}

class BombCommand implements GameCommand {
  @override
  void execute(BombermanServer server, Player player, Map<String, dynamic> data) {
    GameMap map = server.map;
    int currX = player.x.round();
    int currY = player.y.round();

    if (player.currBombs >= player.maxBombs) {
      print('Player ${player.id} cannot place more bombs.');
      return;
    }

    if (map.getCell(currX, currY) == CellType.empty) {
      final newBomb = Bomb(
        x: currX,
        y: currY,
        ownerId: player.id,
        range: player.bombRange,
      );
      server.bombs.add(newBomb);
      map.setCell(currX, currY, CellType.bomb);

      player.currBombs += 1;
    }
  }
}


class Player {
  final int id;
  double x;
  double y;
  bool isAlive = true;

  // for powerups
  int maxBombs = 1;
  int currBombs = 0;
  int bombRange = 1;
  double speed = 0.2;
  int points = 0;

  Player(this.id, this.x, this.y);

  void die() {
    currBombs = 0;
    isAlive = false;
    print('Player $id has died.');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'is_alive': isAlive,
      'max_bombs': maxBombs,
      'current_bombs': currBombs,
      'bomb_range': bombRange,
      'speed': speed,
      'points': points,
    };
  }
}

class Bomb {
  final int x;
  final int y;
  final int ownerId;
  int timer;
  int range;

  Bomb({
    required this.x,
    required this.y,
    required this.ownerId,
    this.timer = 3000,
    this.range = 1,
    });

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'owner_id': ownerId,
      'timer': timer,
      'range': range,
    };
  }

  bool tick(int ms){
    timer -= ms;
    return timer <= 0;
  }
}

class GameMap {
  final int rows = 13;
  final int cols = 15;
  late List<List<CellType>> grid;

  GameMap() {
    grid = generateInitialMap();
  }

  List<List<CellType>> generateInitialMap() {
    final random = Random();
    List<List<CellType>> map = List.generate(rows, (_) => List.filled(cols, CellType.empty));

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (r == 0 || r == rows - 1 || c == 0 || c == cols - 1) {
          map[r][c] = CellType.hardBlock;
        } 
        else if (r % 2 == 0 && c % 2 == 0) {
          map[r][c] = CellType.hardBlock;
        } else {
          bool isTopLeftSpawn = (r == 1 && c == 1) || (r == 1 && c == 2) || (r == 2 && c == 1);
          bool isTopRightSpawn = (r == 1 && c == 13) || (r == 1 && c == 12) || (r == 2 && c == 13);
          bool isBottomLeftSpawn = (r == 11 && c == 1) || (r == 11 && c == 2) || (r == 10 && c == 1);
          bool isBottomRightSpawn = (r == 11 && c == 13) || (r == 11 && c == 12) || (r == 10 && c == 13);

          if (isTopLeftSpawn || isTopRightSpawn || isBottomLeftSpawn || isBottomRightSpawn) {
            map[r][c] = CellType.empty;
          }
          else if (random.nextDouble() < 0.4) {
            map[r][c] = CellType.softBlock;
          }
        }
      }
    }
    final mapToInt = map
          .map((row) => row.map((cell) => cell.index).toList())
          .toList();
    for (var row in mapToInt){
      print(row);
    }
    return map;
  }

  CellType getCell(int x, int y) => grid[y][x];

  void setCell(int x, int y, CellType type) {
    grid[y][x] = type;
  }

  Map<String, dynamic> toJson() {
    return {
      'grid': grid
          .map((row) => row.map((cell) => cell.index).toList())
          .toList(),
    };
  }
}
class GameState {
  String status = 'waiting'; // waiting, playing, game_over
  final GameMap map;
  final Map<int, Player> players = {};
  final List<Bomb> bombs = [];
  int timeLeft = 60 * 1000; // milliseconds
  int? winner;

  GameState(this.map);

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'map': map.toJson(),
      'players': players.map((id, player) => MapEntry(id.toString(), player.toJson())),
      'bombs': bombs.map((bomb) => bomb.toJson()).toList(),
      'time_left': timeLeft,
      'winner': winner,
    };
  }
}

class BombermanServer {
  final Map<String, GameCommand> _commands = {
    'PLAYER_MOVE': MoveCommand(),
    'PLACE_BOMB': BombCommand(),
  };

  final List<WebSocketChannel> _clients = [];
  final  Map<WebSocketChannel, int> _clientIds = {};
  final Map<String, int> explosionOwners = {};

  late GameState gameState;
  Map<int, Player> get players => gameState.players;
  List<Bomb> get bombs => gameState.bombs;
  GameMap get map => gameState.map;
  List<List<CellType>> get grid => gameState.map.grid;

  int gameDuration = 600; // in seconds
  int port = 15000;
  int? _onePlayerSince;
  bool isGameStart = false;

  int confirmedPlayers = 0;

  void start(int numPlayers, int duration, int port) async {
    gameState = GameState(GameMap());
    gameState.timeLeft = duration * 1000; // convert to milliseconds

    final handler = webSocketHandler((WebSocketChannel webSocket, _){
      _onConnection(webSocket, numPlayers);
    });

    var server = await io.serve(handler, InternetAddress.anyIPv4, port); 
    print('Bomberman server running on ws://${server.address.host}:${server.port}');
  }
  // made changes to JSON message LOBBY_STATUS (=> LOBBY_UPDATE)
  // added JSON message COUNTDOWN_STATUS
  // added JSON message START_GAME

  void _onConnection(WebSocketChannel webSocket, int numPlayers) {
    if (isGameStart) {
      print("Cannot join, game has started");
      webSocket.sink.add(jsonEncode({
        "tag": "ERROR",
        "message": "Game has already started"
      }));
      webSocket.sink.close(); // kick them out
      return;
    }

    if (_clients.length >= numPlayers) {
      print("Cannot join, server is full");
      webSocket.sink.add(jsonEncode({
        "tag": "ERROR",
        "message": "Server full"
      }));
      webSocket.sink.close(); // kick them out
      return;
    }
    _clients.add(webSocket);
    print('New player joined. Total players: ${_clients.length}');
    final playerId = _clients.length;
    _clientIds[webSocket] = playerId;

    switch (playerId) {
      case 1: players[playerId] = Player(playerId, 1.0, 1.0); break;
      case 2: players[playerId] = Player(playerId, 13.0, 1.0); break;
      case 3: players[playerId] = Player(playerId, 1.0, 11.0); break;
      case 4: players[playerId] = Player(playerId, 13.0, 11.0); break;
    }

    webSocket.sink.add(jsonEncode({"tag": "ASSIGN_ID", "id": playerId}));

    _broadcastLobbyState(numPlayers, players.keys.toList());

    webSocket.stream.listen((data) {
      final msg = jsonDecode(data);
      _handleInput(webSocket, msg);
    }, onDone: () {
      _clients.remove(webSocket);
      _clientIds.remove(webSocket);
      _broadcastLobbyState(numPlayers, players.keys.toList());
      print('Player $playerId disconnected. Total players: ${_clients.length}');
    });
  }

  void _broadcastLobbyState(int numPlayers, List<int> connectedPlayers) {
    _broadcastEvent({"tag": "LOBBY_STATUS", "total_players": numPlayers, "connected_players": connectedPlayers});
  }

  void _startCountdown() {
    confirmedPlayers++;
    if (confirmedPlayers == _clients.length) {
      Timer.periodic(Duration(seconds: 1), (timer) {
        final remaining = 4 - timer.tick;

        if (remaining > 0) {
          final data = jsonEncode({
            "tag": "COUNTDOWN_STATUS",
            "count": remaining
          });
          for (var client in _clients) {
            client.sink.add(data);
          }
        } else {
          final start = jsonEncode({"tag": "START_GAME"});
          for (var client in _clients) {
            client.sink.add(start);
          }
          _startGame();
          timer.cancel();
        }
      });
    }
  }

  void _startGame() {
    gameState.status = 'playing';
    print('Game started with ${_clients.length} players.');

    Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (gameState.status == 'game_over') {
        timer.cancel();
      } else {
      _updateGameState();
      }
    });
  }

  void _updateGameState() {
    if (gameState.status == 'game_over') return;

    _updateTimer();
    _updateBombs();
    _checkWinConditions();
    _broadcastState();
  }

  void _updateTimer() {
    gameState.timeLeft -= 50;
    if (gameState.timeLeft <= 0) {
      _triggerGameOver(null);
    }
  }

  void _updateBombs() {
    List<dynamic> bombsToExplode = [];
    for (var bomb in bombs) {
      if (bomb.tick(50)) {
        bombsToExplode.add(bomb);
        int x = bomb.x;
        int y = bomb.y;
        grid[y][x] = CellType.empty;
      }
    }
    for (var bomb in bombsToExplode) {
      bombs.remove(bomb);
      explodeBomb(bomb.x, bomb.y, bomb.range, bomb.ownerId);
      players[bomb.ownerId]?.currBombs -= 1;

      _broadcastEvent({"tag": "BOMB_EXPLODE", "x": bomb.x, "y": bomb.y});
    }
  }
  void explodeBomb(int x, int y, int range, int ownerId) {
    _createExplosion(x, y, ownerId, CellType.explosionEpicenter);

    List<List<int>> directions = [
      [1, 0], // right
      [-1, 0], // left
      [0, 1], // down
      [0, -1], // up
    ];

    for (var dir in directions) {

      for (int i = 1; i <= range; i++) {
        int dx = dir[0] * i;
        int dy = dir[1] * i;
        int nx = x + dx;
        int ny = y + dy;

        if (nx < 0 || nx >= 15 || ny < 0 || ny >= 13) break;
        
        CellType hitType = grid[ny][nx];

        if (hitType == CellType.hardBlock) break;

        if (hitType == CellType.softBlock) {
          _handleSoftBlock(nx, ny);
          break;
        } else if (hitType == CellType.bomb){
          for (var bomb in bombs) {
            if (bomb.x == nx && bomb.y == ny) {
              bomb.timer = 0;
              break;
            }
          }
          continue;
        } else {
          CellType explosionType = CellType.explosionMiddle;
          if (i == range) {
            explosionType = CellType.explosionTip;
          }
          _createExplosion(nx, ny, ownerId, explosionType);
        }
      }
    }
  }

  void _handleSoftBlock(int x, int y) {
    final random = Random();
    List<CellType> powerups = powerupMapping.keys.toList();
    if (random.nextDouble() < 0.1) {
      grid[y][x] = powerups[random.nextInt(powerups.length)];
    } else {
      grid[y][x] = CellType.empty;
    }

  }

  void _createExplosion(int x, int y, int ownerId, CellType explosionType) {
    grid[y][x] = explosionType;
    explosionOwners["${x},${y}"] = ownerId;

    playerHit(x, y);

    Timer(Duration(milliseconds: 1000), () {
      if (grid[y][x] == CellType.explosionEpicenter || grid[y][x] == CellType.explosionMiddle || grid[y][x] == CellType.explosionTip ) {
        grid[y][x] = CellType.empty;
        explosionOwners.remove("${x},${y}");
      }
    });
  }

  void playerHit(int x, int y) {
    List<int> playersToRemove = [];

    players.values.forEach((player) {
      int playerX = player.x.round();
      int playerY = player.y.round();

      if (playerX == x && playerY == y) {
        print('Player ${player.id} hit by bomb at ($x, $y)');
        final ownerId = explosionOwners["${x},${y}"];
        if (ownerId != null) {
          players[ownerId]?.points += 1;
        }
        player.die();
        playersToRemove.add(player.id);
      }
    });

    for (var id in playersToRemove) {
      players.remove(id);
    }
  }

  void _checkWinConditions() {
    List<int> alivePlayers = [];
    players.forEach((id, player) {
      if (player.isAlive) alivePlayers.add(id);
    });

    int aliveCount = alivePlayers.length;

    if (aliveCount == 0) {
      _onePlayerSince = null; // reset timer
      _triggerGameOver(null);
    } else if (aliveCount == 1) {
      if (_onePlayerSince == null) {
        _onePlayerSince = DateTime.now().millisecondsSinceEpoch;
      } else {
        int elapsed = DateTime.now().millisecondsSinceEpoch - _onePlayerSince!;
        if (elapsed >= 1000) {
          _triggerGameOver(alivePlayers[0]);
        }
      }
    } else {
      _onePlayerSince = null; // reset timer
    }
  }

  void _triggerGameOver(int? winner) {
    gameState.status = 'game_over';
    gameState.winner = winner;

    print('Game Over! Winner: Player ${winner ?? "Draw"}');
    _broadcastEvent({"tag": "GAME_OVER", "winner": winner});
  }

  void _broadcastState() {
    final data = jsonEncode({"tag": "UPDATE", "state": gameState.toJson()});
    for (var client in _clients) {
      client.sink.add(data);
    }
  }
  
  void _broadcastEvent(Map<String, dynamic> event) {
    final data = jsonEncode(event);
    for (var client in _clients) {
      client.sink.add(data);
    }
  }

  void _handleInput(WebSocketChannel webSocket, Map<String, dynamic> msg) {
    final tag = msg['tag'];
    final playerId = _clientIds[webSocket];
    final command = _commands[tag];
    final player = players[playerId]!;

    // handles JSON message PLAYERR_CONFIRM from client
    if (msg['tag'] == "PLAYER_CONFIRM") {
        isGameStart = true;
        _startCountdown();
      }

    if (gameState.status != 'playing') {
      print("Game not started yet. status: ${gameState.status}");
      return;
    } 

    if (command != null) {
      command.execute(this, player, msg);
    }
  } 
}
