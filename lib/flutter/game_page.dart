import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../services/ai_service.dart';
import '../services/firebase_service.dart';
import '../services/game_service.dart';
import '../theme.dart';
import '../widgets/quoridor_board.dart';

class GamePage extends StatefulWidget {
  final GameState? initialGameState;

  const GamePage({super.key, this.initialGameState});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  late GameState _gameState;
  late AnimationController _messageController;
  late AnimationController _menuController;

  String _currentMessage = '';
  bool _showMessage = false;
  bool _isMenuOpen = false;
  bool _showValidMoves = true;
  AIDifficulty _currentDifficulty = AIDifficulty.medium;
  bool _isProcessingMove = false;

  @override
  void initState() {
    super.initState();

    _messageController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _menuController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _initializeGame();
  }

  void _initializeGame() {
    _gameState = widget.initialGameState ?? GameStateFactory.createNewGame();
    _updateGameState(_gameState);
  }

  void _updateGameState(GameState newState) {
    setState(() {
      _gameState = newState;
    });

    // Save to Firebase
    FirebaseService.saveGame(_gameState);

    // Check for game end
    if (_gameState.gameStatus != GameStatus.playing) {
      final winner = _gameState.gameStatus == GameStatus.player1Won
          ? 'Player 1'
          : 'Player 2';
      _showGameMessage('🎉 $winner wins!');
      HapticFeedback.heavyImpact();
      return;
    }

    // Handle AI turn
    if (_gameState.currentPlayer.isAI && !_isProcessingMove) {
      _handleAITurn();
    }
  }

  Future<void> _handleAITurn() async {
    setState(() {
      _isProcessingMove = true;
    });

    _showGameMessage('AI is thinking...');

    try {
      final aiMove = await AIService.getMove(_gameState, _currentDifficulty);

      if (aiMove != null) {
        final newState = GameService.processMove(_gameState, aiMove);
        if (newState != null) {
          await Future.delayed(
            const Duration(milliseconds: 500),
          ); // Add some delay for better UX
          _updateGameState(newState);
        } else {
          _showGameMessage('AI made an invalid move');
        }
      } else {
        _showGameMessage('AI couldn\'t find a move');
      }
    } catch (e) {
      _showGameMessage('AI error: ${e.toString()}');
    } finally {
      setState(() {
        _isProcessingMove = false;
      });
    }
  }

  void _handleMoveAttempted(Position position) {
    if (_isProcessingMove) return;

    final move = GameMove.pawn(position);
    final newState = GameService.processMove(_gameState, move);

    if (newState != null) {
      _updateGameState(newState);
      HapticFeedback.lightImpact();
    } else {
      _showGameMessage('Invalid move!');
      HapticFeedback.heavyImpact();
    }
  }

  void _handleWallPlaceAttempted(Wall wall) {
    if (_isProcessingMove) return;

    final move = GameMove.wallMove(wall);
    final newState = GameService.processMove(_gameState, move);

    if (newState != null) {
      _updateGameState(newState);
      HapticFeedback.mediumImpact();
    } else {
      _showGameMessage('Invalid wall placement!');
      HapticFeedback.heavyImpact();
    }
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

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });

    if (_isMenuOpen) {
      _menuController.forward();
    } else {
      _menuController.reverse();
    }
  }

  void _newGame() {
    setState(() {
      _gameState = GameStateFactory.createNewGame();
      _isProcessingMove = false;
    });
    _toggleMenu();
    _showGameMessage('New game started!');
  }

  void _togglePlayerMode() {
    setState(() {
      _gameState = _gameState.copyWith(
        player2: _gameState.player2.copyWith(isAI: !_gameState.player2.isAI),
      );
    });
    _toggleMenu();

    final mode = _gameState.player2.isAI ? 'vs AI' : 'vs Human';
    _showGameMessage('Switched to $mode mode');
  }

  void _changeDifficulty() {
    setState(() {
      switch (_currentDifficulty) {
        case AIDifficulty.easy:
          _currentDifficulty = AIDifficulty.medium;
          break;
        case AIDifficulty.medium:
          _currentDifficulty = AIDifficulty.hard;
          break;
        case AIDifficulty.hard:
          _currentDifficulty = AIDifficulty.easy;
          break;
      }
    });
    _toggleMenu();
    _showGameMessage('Difficulty: ${_currentDifficulty.name.toUpperCase()}');
  }

  void _toggleValidMoves() {
    setState(() {
      _showValidMoves = !_showValidMoves;
    });
    _toggleMenu();

    final status = _showValidMoves ? 'enabled' : 'disabled';
    _showGameMessage('Valid moves $status');
  }

  void _showGameInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quoridor Rules'),
        content: const SingleChildScrollView(
          child: Text(
            '🎯 Objective: Reach the opposite side of the board\n\n'
            '🚶 Movement: Move your pawn one space in any direction (up, down, left, right)\n\n'
            '🧱 Walls: Place walls to block your opponent\'s path. Each player starts with 10 walls\n\n'
            '⚡ Jumping: If blocked by opponent\'s pawn, you can jump over them\n\n'
            '🚫 Rules: Walls cannot completely block a player\'s path to their goal\n\n'
            '💡 Strategy: Balance between advancing your pawn and blocking your opponent!',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
    _toggleMenu();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _menuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Quoridor'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: AnimatedRotation(
              turns: _isMenuOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(Icons.menu),
            ),
            onPressed: _toggleMenu,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main game area
          Column(
            children: [
              // Game status
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildGameStatus(),
              ),

              // Board
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: QuoridorBoard(
                      gameState: _gameState,
                      onMoveAttempted: _handleMoveAttempted,
                      onWallPlaceAttempted: _handleWallPlaceAttempted,
                      showValidMoves: _showValidMoves,
                    ),
                  ),
                ),
              ),

              // Player info
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildPlayerInfo(),
              ),
            ],
          ),

          // Side menu
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            right: _isMenuOpen ? 0 : -280,
            top: 0,
            bottom: 0,
            width: 280,
            child: _buildSideMenu(),
          ),

          // Message overlay
          if (_showMessage)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: AnimatedBuilder(
                animation: _messageController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -20 * (1 - _messageController.value)),
                    child: Opacity(
                      opacity: _messageController.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          _currentMessage,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGameStatus() {
    String statusText;
    Color statusColor;

    switch (_gameState.gameStatus) {
      case GameStatus.playing:
        final currentPlayerName = _gameState.currentPlayer == _gameState.player1
            ? 'Player 1'
            : 'Player 2';
        statusText = _isProcessingMove
            ? 'AI is thinking...'
            : '$currentPlayerName\'s turn';
        statusColor = _gameState.currentPlayer == _gameState.player1
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.secondary;
        break;
      case GameStatus.player1Won:
        statusText = '🎉 Player 1 Wins!';
        statusColor = Theme.of(context).colorScheme.primary;
        break;
      case GameStatus.player2Won:
        statusText = '🎉 Player 2 Wins!';
        statusColor = Theme.of(context).colorScheme.secondary;
        break;
      case GameStatus.draw:
        statusText = '🤝 It\'s a Draw!';
        statusColor = Theme.of(context).colorScheme.tertiary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Text(
        statusText,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: statusColor,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPlayerInfo() {
    return Row(
      children: [
        Expanded(
          child: _buildPlayerCard(
            _gameState.player1,
            'Player 1',
            Theme.of(context).colorScheme.primary,
            _gameState.currentPlayer == _gameState.player1,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildPlayerCard(
            _gameState.player2,
            'Player 2',
            Theme.of(context).colorScheme.secondary,
            _gameState.currentPlayer == _gameState.player2,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerCard(
    Player player,
    String name,
    Color color,
    bool isActive,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(isActive ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(isActive ? 0.5 : 0.3),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Icon(Icons.location_on, color: color, size: 20),
                  Text(
                    '(${player.position.row}, ${player.position.col})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              Column(
                children: [
                  Icon(Icons.grid_view, color: color, size: 20),
                  Text(
                    '${player.wallsRemaining}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          if (player.isAI) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'AI',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSideMenu() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.games,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Game Menu',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildMenuButton(
                    icon: Icons.refresh,
                    title: 'New Game',
                    subtitle: 'Start fresh',
                    onTap: _newGame,
                  ),
                  const SizedBox(height: 12),
                  _buildMenuButton(
                    icon: Icons.people,
                    title: 'Player Mode',
                    subtitle: _gameState.player2.isAI
                        ? 'Currently: vs AI'
                        : 'Currently: vs Human',
                    onTap: _togglePlayerMode,
                  ),
                  if (_gameState.player2.isAI) ...[
                    const SizedBox(height: 12),
                    _buildMenuButton(
                      icon: Icons.psychology,
                      title: 'AI Difficulty',
                      subtitle:
                          'Current: ${_currentDifficulty.name.toUpperCase()}',
                      onTap: _changeDifficulty,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildMenuButton(
                    icon: Icons.visibility,
                    title: 'Valid Moves',
                    subtitle: _showValidMoves
                        ? 'Currently: ON'
                        : 'Currently: OFF',
                    onTap: _toggleValidMoves,
                  ),
                  const SizedBox(height: 12),
                  _buildMenuButton(
                    icon: Icons.info,
                    title: 'Game Rules',
                    subtitle: 'Learn how to play',
                    onTap: _showGameInfo,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
}
