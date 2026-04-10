import 'package:flame/events.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flame_audio/flame_audio.dart';

void main(List<String> args) {
  String ip = '127.0.0.1';
  int port = 15000;


  if (args.length == 2) {
    ip = args[0];
    try {
      port = int.parse(args[1]);
    } catch (e) {
      print('Invalid port number, using default $port.');
    }
  } else {
    print('Usage: flutter run -a <server_ip> -a <server_port>');
    print('Using default server IP $ip and port $port.');
  }

  runApp(
    MaterialApp(  // <-- wrap the whole game
      home: Scaffold(
      body: GameWidget(
        game: BombermanGame(serverIp: ip, serverPort: port),
        autofocus: true,
        overlayBuilderMap: {
          'GameOver': (context, game) {
            return SizedBox(
              width: 768,
              height: 792,
              child: GameOverOverlay(game: game as BombermanGame),
            );
          },
        }
      ),
    ),
    ),
  );
}

class GameOverOverlay extends StatelessWidget {
  final BombermanGame game;

  const GameOverOverlay({super.key, required this.game}); // constructor

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.fromRGBO(0, 0, 0, 0.5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Game Over!',
              style: TextStyle(
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

class DigitComponent extends SpriteComponent with HasGameReference<BombermanGame>{
  DigitComponent(
    Vector2 position) 
    : super(position: position, size: Vector2 (16, 16), anchor: Anchor.topLeft);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('0.png');
  }

  void updateSprite(int digit) async {
    sprite = await game.loadSprite('$digit.png');
  }
}

class HudComponent extends SpriteComponent with HasGameReference<BombermanGame>{

  HudComponent() : super(position: Vector2(0, 0), size: Vector2 (768, 72), anchor: Anchor.topLeft);
  
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('HUD.png');
  }
}

class Background extends PositionComponent with HasGameReference<BombermanGame> {
  static final paint = Paint()..color = const Color.fromRGBO(99, 97, 99, 1);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, game.size.x, game.size.y),
      paint,
    );
  }
}

class BombermanGame extends FlameGame with HasKeyboardHandlerComponents {
  late WebSocketChannel channel;
  final ValueNotifier<List<String>> connectedPlayers = ValueNotifier<List<String>>([]);
  late double cellWidth;
  late double cellHeight;

  final Map<int, PlayerComponent> playerComponents = {};
  final Map<String, BombComponent> bombComponents = {};
  final Map<int, BlockComponent> blockComponents = {};
  late int localPlayerId; // from ASSIGN_ID
  late int? winner;

  late DigitComponent minutesTensDigit;
  late DigitComponent minutesOnesDigit;
  late DigitComponent colon;
  late DigitComponent secondsTensDigit;
  late DigitComponent secondsOnesDigit;

  final String serverIp;
  final int serverPort;

  BombermanGame({required this.serverIp, required this.serverPort});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await FlameAudio.audioCache.loadAll([
      'audio/death.mp3',
      'audio/draw.mp3',
      'audio/explosion.mp3',
      'audio/lose.mp3',
      'audio/powerup.mp3',
      'audio/win.mp3',
    ]);
    camera.viewport = FixedResolutionViewport(resolution: Vector2(768, 792));
    final Background background = Background();
    background.priority = -10;
    add(background);
    add(HudComponent());
    minutesTensDigit = DigitComponent(Vector2(99, 27));
    minutesOnesDigit = DigitComponent(Vector2(115, 27));
    colon = DigitComponent(Vector2(127, 27));
    secondsTensDigit = DigitComponent(Vector2(143, 27));
    secondsOnesDigit = DigitComponent(Vector2(159, 27));
    add(minutesOnesDigit);
    add(minutesTensDigit);
    add(colon);
    add(secondsTensDigit);
    add(secondsOnesDigit);

    final int rows = 13;
    final int cols = 15;
    cellWidth = 720 / cols;
    cellHeight = 720 / rows;

    print("Attempting connection to ws://$serverIp:$serverPort");
    channel = WebSocketChannel.connect(Uri.parse('ws://$serverIp:$serverPort')); 

    // listens to server
    channel.stream.listen((data) {
      final msg = jsonDecode(data);
      switch (msg['tag']){
        case 'ASSIGN_ID':
          _assignLocalId(msg);
          break;
        case 'UPDATE':
          _updateGameState(msg);
          break;
        case 'GAME_OVER':
          _triggerGameOver(msg);
      }
    }
  );
  }

  @override
  void onRemove() {
    channel.sink.close(); // close connection
    super.onRemove();
  }

  void _assignLocalId(Map<String, dynamic> msg){
    final int id = msg['id'];
    localPlayerId = id;
  }

  void _updateGameState(Map<String, dynamic> msg){
    final state = msg['state'];
    final map = state['map'];
    final players = state['players'];
    final bombs = state['bombs'];
    final time_left = state['time_left'];
    _updateGrid(map);
    _updatePlayerMovements(players);
    _updateBombs(bombs);
    _updateTimer(time_left);
  }

  // builds grid per server tick
  void _updateGrid(Map<String, dynamic> grid) {
    final rows = grid['grid'];
    int r = 0;
    int c = 0;

    for (List<dynamic> row in rows) {
      for (int index in row) {
        final key = r * row.length + c;
        final existing = blockComponents[key];
        if (index == 0) {
          if (existing is FireUp || existing is SpeedUp || existing is BombUp) {
            FlameAudio.play('powerup.mp3');
          }
          existing?.removeFromParent();
          final block = WalkableBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c);
          block.priority = -9;
          add(block);
          blockComponents[key] = block;
        }
        else if (index == 1 && existing is! HardBlock) {
          existing?.removeFromParent();
          final block = HardBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c);
          add(block);
          blockComponents[key] = block;
        }
        else if (index == 2 && existing is! SoftBlock) {
          existing?.removeFromParent();
          final block = SoftBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c);
          add(block);
          blockComponents[key] = block;
        }
        else if (index == 4 && existing is! ExplosionBlock) {
          existing?.removeFromParent();
          final block = ExplosionBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c);
          add(block);
          blockComponents[key] = block;
        }
        else if (index == 5 && existing is! FireUp) {
          existing?.removeFromParent();
          final block = FireUp(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c);
          add(block);
          blockComponents[key] = block;
        }
        else if (index == 6 && existing is! BombUp) {
          existing?.removeFromParent();
          final block = BombUp(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c);
          add(block);
          blockComponents[key] = block;
        }
        else if (index == 7 && existing is! SpeedUp) {
          existing?.removeFromParent();
          final block = SpeedUp(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c);
          add(block);
          blockComponents[key] = block;
        }
        c++;
      }
      c = 0;
      r++;
    }
  }

  void _updatePlayerMovements(Map<String, dynamic> players){
    final currentPlayerKeys = players.keys.toSet();
    playerComponents.keys.toList().forEach((id) {
      if (!currentPlayerKeys.contains(id.toString())) {
        FlameAudio.play('death.mp3');
        remove(playerComponents[id]!);
        playerComponents.remove(id);
      }
    });

    players.forEach((idStr, playerData) {
      final id = int.parse(idStr);
      final x = (playerData['x'] as num).toDouble();
      final y = (playerData['y'] as num).toDouble();

      final position = Vector2(x * cellWidth + 24, y * cellHeight + 72);

      if (!playerComponents.containsKey(id)) {

        final isLocal = (id == localPlayerId);
        final player = isLocal
            ? LocalPlayer(playerId: id, channel: channel, position: position, size: Vector2(cellWidth, cellHeight + 15))
            : RemotePlayer(playerId: id, position: position, size: Vector2(cellWidth, cellHeight + 15));

        add(player);
        playerComponents[id] = player;
      } else {
        playerComponents[id]!.updatePosition(position);
      }
    });
  }

  void _updateBombs(List<dynamic> bombs){
    final currentBombKeys = bombs.map((b) => "${b['x']}_${b['y']}").toSet();
    bombComponents.keys.toList().forEach((key) {
      if (!currentBombKeys.contains(key)) {
        FlameAudio.play('explosion.mp3');
        remove(bombComponents[key]!);
        bombComponents.remove(key);
      }
    });

    for (var bombData in bombs) {
      final x = bombData['x'] as int;
      final y = bombData['y'] as int;
      final key = "${x}_$y";

      final position = Vector2(x * cellWidth + 24, y * cellHeight + 72);

      if (!bombComponents.containsKey(key)) {
        final bomb = BombComponent(position: position, size: Vector2(cellWidth, cellHeight));
        bomb.priority = -8;
        add(bomb);
        bombComponents[key] = bomb;
      } else {
        bombComponents[key]!.updatePosition(position);
      }
    }
  }

  void _updateTimer(int timeLeft){
    final int timeLeftInSeconds = (timeLeft / 1000).floor();
    final minutes = timeLeftInSeconds ~/ 60;
    final int seconds = timeLeftInSeconds % 60;

    minutesTensDigit.updateSprite((minutes / 10).floor());
    minutesOnesDigit.updateSprite((minutes % 10));
    colon.updateSprite(10);
    secondsTensDigit.updateSprite((seconds / 10).floor());
    secondsOnesDigit.updateSprite((seconds % 10));
  }

  void _triggerGameOver(Map<String, dynamic> msg){
    winner = msg['winner'];
    if (winner == localPlayerId) {
      FlameAudio.play('win.mp3');
    } else if (winner == null) {
      FlameAudio.play('draw.mp3');
    } else {
      FlameAudio.play('lose.mp3');
    }
    
    overlays.add('GameOver');
  }
}

abstract class PlayerComponent extends SpriteComponent with HasGameReference<BombermanGame> {
  final int playerId;
  late TextComponent nameTag;

  PlayerComponent({
    required this.playerId,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor(0.0, 0.25));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('player_$playerId.png');

    nameTag = TextComponent(
      text: 'P$playerId',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      anchor: Anchor.center,
      position: Vector2(size.x / 2, -10),
    );

    add(nameTag);
  }

  void updatePosition(Vector2 newPosition) {
    position = newPosition;
  }
}

// takes movement as input from local player
class LocalPlayer extends PlayerComponent with KeyboardHandler {
  final WebSocketChannel channel;

  LocalPlayer({
    required super.playerId,
    required super.position,
    required super.size,
    required this.channel,
  });

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    String? direction;
    bool bombPlaced = false;
    bool spaceHeld = false;
    if (keysPressed.contains(LogicalKeyboardKey.arrowUp)) direction = "UP";
    if (keysPressed.contains(LogicalKeyboardKey.arrowDown)) direction = "DOWN";
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) direction = "LEFT";
    if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) direction = "RIGHT";
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent && !spaceHeld) {
        spaceHeld = true;
        bombPlaced = true;
      }
      if (event is KeyUpEvent) {
        spaceHeld = false;
      }
    }
    // encode and send JSON message to server
    if (direction != null) {
      print("sending PLAYER_MOVE $direction");
      final msg = {"tag": "PLAYER_MOVE", "direction": direction};
      channel.sink.add(jsonEncode(msg));
    }

    if (bombPlaced) {
      print("sending PLACE_BOMB");
      final msg = {"tag": "PLACE_BOMB"};
      channel.sink.add(jsonEncode(msg));
      bombPlaced = false;
    }
    return true;
  }
}

class RemotePlayer extends PlayerComponent {

  RemotePlayer({
    required super.playerId,
    required super.position,
    required super.size,
  });
}

class BombComponent extends SpriteComponent with HasGameReference<BombermanGame> {
  BombComponent({
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('bomb.png');
  }

  void updatePosition(Vector2 newPosition) {
    position = newPosition;
  }
}

abstract class BlockComponent extends SpriteComponent {
  final double cellWidth;
  final double cellHeight;
  final int row;
  final int col;

  BlockComponent({
    required this.cellWidth,
    required this.cellHeight,
    required this.row,
    required this.col,
  }) : super(
          size: Vector2(cellWidth, cellHeight),
          anchor: Anchor.topLeft,
        );

  void updatePosition(Vector2 newPosition) {
    position = newPosition;
  }
}

class ExplosionBlock extends BlockComponent with HasGameReference<BombermanGame> {

  ExplosionBlock({
    required super.cellWidth,
    required super.cellHeight,
    required super.row,
    required super.col,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('explosion.png');
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

class HardBlock extends BlockComponent with HasGameReference<BombermanGame> {
    HardBlock({
    required super.cellWidth,
    required super.cellHeight,
    required super.row,
    required super.col,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('hard_block.png'); //to do: add in assets folder
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

class SoftBlock extends BlockComponent with HasGameReference<BombermanGame> {
  SoftBlock({
  required super.cellWidth,
  required super.cellHeight,
  required super.row,
  required super.col,
});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('soft_block.png'); //to do: add in assets folder
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

class WalkableBlock extends BlockComponent with HasGameReference<BombermanGame> {
  WalkableBlock({
  required super.cellWidth,
  required super.cellHeight,
  required super.row,
  required super.col,
});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('walkable_block.png');
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

class FireUp extends BlockComponent with HasGameReference<BombermanGame> {
  FireUp({
  required super.cellWidth,
  required super.cellHeight,
  required super.row,
  required super.col,
});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('fireUp.png');
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

class BombUp extends BlockComponent with HasGameReference<BombermanGame> {
  BombUp({
  required super.cellWidth,
  required super.cellHeight,
  required super.row,
  required super.col,
});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('bombUp.png');
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

class SpeedUp extends BlockComponent with HasGameReference<BombermanGame> {
  SpeedUp({
  required super.cellWidth,
  required super.cellHeight,
  required super.row,
  required super.col,
});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('speedUp.png');
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}
