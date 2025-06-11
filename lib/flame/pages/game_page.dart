import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../flame/game/quoridor_game.dart';
import '../../flame/models/game_state.dart';
import '../../flame/services/ai_service.dart';
import '../../flame/services/firebase_service.dart';

class GamePage extends StatefulWidget {
  final GameState? initialGameState;

  const GamePage({super.key, this.initialGameState});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  late QuoridorGame _game;
  late AnimationController _messageController;

  String _currentMessage = '';
  bool _showMessage = false;
  bool _showValidMoves = true;
  AIDifficulty _currentDifficulty = AIDifficulty.medium;

  @override
  void initState() {
    _initializeGame();
    super.initState();

    _messageController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  void _initializeGame() {
    _game = QuoridorGame();

    if (widget.initialGameState != null) {
      _game.updateGameState(widget.initialGameState!);
    }

    _game.onGameStateChanged = _handleGameStateChanged;
    _game.onGameMessage = _showGameMessage;
  }

  void closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _handleGameStateChanged(GameState gameState) {
    // Auto-save game state to Firebase
    if (FirebaseService.currentUser != null) {
      FirebaseService.updateGame(gameState);
    }

    setState(() {});
  }

  void _showGameMessage(String message) {
    setState(() {
      _currentMessage = message;
      _showMessage = true;
    });

    _messageController.forward().then((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _messageController.reverse().then((_) {
            setState(() {
              _showMessage = false;
            });
          });
        }
      });
    });
  }

  void _newGame() {
    _game.newGame();
    _showGameMessage('New game started!');
    closeMenu();
  }

  void _toggleValidMoves() {
    setState(() {
      _showValidMoves = !_showValidMoves;
    });
    _game.showValidMoves(_showValidMoves);
    _showGameMessage(
      _showValidMoves ? 'Valid moves shown' : 'Valid moves hidden',
    );
    closeMenu();
  }

  void _changeDifficulty(AIDifficulty difficulty) {
    setState(() {
      _currentDifficulty = difficulty;
    });
    _game.setDifficulty(difficulty);
    _showGameMessage('Difficulty: ${difficulty.name}');
  }

  void _togglePlayerMode() {
    _game.togglePlayerMode();
    closeMenu();
  }

  Future<void> _saveGame() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      _showGameMessage('Please sign in to save game');
      closeMenu();
      return;
    }

    final gameId = await FirebaseService.saveGame(_game.gameState);
    if (gameId != null) {
      _showGameMessage('Game saved successfully!');
    } else {
      _showGameMessage('Failed to save game');
    }
    closeMenu();
  }

  void _showGameInfo() {
    showDialog(context: context, builder: (context) => _buildGameInfoDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      drawer: Drawer(
        width: 350,
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
                  image: DecorationImage(
                    image: AssetImage('assets/icons/logo.png'),
                    fit: BoxFit.cover,
                  ),
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: SizedBox(
                  height: double.infinity,
                  width: double.infinity,
                ),
              ),

              // Menu Items
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (context) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMenuSection('Game Controls', [
                            _buildMenuItem(
                              Icons.refresh,
                              'New Game',
                              'Start a fresh game',
                              _newGame,
                            ),
                            _buildMenuItem(
                              Icons.save,
                              'Save Game',
                              'Save current progress',
                              _saveGame,
                            ),
                            if (_game.isInitialized)
                              _buildMenuItem(
                                Icons.people,
                                'Toggle Player Mode',
                                _game.gameState.player2.isAI
                                    ? 'Switch to 2 players'
                                    : 'Switch to AI',
                                _togglePlayerMode,
                              ),
                          ]),

                          const SizedBox(height: 24),

                          _buildMenuSection('Display Options', [
                            _buildSwitchItem(
                              Icons.visibility,
                              'Show Valid Moves',
                              'Highlight possible moves',
                              _showValidMoves,
                              _toggleValidMoves,
                            ),
                          ]),

                          const SizedBox(height: 24),

                          _buildMenuSection('AI Difficulty', [
                            _buildDifficultyItem(AIDifficulty.easy),
                            _buildDifficultyItem(AIDifficulty.medium),
                            _buildDifficultyItem(AIDifficulty.hard),
                          ]),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Text.rich(
                textDirection: TextDirection.ltr,
                TextSpan(
                  children: [
                    TextSpan(
                      text: "@copyWrite",
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    TextSpan(text: " "),
                    TextSpan(
                      text: "MO",
                      style: TextStyle(color: Colors.cyan),
                    ),
                    TextSpan(
                      text: "RE",
                      style: TextStyle(color: Theme.of(context).dividerColor),
                    ),
                    TextSpan(
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
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildTopActionBar(),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Game Board
                  Positioned.fill(
                    child: GameWidget<QuoridorGame>.controlled(
                      gameFactory: () => _game,
                    ),
                  ),

                  // Message Toast
                  if (_showMessage)
                    AnimatedBuilder(
                      animation: _messageController,
                      builder: (context, child) {
                        return Positioned(
                          bottom: 20,
                          left: 20,
                          right: 20,
                          child: Opacity(
                            opacity: _messageController.value,
                            child: _buildMessageToast(),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
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
              'Quoridor',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Game Info Button
          IconButton(
            onPressed: _showGameInfo,
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

  Widget _buildMenuSection(String title, List<Widget> children) {
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

  Widget _buildDifficultyItem(AIDifficulty difficulty) {
    final isSelected = _currentDifficulty == difficulty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: ListTile(
        onTap: () => _changeDifficulty(difficulty),
        leading: Icon(
          _getDifficultyIcon(difficulty),
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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

  Widget _buildMessageToast() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.info,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
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
