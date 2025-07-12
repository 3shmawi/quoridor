import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/theme.dart';

import '../../../flame/constants.dart';
import '../../controller/game_controller.dart';
import '../../controller/game_states.dart';
import '../../services/localizations.dart';

/// A widget for controlling wall placement in the game.
///
/// This widget provides controls for:
/// - Toggling wall orientation (horizontal/vertical)
/// - Moving the wall preview
/// - Confirming wall placement
class GameWallControls extends StatefulWidget {
  final bool isWideScreen;
  final GameController? gameController;

  /// Creates a new instance of [GameWallControls].
  const GameWallControls({
    super.key,
    this.isWideScreen = false,
    this.gameController,
  });

  @override
  State<GameWallControls> createState() => _GameWallControlsState();
}

class _GameWallControlsState extends State<GameWallControls> {
  void _confirmWallPlacement() {
    if (widget.gameController == null) return;

    final state = widget.gameController!.state;
    if (state is! GamePlayingState) return;

    final gameState = state.gameState;
    if (gameState.previewWall == null) return;

    final wall = Wall(
      gameState.previewWall!.position,
      gameState.wallOrientation,
    );

    widget.gameController!.add(PlaceWall(wall));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameController, GameStates>(
      builder: (context, state) {
        if (state is! GamePlayingState) {
          return const SizedBox.shrink();
        }

        final children = [
          IconButton(
            onPressed: () {
              if (widget.gameController != null) {
                widget.gameController!.add(ToggleWallOrientation());
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
              ).colorScheme.primary.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),

          Icon(CupertinoIcons.game_controller),
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

        return Stack(
          alignment: Alignment.topCenter,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: children,
              ),
            ),
            Positioned(
              top: 0,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 5,
                  children: [
                    Icon(Icons.rotate_left),

                    Text(
                      // TODO: Localize this string
                      "Wall controls",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.control_point_duplicate),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
