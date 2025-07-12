import 'package:flutter/material.dart';

/// A widget that displays information about a player in the game.
///
/// This widget shows:
/// - Player name
/// - Number of walls remaining
/// - Current player indicator
/// - AI indicator (if applicable)
class GamePlayerInfoWidget extends StatelessWidget {
  /// The player's ID (1 or 2)
  final int playerId;

  /// The player's name
  final String name;

  /// Number of walls remaining for the player
  final int wallsRemaining;

  /// Whether this player is the current player
  final bool isCurrentPlayer;

  /// Creates a new instance of [GamePlayerInfoWidget].
  const GamePlayerInfoWidget({
    super.key,
    required this.playerId,
    required this.name,
    required this.wallsRemaining,
    required this.isCurrentPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        Card(
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isCurrentPlayer)
          CircleAvatar(
            radius: 12,
            child: Text(
              "$wallsRemaining",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
