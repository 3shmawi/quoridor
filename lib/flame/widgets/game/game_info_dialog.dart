import 'package:flutter/material.dart';

/// A dialog widget that displays information about how to play Quoridor.
///
/// This widget provides a comprehensive guide about the game rules,
/// objectives, and gameplay mechanics in an organized and visually appealing format.
class GameInfoDialog extends StatelessWidget {
  /// Creates a new instance of [GameInfoDialog].
  const GameInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('How to Play Quoridor')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoSection(
              context,
              '🎯 Objective',
              'Be the first player to reach the opposite side of the board.',
            ),
            _buildInfoSection(
              context,
              '🎮 Your Turn',
              'On each turn, either:\n• Move your pawn one space\n• Place a wall to block your opponent',
            ),
            _buildInfoSection(
              context,
              '🚶 Movement',
              'Move up, down, left, or right. Jump over your opponent if they\'re in your way.',
            ),
            _buildInfoSection(
              context,
              '🧱 Walls',
              'Each player has 10 walls. Place them strategically but don\'t completely block your opponent\'s path.',
            ),
            _buildInfoSection(
              context,
              '🏆 Winning',
              'Player 1 (purple) wins by reaching the bottom row.\nPlayer 2 (teal) wins by reaching the top row.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it!'),
        ),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
