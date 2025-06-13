import 'package:flutter/material.dart';

/// A custom drawer widget for the Quoridor game.
///
/// This widget provides a navigation menu with game controls, display options,
/// and other settings. It's organized into sections for better user experience.
class GameDrawer extends StatelessWidget {
  /// Callback function when new game is requested
  final VoidCallback onNewGame;

  /// Callback function when save game is requested
  final VoidCallback onSaveGame;

  /// Callback function when player mode is toggled
  final VoidCallback onTogglePlayerMode;

  /// Callback function when valid moves visibility is toggled
  final VoidCallback onToggleValidMoves;

  /// Callback function when dark mode is toggled
  final VoidCallback onToggleDarkMode;

  /// Whether valid moves are currently shown
  final bool showValidMoves;

  /// Whether dark mode is currently enabled
  final bool isDarkMode;

  /// Whether player 2 is AI
  final bool isPlayer2AI;

  /// Creates a new instance of [GameDrawer].
  const GameDrawer({
    super.key,
    required this.onNewGame,
    required this.onSaveGame,
    required this.onTogglePlayerMode,
    required this.onToggleValidMoves,
    required this.onToggleDarkMode,
    required this.showValidMoves,
    required this.isDarkMode,
    required this.isPlayer2AI,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // Menu Header
            DrawerHeader(
              padding: EdgeInsets.zero,
              margin: EdgeInsets.zero,
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                image: const DecorationImage(
                  image: AssetImage('assets/icons/logo.png'),
                  fit: BoxFit.cover,
                ),
                color: Theme.of(context).colorScheme.primary,
              ),
              child: const SizedBox(
                height: double.infinity,
                width: double.infinity,
              ),
            ),

            // Menu Items
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMenuSection(context, 'Game Controls', [
                      _buildMenuItem(
                        context,
                        Icons.refresh,
                        'New Game',
                        'Start a fresh game',
                        onNewGame,
                      ),
                      _buildMenuItem(
                        context,
                        Icons.save,
                        'Save Game',
                        'Save current progress',
                        onSaveGame,
                      ),
                      _buildMenuItem(
                        context,
                        Icons.people,
                        'Toggle Player Mode',
                        isPlayer2AI ? 'Switch to 2 players' : 'Switch to AI',
                        onTogglePlayerMode,
                      ),
                    ]),

                    const SizedBox(height: 24),

                    _buildMenuSection(context, 'Display Options', [
                      _buildSwitchItem(
                        context,
                        Icons.visibility,
                        'Show Valid Moves',
                        'Highlight possible moves',
                        showValidMoves,
                        onToggleValidMoves,
                      ),
                      _buildSwitchItem(
                        context,
                        Icons.dark_mode,
                        'Dark Mode',
                        'Toggle dark mode',
                        isDarkMode,
                        onToggleDarkMode,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _buildSwitchItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    bool value,
    VoidCallback onChanged,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: (_) => onChanged(),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        Text.rich(
          textDirection: TextDirection.ltr,
          TextSpan(
            children: [
              TextSpan(
                text: "@copyWrite",
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
              const TextSpan(text: " "),
              const TextSpan(
                text: "MO",
                style: TextStyle(color: Colors.cyan),
              ),
              TextSpan(
                text: "RE",
                style: TextStyle(color: Theme.of(context).dividerColor),
              ),
              const TextSpan(
                text: " H",
                style: TextStyle(color: Colors.cyan),
              ),
            ],
          ),
        ),
        Text(
          "ASHMAWY",
          style: TextStyle(color: Theme.of(context).dividerColor),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
