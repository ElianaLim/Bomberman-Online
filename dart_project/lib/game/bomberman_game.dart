import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:flame/events.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';

import 'assets.dart';

// -------------------------- Flame Game --------------------------

class BombermanGame extends FlameGame with HasKeyboardHandlerComponents {
  late WebSocketChannel channel;
  final ValueNotifier<List<int>> connectedPlayers = ValueNotifier<List<int>>([]);
  final ValueNotifier<int> countdown = ValueNotifier<int>(0);
  late double cellWidth;
  late double cellHeight;

  final Map<int, PlayerComponent> playerComponents = {};
  final Map<String, BombComponent> bombComponents = {};
  final Map<int, BlockComponent> blockComponents = {};
  int totalPlayers = 0;
  late int localPlayerId; // from ASSIGN_ID
  late int? winner;

  late DigitComponent minutesTensDigit;
  late DigitComponent minutesOnesDigit;
  late DigitComponent colon;
  late DigitComponent secondsTensDigit;
  late DigitComponent secondsOnesDigit;


  BombermanGame();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await images.loadAll(imageAssets);
    await FlameAudio.audioCache.loadAll(audioAssets);
    final Background background = Background();
    background.priority = -10;
    add(background);
    minutesTensDigit = DigitComponent(Vector2(99, 27));
    minutesOnesDigit = DigitComponent(Vector2(115, 27));
    colon = DigitComponent(Vector2(127, 27));
    secondsTensDigit = DigitComponent(Vector2(143, 27));
    secondsOnesDigit = DigitComponent(Vector2(159, 27));

    final int rows = 13;
    final int cols = 15;
    cellWidth = 720 / cols;
    cellHeight = 720 / rows;
  }

  @override
  void onRemove() {
    channel.sink.close();
    super.onRemove();
  }

  void assignLocalId(Map<String, dynamic> msg){
    final int id = msg['id'];
    localPlayerId = id;
  }

  void updateGameState(Map<String, dynamic> msg){
    final state = msg['state'];
    final map = state['map'];
    final players = state['players'];
    final bombs = state['bombs'];
    final timeLeft = state['time_left'];
    _updateGridState(map);
    _updatePlayersState(players);
    _updateBombsState(bombs);
    _updateTimerState(timeLeft);
  }

  // updates the game grid for every server tick
  void _updateGridState(Map<String, dynamic> grid) {
    final rows = grid['grid'];

    bool isExplosionBlock(int? index) => index == 4 || index == 5 || index == 6;

    String getExplosionAnimation(int index, int? top, int? bottom, int? left, int? right) {
      if (isExplosionBlock(top) && isExplosionBlock(bottom) && !isExplosionBlock(left) && !isExplosionBlock(right) && index == 5) {
        return "middle_vertical";
      } else if (!isExplosionBlock(top) && isExplosionBlock(bottom) && !isExplosionBlock(left) && !isExplosionBlock(right) && index == 6) {
        return "tip_top";
      } else if (isExplosionBlock(top) && !isExplosionBlock(bottom) && !isExplosionBlock(left) && !isExplosionBlock(right) && index == 6) {
        return "tip_bottom";
      } else if (!isExplosionBlock(top) && !isExplosionBlock(bottom) && isExplosionBlock(left) && isExplosionBlock(right) && index == 5) {
        return "middle_horizontal";
      } else if (!isExplosionBlock(top) && !isExplosionBlock(bottom) && !isExplosionBlock(left) && isExplosionBlock(right) && index == 6) {
        return "tip_left";
      } else if (!isExplosionBlock(top) && !isExplosionBlock(bottom) && isExplosionBlock(left) && !isExplosionBlock(right) && index == 6) {
        return "tip_right";
      }
      return "center";
    }

    void replaceBlock(int key, dynamic oldBlock, dynamic newBlock) {
      add(newBlock);
      blockComponents[key] = newBlock;
    }

    for (int r = 0; r < rows.length; r++) {
      final int rowLength = rows[r].length;
      for (int c = 0; c < rowLength; c++) {
        final int index = rows[r][c];
        final int key = r * rowLength + c;
        final existing = blockComponents[key];

        final indexTop = r > 0 ? rows[r - 1][c] : null;
        final indexBottom = r < rows.length - 1 ? rows[r + 1][c] : null;
        final indexLeft = c > 0 ? rows[r][c - 1] : null;
        final indexRight = c < rowLength - 1 ? rows[r][c + 1] : null;

        switch (index) {
          case 0:
            if (existing is FireUp || existing is SpeedUp || existing is BombUp) {
              FlameAudio.play('powerup.mp3');
            }
            if (existing is SoftBlock) {
              existing.onExplosion();
              Future.delayed(const Duration(seconds: 1), () {
                existing.removeFromParent();
              });
            } else {
              existing?.removeFromParent();
            }
            replaceBlock(
              key,
              existing,
              WalkableBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c)..priority = -9,
            );
            break;
          case 1:
            if (existing is! HardBlock) {
              existing?.removeFromParent();
              replaceBlock(key, existing, HardBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c));
            }
            break;
          case 2:
            if (existing is! SoftBlock) {
              existing?.removeFromParent();
              replaceBlock(key, existing, SoftBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c));
            }
            break;
          case 4:
          case 5:
          case 6:
            if (existing is! ExplosionBlock) {
              existing?.removeFromParent();
              final animation = getExplosionAnimation(index, indexTop, indexBottom, indexLeft, indexRight);
              replaceBlock(key, existing, ExplosionBlock(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c, animationType: animation)..priority = -8);
            }
            break;
          case 7:
            if (existing is! FireUp) {
              existing?.removeFromParent();
              replaceBlock(key, existing, FireUp(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c));
            }
            break;
          case 8:
            if (existing is! BombUp) {
              existing?.removeFromParent();
              replaceBlock(key, existing, BombUp(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c));
            }
            break;
          case 9:
            if (existing is! SpeedUp) {
              existing?.removeFromParent();
              replaceBlock(key, existing, SpeedUp(cellWidth: cellWidth, cellHeight: cellHeight, row: r, col: c));
            }
            break;
        }
      }
    }
  }

  // updates states of players (local and remote) for every server tick
  void _updatePlayersState(Map<String, dynamic> players) {
    final currentIds = players.keys.map(int.parse).toSet();

    final idsToRemove = playerComponents.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in idsToRemove) {
      final player = playerComponents[id];
      if (player != null) {
        FlameAudio.play('death.mp3');
        player.playerDies();
        playerComponents.remove(id);
      }
    }

    players.forEach((idStr, data) {
      final id = int.parse(idStr);
      final x = (data['x'] as num).toDouble();
      final y = (data['y'] as num).toDouble();

      final position = Vector2(
        x * cellWidth + 24,
        y * cellHeight + 72,
      );

      final size = Vector2(cellWidth, cellHeight + 15);

      final existing = playerComponents[id];
      if (existing == null) {
        final isLocal = id == localPlayerId;

        final player = isLocal
            ? LocalPlayer(
                playerId: id,
                channel: channel,
                position: position,
                size: size,
              )
            : RemotePlayer(
                playerId: id,
                position: position,
                size: size,
              );

        add(player);
        playerComponents[id] = player;
      } else {
        existing.updatePosition(position);
      }
    });
  }

  // updates states of bombs for every server tick
  void _updateBombsState(List<dynamic> bombs) {
    final currentKeys = bombs
        .map<String>((b) => "${b['x']}_${b['y']}")
        .toSet();

    final keysToRemove = bombComponents.keys
        .where((key) => !currentKeys.contains(key))
        .toList();

    for (final key in keysToRemove) {
      final bomb = bombComponents[key];
      if (bomb != null) {
        FlameAudio.play('explosion.mp3', volume: 0.5);
        remove(bomb);
        bombComponents.remove(key);
      }
    }

    for (final bombData in bombs) {
      final x = bombData['x'] as int;
      final y = bombData['y'] as int;
      final key = "${x}_$y";

      final position = Vector2(
        x * cellWidth + 24,
        y * cellHeight + 72,
      );

      final existing = bombComponents[key];
      if (existing == null) {
        final bomb = BombComponent(
          position: position,
          size: Vector2(cellWidth, cellHeight),
        )..priority = -8;

        add(bomb);
        bombComponents[key] = bomb;
      } else {
        existing.updatePosition(position);
      }
    }
  }

  // updates state of timer for every server tick
  void _updateTimerState(int timeLeftMs) {
    final totalSeconds = (timeLeftMs / 1000).floor();

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    int tens(int value) => value ~/ 10;
    int ones(int value) => value % 10;

    minutesTensDigit.updateSprite(tens(minutes));
    minutesOnesDigit.updateSprite(ones(minutes));

    colon.updateSprite(10); // fixed colon index

    secondsTensDigit.updateSprite(tens(seconds));
    secondsOnesDigit.updateSprite(ones(seconds));
  }

  void triggerGameOver(Map<String, dynamic> msg) {
    winner = msg['winner'];

    final sound = (winner == null)
        ? 'draw.mp3'
        : (winner == localPlayerId ? 'win.mp3' : 'lose.mp3');

    FlameAudio.play(sound);

    overlays.add('GameOver');
  }
}

// -------------------------- Game Components --------------------------

// Digits of the visible timer
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
 
// The game's status bar containing the timer
class HudComponent extends SpriteComponent with HasGameReference<BombermanGame>{
  HudComponent() : super(position: Vector2(0, 0), size: Vector2 (768, 72), anchor: Anchor.topLeft);
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await game.loadSprite('HUD.png');
  }
}

// The gray background below the visible game screen
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

// Abstract Player class
abstract class PlayerComponent extends SpriteAnimationComponent with HasGameReference<BombermanGame> {
  final int playerId;
  late TextComponent nameTag;
  bool isFirstMovement = true;
  String lastDirection = "down";

  PlayerComponent({
    required this.playerId,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor(0.0, 0.25));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    animation = await game.loadSpriteAnimation(
      'Player_${playerId}_down.png',
      SpriteAnimationData.sequenced(
        amount: 1,
        stepTime: .2,
        textureSize: Vector2(17, 22),
        ),
      );

    nameTag = TextComponent(
      text: 'Player $playerId',
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

  void updatePosition(Vector2 newPosition) async {
    Vector2 delta = position - newPosition;
    String direction = "idle";
    if (delta == Vector2(0, 0)){
      direction == "idle";
    }
    else if (delta.y > 0.0){
      direction = "up";
    }
    else if (delta.y < 0.0){
      direction = "down";
    }
    else if (delta.x > 0){
      direction = "left";
    }
    else if (delta.x < 0){
      direction = "right";
    }

    if (direction == "idle") {
      animation = await game.loadSpriteAnimation(
      'Player_${playerId}_$lastDirection.png',
      SpriteAnimationData.sequenced(
        amount: 1,
        stepTime: .2,
        textureSize: Vector2(17, 22),
        ),
      );
      isFirstMovement = true;
    }
    else {
      if (isFirstMovement) {
        animation = await game.loadSpriteAnimation(
        'Player_${playerId}_walking_$direction.png',
        SpriteAnimationData.sequenced(
          amount: 2,
          stepTime: .2,
          textureSize: Vector2(17, 22),
          ),
        );
        isFirstMovement = false;
      }
      lastDirection = direction;
    }
    position = newPosition;
  }

  void playerDies() async {
    animation = await game.loadSpriteAnimation(
    'Player_${playerId}_exploding.png',
    SpriteAnimationData.sequenced(
      amount: 9,
      stepTime: .08,
      textureSize: Vector2(21, 22),
      loop: false,
      ),
    );
    await Future.delayed(Duration(milliseconds: (0.72 * 1000).toInt()));
    game.remove(this);
  }
}

// The client
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

    if (direction != null) {
      final msg = {"tag": "PLAYER_MOVE", "direction": direction};
      channel.sink.add(jsonEncode(msg));
    }

    if (bombPlaced) {
      final msg = {"tag": "PLACE_BOMB"};
      channel.sink.add(jsonEncode(msg));
      bombPlaced = false;
    }
    return true;
  }
}

// Other player from a different client
class RemotePlayer extends PlayerComponent {

  RemotePlayer({
    required super.playerId,
    required super.position,
    required super.size,
  });
}

// Bomb
class BombComponent extends SpriteAnimationComponent with HasGameReference<BombermanGame> {
  BombComponent({
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    animation = await game.loadSpriteAnimation(
    'bomb.png',
    SpriteAnimationData.sequenced(
      amount: 2,
      stepTime: .2,
      textureSize: Vector2(16, 16),
      ),
    );
  }

  void updatePosition(Vector2 newPosition) {
    position = newPosition;
  }
}

// Abstract Block class for objects on the grid's cells (Use this to create new power ups)
abstract class BlockComponent extends SpriteAnimationComponent {
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

  void onExplosion(){
  }
}

// Explosion block (for animation)
class ExplosionBlock extends BlockComponent with HasGameReference<BombermanGame> {
  final String animationType;
  ExplosionBlock({
    required super.cellWidth,
    required super.cellHeight,
    required super.row,
    required super.col,
    required this.animationType,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    animation = await game.loadSpriteAnimation(
    'explosion_$animationType.png',
    SpriteAnimationData.sequenced(
      amount: 8,
      stepTime: .125,
      textureSize: Vector2(16, 16),
      loop: false,
      ),
    );
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

// Hard block (for borders and inner blocks)
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
    animation = await game.loadSpriteAnimation(
    'hard_block.png',
    SpriteAnimationData.sequenced(
      amount: 1,
      stepTime: .2,
      textureSize: Vector2(16, 16),
      ),
    );
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

// Soft Block
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
    animation = await game.loadSpriteAnimation(
    'soft_block.png',
    SpriteAnimationData.sequenced(
      amount: 1,
      stepTime: .2,
      textureSize: Vector2(16, 16),
      ),
    );
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }

  @override
  void onExplosion() async {
    animation = await game.loadSpriteAnimation(
    'soft_block_exploding.png',
    SpriteAnimationData.sequenced(
      amount: 8,
      stepTime: .125,
      textureSize: Vector2(16, 16),
      loop: false,
      ),
    );
  }
}

// Walkable Block
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
    animation = await game.loadSpriteAnimation(
    'walkable_block.png',
    SpriteAnimationData.sequenced(
      amount: 1,
      stepTime: .2,
      textureSize: Vector2(16, 16),
      ),
    );
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

// Fire up Power up
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
    animation = await game.loadSpriteAnimation(
    'fireUp.png',
    SpriteAnimationData.sequenced(
      amount: 2,
      stepTime: .2,
      textureSize: Vector2(16, 16),
      ),
    );
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

// Bomb up Power up
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
    animation = await game.loadSpriteAnimation(
    'bombUp.png',
    SpriteAnimationData.sequenced(
      amount: 2,
      stepTime: .2,
      textureSize: Vector2(16, 16),
      ),
    );
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}

// Speed up Power up
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
    animation = await game.loadSpriteAnimation(
    'speedUp.png',
    SpriteAnimationData.sequenced(
      amount: 2,
      stepTime: .2,
      textureSize: Vector2(16, 16),
      ),
    );
    position = Vector2(col * cellWidth + 24, row * cellHeight + 72);
  }
}