import 'package:flutter/material.dart';

/// A custom app bar widget for the Quoridor game.
///
/// This widget displays the game title, menu button, and game info button.
/// It provides a consistent header for the game interface.
class GameAppBar extends StatefulWidget {
  /// Callback function when the game info button is pressed

  /// Creates a new instance of [GameAppBar].
  const GameAppBar({super.key});

  @override
  State<GameAppBar> createState() => _GameAppBarState();
}

class _GameAppBarState extends State<GameAppBar> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Menu Button
        Builder(
          builder: (context) {
            return IconButton(
              onPressed: Scaffold.of(context).openDrawer,
              icon: Icon(
                Icons.menu,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.1),
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          },
        ),

        const SizedBox(width: 16),

        // Game Title
        Expanded(
          child: Text(
            'Quoridor Game',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // Game Info Button
        IconButton(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => _buildGameInfoDialog(),
          ),
          icon: Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.secondary.withOpacity(0.1),
            foregroundColor: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildGameInfoDialog() {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: const Text('How to Play Quoridor')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoSection(
              '🎯 Objective',
              'Be the first player to reach the opposite side of the board.',
            ),
            _buildInfoSection(
              '🎮 Your Turn',
              'On each turn, either:\n• Move your pawn one space\n• Place a wall to block your opponent',
            ),
            _buildInfoSection(
              '🚶 Movement',
              'Move up, down, left, or right. Jump over your opponent if they\'re in your way.',
            ),
            _buildInfoSection(
              '🧱 Walls',
              'Each player has 10 walls. Place them strategically but don\'t completely block your opponent\'s path.',
            ),
            _buildInfoSection(
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

  Widget _buildInfoSection(String title, String content) {
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
