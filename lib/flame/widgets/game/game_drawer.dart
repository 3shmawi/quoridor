import 'package:flutter/material.dart';

import '/flame/game/quoridor_game.dart';
import '/theme.dart';
import '../../services/ai_service.dart';
import '../../services/firebase_service.dart';
import '../app/copywrite.dart';

/// A custom drawer widget for the Quoridor game.
///
/// This widget provides a navigation menu with game controls, display options,
/// and other settings. It's organized into sections for better user experience.
class GameDrawer extends StatefulWidget {
  /// Callback function when new game is requested
  final QuoridorGame game;
  final Function(String)? onMessage;

  /// Creates a new instance of [GameDrawer].
  const GameDrawer({super.key, required this.game, this.onMessage});

  @override
  State<GameDrawer> createState() => _GameDrawerState();
}

class _GameDrawerState extends State<GameDrawer> {
  bool _showValidMoves = true;
  AIDifficulty _currentDifficulty = AIDifficulty.medium;

  void closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  void _newGame() {
    widget.game.newGame();
    closeMenu();
  }

  void _toggleValidMoves() {
    setState(() {
      _showValidMoves = !_showValidMoves;
    });
    widget.game.showValidMoves(_showValidMoves);
    widget.onMessage?.call(
      _showValidMoves ? 'Valid moves highlighted' : 'Valid moves hidden',
    );
    closeMenu();
  }

  void _changeDifficulty(AIDifficulty difficulty) {
    setState(() {
      _currentDifficulty = difficulty;
    });
    widget.game.setDifficulty(difficulty);
    widget.onMessage?.call('AI difficulty set to ${difficulty.name}');
  }

  void _togglePlayerMode() {
    widget.game.togglePlayerMode();
    closeMenu();
  }

  Future<void> _saveGame() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      widget.onMessage?.call('Please log in to save the game');

      closeMenu();
      return;
    }

    final gameId = await FirebaseService.saveGame(widget.game.gameState);
    if (gameId != null) {
      widget.onMessage?.call('Game saved successfully with ID: $gameId');
    } else {
      widget.onMessage?.call('Failed to save game. Please try again.');
    }
    closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
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
                        _newGame,
                      ),
                      _buildMenuItem(
                        context,
                        Icons.save,
                        'Save Game',
                        'Save current progress',
                        _saveGame,
                      ),
                      _buildMenuItem(
                        context,
                        Icons.people,
                        'Toggle Player Mode',
                        widget.game.gameState.currentPlayer.isAI
                            ? 'Switch to 2 players'
                            : 'Switch to AI',
                        _togglePlayerMode,
                      ),
                      _buildDifficultyItem(_currentDifficulty),
                    ]),

                    const SizedBox(height: 24),

                    _buildMenuSection(context, 'Display Options', [
                      _buildSwitchItem(
                        context,
                        Icons.visibility,
                        'Show Valid Moves',
                        'Highlight possible moves',
                        _showValidMoves,
                        _toggleValidMoves,
                      ),
                      _buildSwitchItem(
                        context,
                        Icons.dark_mode,
                        'Dark Mode',
                        'Toggle dark mode',
                        isDarkModeNotifier.value,
                        () {
                          isDarkModeNotifier.value = !isDarkModeNotifier.value;
                          widget.onMessage?.call(
                            isDarkModeNotifier.value
                                ? 'Dark mode enabled'
                                : 'Dark mode disabled',
                          );
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            AppCopyWrite(),
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
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
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
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
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
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
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
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
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

  Widget _buildModeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyItem(AIDifficulty difficulty) {
    final isSelected = _currentDifficulty == difficulty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        onTap: () => _changeDifficulty(difficulty),
        leading: Icon(
          _getDifficultyIcon(difficulty),
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        title: Text(
          difficulty.name.toUpperCase(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          _getDifficultyDescription(difficulty),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
      ),
    );
  }

  IconData _getDifficultyIcon(AIDifficulty difficulty) {
    switch (difficulty) {
      case AIDifficulty.easy:
        return Icons.sentiment_satisfied;
      case AIDifficulty.medium:
        return Icons.sentiment_neutral;
      case AIDifficulty.hard:
        return Icons.sentiment_very_dissatisfied;
    }
  }

  String _getDifficultyDescription(AIDifficulty difficulty) {
    switch (difficulty) {
      case AIDifficulty.easy:
        return 'Beginner-friendly AI';
      case AIDifficulty.medium:
        return 'Balanced challenge';
      case AIDifficulty.hard:
        return 'Expert-level AI';
    }
  }
}
