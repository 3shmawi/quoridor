import 'package:flutter/material.dart';

/// A custom app bar widget for the Quoridor game.
///
/// This widget displays the game title, menu button, and game info button.
/// It provides a consistent header for the game interface.
class GameAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Callback function when the game info button is pressed
  final VoidCallback onGameInfoPressed;

  /// Creates a new instance of [GameAppBar].
  const GameAppBar({super.key, required this.onGameInfoPressed});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      automaticallyImplyLeading: false,
      title: Row(
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Game Info Button
          IconButton(
            onPressed: onGameInfoPressed,
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
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
