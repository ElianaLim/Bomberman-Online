import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

//import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
//import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum CellType {
  empty,
  hardBlock,
  softBlock,
  bomb,
  explosion,
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
    //TODO: check if need to add an offset to center the player in the cell so that they don't move into hardblocks
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

    if (targetCell == CellType.explosion) {
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
  double speed = 0.1;
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

  int numPlayers = 2;
  int gameDuration = 600; // in seconds
  int port = 15000;
  int? _onePlayerSince;

  void start(int numPlayers, int duration, int port) async {
    gameState = GameState(GameMap());
    gameState.timeLeft = duration * 1000; // convert to milliseconds

    final handler = webSocketHandler((WebSocketChannel webSocket, _){
      _onConnection(webSocket, numPlayers);
    });

    var server = await io.serve(handler, InternetAddress.anyIPv4, port); // TODO: make address and port configurable
    print('Bomberman server running on ws://${server.address.host}:${server.port}');
  }

  void _onConnection(WebSocketChannel webSocket, int numPlayers) {
    _clients.add(webSocket);
    print('New player joined. Total players: ${_clients.length}');
    final playerId = _clients.length;
    _clientIds[webSocket] = playerId;

    if (gameState.status == 'waiting' && _clients.length >= numPlayers) {
      _startGame();
    }

    if (playerId == 1) {
      players[playerId] = Player(playerId, 1.0, 1.0);
    } else if (playerId == 2) {
      players[playerId] = Player(playerId, 13.0, 1.0);
    } else if (playerId == 3) {
      players[playerId] = Player(playerId, 1.0, 11.0);
    } else if (playerId == 4) {
      players[playerId] = Player(playerId, 13.0, 11.0);
    } else {
      // more than 4 players not supported
      webSocket.sink.add(jsonEncode({"tag": "ERROR", "message": "Server full"}));
      webSocket.sink.close();
      return;
    }

    webSocket.sink.add(jsonEncode({"tag": "ASSIGN_ID", "id": playerId}));

    webSocket.stream.listen((data) {
      final msg = jsonDecode(data);
      _handleInput(webSocket, msg);
    }, onDone: () {
      _clients.remove(webSocket);
      _clientIds.remove(webSocket);
      print('Player ${playerId} disconnected. Total players: ${_clients.length}');
    });
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
      gameState.timeLeft = 0;
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
    _createExplosion(x, y, ownerId);

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
          _createExplosion(nx, ny, ownerId);
        }
      }
    }
  }

  void _handleSoftBlock(int x, int y) {
    final random = Random();
    List<CellType> powerups = [CellType.fireUp, CellType.bombUp, CellType.speedUp]; // TODO: use the powerup mapping for this
    if (random.nextDouble() < 0.1) {
      grid[y][x] = powerups[random.nextInt(powerups.length)];
    } else {
      grid[y][x] = CellType.empty;
    }

  }

  void _createExplosion(int x, int y, int ownerId) {
    grid[y][x] = CellType.explosion;
    explosionOwners["${x},${y}"] = ownerId;

    playerHit(x, y);

    Timer(Duration(milliseconds: 1000), () {
      if (grid[y][x] == CellType.explosion) {
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
    if (gameState.status != 'playing') {
      print("Game not started yet. status: ${gameState.status}");
      return;
    } 

    final tag = msg['tag'];
    final playerId = _clientIds[webSocket];
    final command = _commands[tag];
    final player = players[playerId]!;

    if (command != null) {
      command.execute(this, player, msg);
    }
  } 
}

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    print('Run as: dart run bin/server.dart <num_players> <duration> --host <port>');
    exit(1);
  }

  try {
    int numPlayers = int.parse(args[0]);
    if (numPlayers < 2 || numPlayers > 4) {
      print('Error: Number of players must be between 2 and 4.');
      exit(1);
    }

    int duration = int.parse(args[1]);
    if (duration < 30 || duration > 600) {
      print('Error: Duration must be between 30 and 600 seconds.');
      exit(1);
    }

    if (args[2] != '--host') {
      print('Error: Missing --host flag.');
      exit(1);
    }

    int port = int.parse(args[3]);

    BombermanServer().start(numPlayers, duration, port);
  } catch (e) {
    print('Error: ${e.toString()}');
    exit(1);
  }
}
