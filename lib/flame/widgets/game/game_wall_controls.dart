import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';

import '../../../flame/constants.dart';
import '../../../flame/services/localizations.dart';

/// A widget for controlling wall placement in the game.
///
/// This widget provides controls for:
/// - Toggling wall orientation (horizontal/vertical)
/// - Moving the wall preview
/// - Confirming wall placement
class GameWallControls extends StatefulWidget {
  final QuoridorGame game;

  /// Creates a new instance of [GameWallControls].
  const GameWallControls({super.key, required this.game});

  @override
  State<GameWallControls> createState() => _GameWallControlsState();
}

class _GameWallControlsState extends State<GameWallControls> {
  late final gameState = widget.game.gameState;

  void _confirmWallPlacement() {
    if (gameState.previewWall == null) return;

    final wall = Wall(
      gameState.previewWall!.position,
      gameState.wallOrientation,
    );

    widget.game.handleWallPlaceAttempt(wall);
    setState(() {});
  }

  void _handleWallMovement(String direction) {
    Position? newPosition;

    if (gameState.previewWall == null) {
      newPosition = Position(4, 4);
      _moveWallPreview(newPosition);
    }
    switch (direction) {
      case 'up':
        if (gameState.previewWall!.position.row > 0) {
          newPosition = Position(
            gameState.previewWall!.position.row - 1,
            gameState.previewWall!.position.col,
          );
        }
        break;
      case 'down':
        if (gameState.previewWall!.position.row < GameConstants.boardSize - 1) {
          newPosition = Position(
            gameState.previewWall!.position.row + 1,
            gameState.previewWall!.position.col,
          );
        }
        break;
      case 'left':
        if (gameState.previewWall!.position.col > 0) {
          newPosition = Position(
            gameState.previewWall!.position.row,
            gameState.previewWall!.position.col - 1,
          );
        }
        break;
      case 'right':
        if (gameState.previewWall!.position.col < GameConstants.boardSize - 1) {
          newPosition = Position(
            gameState.previewWall!.position.row,
            gameState.previewWall!.position.col + 1,
          );
        }
        break;
    }
    if (newPosition != null) {
      _moveWallPreview(newPosition);
    }
  }

  void _moveWallPreview(Position? newPosition) {
    if (newPosition == null) return;
    setState(() {
      gameState.previewWall = Wall(newPosition, gameState.wallOrientation);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 8),
        _buildOrientationButton(context),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _handleWallMovement('left'),
              icon: const Icon(Icons.arrow_back),
            ),
            Column(
              children: [
                IconButton(
                  onPressed: () => _handleWallMovement('up'),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  onPressed: _confirmWallPlacement,
                  icon: const Icon(Icons.check, color: Colors.green, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.green),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _handleWallMovement('down'),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            IconButton(
              onPressed: () => _handleWallMovement('right'),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOrientationButton(BuildContext context) {
    final isVertical =
        widget.game.gameState.wallOrientation == WallOrientation.vertical;
    return Row(
      spacing: 8,
      children: [
        IconButton(
          onPressed: () {
            widget.game.toggleWallOrientation();
            setState(() {});
          },
          icon: Transform.rotate(
            angle: isVertical ? pi / 2 : 0,
            child: Icon(
              Icons.horizontal_rule,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
          ),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.1),
            padding: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        Text(
          isVertical
              ? AppLocale.vertical.getString(context)
              : AppLocale.horizontal.getString(context),
        ),
      ],
    );
  }
}
