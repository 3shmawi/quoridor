import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';

class EmojiAnimationComponent extends PositionComponent {
  final String emoji;
  final Vector2 gameSize;
  late final SpriteComponent _emojiSprite;
  double _scale = 0.0;
  double _opacity = 0.0;
  bool _isAnimating = false;

  EmojiAnimationComponent({required this.emoji, required this.gameSize})
    : super(
        position: Vector2(gameSize.x / 2, gameSize.y / 2),
        size: Vector2(200, 200),
        anchor: Anchor.center,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await _loadEmoji();
  }

  Future<void> _loadEmoji() async {
    String emojiPath;
    switch (emoji) {
      case '😊':
        emojiPath = 'assets/emojis/happy.png';
        break;
      case '😂':
        emojiPath = 'assets/emojis/laugh.png';
        break;
      case '😡':
        emojiPath = 'assets/emojis/angry.png';
        break;
      case '👍':
        emojiPath = 'assets/emojis/thumbs_up.png';
        break;
      default:
        emojiPath = 'assets/emojis/happy.png';
    }

    final sprite = await (parent as QuoridorGame).loadSprite(emojiPath);
    _emojiSprite = SpriteComponent(
      sprite: sprite,
      size: size,
      anchor: Anchor.center,
    );
    add(_emojiSprite);
  }

  void playAnimation() {
    _isAnimating = true;
    _scale = 0.0;
    _opacity = 0.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isAnimating) {
      if (_scale < 1.0) {
        _scale += dt * 2;
        if (_scale > 1.0) _scale = 1.0;
      }
      if (_opacity < 1.0) {
        _opacity += dt * 2;
        if (_opacity > 1.0) _opacity = 1.0;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (!_isAnimating) return;

    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.scale(_scale, _scale);
    canvas.translate(-position.x, -position.y);

    final paint = Paint()
      ..color = Colors.white.withOpacity(_opacity)
      ..style = PaintingStyle.fill;

    // Draw a circular background
    canvas.drawCircle(Offset(position.x, position.y), size.x / 2, paint);

    canvas.restore();
  }

  @override
  void onRemove() {
    _isAnimating = false;
    super.onRemove();
  }
}
