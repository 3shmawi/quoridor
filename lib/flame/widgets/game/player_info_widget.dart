import 'package:flutter/material.dart';

/// A widget that displays information about a player in the game.
///
/// This widget shows:
/// - Player name
/// - Number of walls remaining
/// - Current player indicator
/// - AI indicator (if applicable)
class PlayerInfoWidget extends StatelessWidget {
  /// The player's ID (1 or 2)
  final int playerId;

  /// The player's name
  final String name;

  /// Number of walls remaining for the player
  final int wallsRemaining;

  /// Whether this player is the current player
  final bool isCurrentPlayer;

  /// Whether this player is controlled by AI
  final bool isAI;

  /// Creates a new instance of [PlayerInfoWidget].
  const PlayerInfoWidget({
    super.key,
    required this.playerId,
    required this.name,
    required this.wallsRemaining,
    required this.isCurrentPlayer,
    required this.isAI,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrentPlayer
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: isCurrentPlayer ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (isAI) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.computer,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
                if (isCurrentPlayer) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.play_arrow,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.wallpaper,
                  size: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  '$wallsRemaining walls left',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
