import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../../../flame/constants.dart';

/// A widget for controlling wall placement in the game.
///
/// This widget provides controls for:
/// - Toggling wall orientation (horizontal/vertical)
/// - Moving the wall preview
/// - Confirming wall placement
class GameWallControls extends StatelessWidget {
  /// The current wall orientation
  final WallOrientation orientation;

  /// Callback when wall orientation is changed
  final ValueChanged<WallOrientation> onOrientationChanged;

  /// Callback when wall movement is requested
  final ValueChanged<String> onWallMovement;

  /// Callback when wall placement is confirmed
  final VoidCallback onWallPlacementConfirmed;

  /// Creates a new instance of [GameWallControls].
  const GameWallControls({
    super.key,
    required this.orientation,
    required this.onOrientationChanged,
    required this.onWallMovement,
    required this.onWallPlacementConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 8),
        _buildOrientationButton(context),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => onWallMovement('left'),
              icon: const Icon(Icons.arrow_back),
            ),
            Column(
              children: [
                IconButton(
                  onPressed: () => onWallMovement('up'),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  onPressed: onWallPlacementConfirmed,
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
                  onPressed: () => onWallMovement('down'),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            IconButton(
              onPressed: () => onWallMovement('right'),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOrientationButton(BuildContext context) {
    final isVertical = orientation == WallOrientation.vertical;
    return Row(
      spacing: 8,
      children: [
        IconButton(
          onPressed: () {
            onOrientationChanged(
              orientation == WallOrientation.horizontal
                  ? WallOrientation.vertical
                  : WallOrientation.horizontal,
            );
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
        Text(isVertical ? "VERTICAL" : "HORIZONTAL"),
      ],
    );
  }
}
