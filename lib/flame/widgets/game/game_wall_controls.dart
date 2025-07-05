import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';

import '../../../flame/constants.dart';
import '../../../flame/services/localizations.dart';
import '../../controller/game_controller.dart';

/// A widget for controlling wall placement in the game.
///
/// This widget provides controls for:
/// - Toggling wall orientation (horizontal/vertical)
/// - Moving the wall preview
/// - Confirming wall placement
class GameWallControls extends StatefulWidget {
  final QuoridorGame game;
  final bool isWideScreen;
  final GameController? gameController;

  /// Creates a new instance of [GameWallControls].
  const GameWallControls({
    super.key,
    required this.game,
    this.isWideScreen = false,
    this.gameController,
  });

  @override
  State<GameWallControls> createState() => _GameWallControlsState();
}

class _GameWallControlsState extends State<GameWallControls> {
  void _confirmWallPlacement() {
    if (widget.game.gameState?.previewWall == null) return;

    final wall = Wall(
      widget.game.gameState!.previewWall!.position,
      widget.game.gameState!.wallOrientation,
    );

    if (widget.gameController != null) {
      widget.gameController!.add(PlaceWall(wall));
    } else {
      widget.game.handleWallPlaceAttempt(wall);
    }
    setState(() {});
  }

  void _handleWallMovement(String direction) {
    Position? newPosition;

    if (widget.game.gameState?.previewWall == null) {
      widget.game.gameState!.previewWall = Wall(
        Position(4, 4),
        widget.game.gameState!.wallOrientation,
      );
    }
    switch (direction) {
      case 'up':
        if (widget.game.gameState!.previewWall!.position.row > 0) {
          newPosition = Position(
            widget.game.gameState!.previewWall!.position.row - 1,
            widget.game.gameState!.previewWall!.position.col,
          );
        }
        break;
      case 'down':
        if (widget.game.gameState!.previewWall!.position.row <
            GameConstants.boardSize - 1) {
          newPosition = Position(
            widget.game.gameState!.previewWall!.position.row + 1,
            widget.game.gameState!.previewWall!.position.col,
          );
        }
        break;
      case 'left':
        if (widget.game.gameState?.previewWall?.position.col != null &&
            widget.game.gameState!.previewWall!.position.col > 0) {
          newPosition = Position(
            widget.game.gameState!.previewWall!.position.row,
            widget.game.gameState!.previewWall!.position.col - 1,
          );
        }
        break;
      case 'right':
        if (widget.game.gameState?.previewWall?.position.col != null &&
            widget.game.gameState!.previewWall!.position.col <
                GameConstants.boardSize - 1) {
          newPosition = Position(
            widget.game.gameState!.previewWall!.position.row,
            widget.game.gameState!.previewWall!.position.col + 1,
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
      widget.game.gameState!.previewWall = Wall(
        newPosition,
        widget.game.gameState!.wallOrientation,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      const SizedBox(width: 8),
      Center(child: _buildOrientationButton(context)),
      if (!widget.isWideScreen) const Spacer(),
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
    ];
    if (widget.isWideScreen) {
      return Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        children: children,
      );
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
  }

  Widget _buildOrientationButton(BuildContext context) {
    final isVertical =
        widget.game.gameState?.wallOrientation == WallOrientation.vertical;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8,
      children: [
        IconButton(
          onPressed: () {
            if (widget.gameController != null) {
              widget.gameController!.add(ToggleWallOrientation());
            } else {
              widget.game.toggleWallOrientation();
            }
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
