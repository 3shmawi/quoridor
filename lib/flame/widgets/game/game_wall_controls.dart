import 'package:flutter/material.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';

import '../../../flame/constants.dart';
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

  @override
  Widget build(BuildContext context) {
    final children = [
      const SizedBox(width: 8),
      IconButton(
        onPressed: () {
          if (widget.gameController != null) {
            widget.gameController!.add(ToggleWallOrientation());
          } else {
            widget.game.toggleWallOrientation();
          }
          setState(() {});
        },
        icon: Icon(
          Icons.crop_rotate,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
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
      const Spacer(),
      IconButton(
        onPressed: _confirmWallPlacement,
        icon: const Icon(Icons.power_input, color: Colors.green, size: 28),
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.green),
          ),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }
}
