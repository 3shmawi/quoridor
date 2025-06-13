import 'dart:math' show pi;

import 'package:confetti/confetti.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../constants.dart';
import '../game/quoridor_game.dart';
import '../models/game_state.dart';
import '../services/firebase_service.dart';
import '../widgets/game/game_app_bar.dart';
import '../widgets/game/game_drawer.dart';
import '../widgets/game/game_info_dialog.dart';
import '../widgets/game/game_message_toast.dart';
import '../widgets/game/game_mode_selection.dart';
import '../widgets/game/player_info_widget.dart';
import '../widgets/game/wall_controls.dart';

/// The main game page that hosts the Quoridor game.
///
/// This page manages the game state, UI components, and user interactions.
/// It provides a complete game interface with controls, menus, and game board.
class GamePage extends StatefulWidget {
  /// The initial game state to load, if any
  final GameState? initialGameState;

  /// Creates a new instance of [GamePage].
  const GamePage({super.key, this.initialGameState});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  late AnimationController _messageController;
  late ConfettiController _confettiController;
  WallOrientation _selectedWallOrientation = WallOrientation.horizontal;
  bool _showValidMoves = true;

  String _currentMessage = '';
  bool _showMessage = false;
  Position? _wallPreviewPosition;
  late QuoridorGame _game;

  @override
  void initState() {
    _initializeGame();
    super.initState();
    _messageController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showGameModeSelection(context);
    });
  }

  void _initializeGame() {
    _game = QuoridorGame();

    if (widget.initialGameState != null) {
      _game.updateGameState(widget.initialGameState!);
    }

    _game.onGameStateChanged = _handleGameStateChanged;
    _game.onGameMessage = _showGameMessage;
    _game.onGameWon = _showConfetti;
    isInitializedProvider.value = _game.isInitialized;
  }

  void closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _handleGameStateChanged(GameState gameState) {
    // Auto-save game state to Firebase
    if (FirebaseService.currentUser != null) {
      FirebaseService.updateGame(gameState);
    }

    isInitializedProvider.value = true;
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

  void _showConfetti() {
    _confettiController.play();
    // Show replay dialog after confetti animation
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _showReplayDialog();
      }
    });
  }

  void _showReplayDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.emoji_events,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text('Game Over!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_game.gameState.winner} wins!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Would you like to play again?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _game.newGame();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveGame(BuildContext context) async {
    if (!_game.isInitialized) return;
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

  void _showGameInfo(BuildContext context) {
    showDialog(context: context, builder: (context) => const GameInfoDialog());
  }

  void _showGameModeSelection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) => GameModeSelection(
        onAIModeSelected: () {
          if (!_game.gameState.player2.isAI) {
            _game.togglePlayerMode();
          } else {
            _game.updateGameState(_game.gameState);
          }
          Navigator.pop(context);
          _showGameMessage('Playing against AI');
        },
        onTwoPlayerModeSelected: () {
          if (_game.gameState.player2.isAI) {
            _game.togglePlayerMode();
          } else {
            _game.updateGameState(_game.gameState);
          }
          Navigator.pop(context);
          _showGameMessage('Two player mode activated');
        },
      ),
    );
  }

  void _moveWallPreview(BuildContext context, Position? newPosition) {
    if (newPosition == null) return;
    setState(() {
      _wallPreviewPosition = newPosition;
    });

    if (_wallPreviewPosition != null) {
      final wall = Wall(_wallPreviewPosition!, _selectedWallOrientation);
      _game.boardComponent.previewWall = wall;
    }
  }

  void _confirmWallPlacement(BuildContext context) {
    if (_wallPreviewPosition == null) return;

    final wall = Wall(_wallPreviewPosition!, _selectedWallOrientation);
    _game.boardComponent.onWallPlaceAttempted?.call(wall);
    setState(() {
      _wallPreviewPosition = null;
    });
    _game.boardComponent.previewWall = null;
  }

  void _handleWallMovement(BuildContext context, String direction) {
    if (_wallPreviewPosition == null) {
      _wallPreviewPosition = Position(4, 4);
      _moveWallPreview(context, _wallPreviewPosition);
      return;
    }
    Position? newPosition;
    switch (direction) {
      case 'up':
        if (_wallPreviewPosition!.row > 0) {
          newPosition = Position(
            _wallPreviewPosition!.row - 1,
            _wallPreviewPosition!.col,
          );
        }
        break;
      case 'down':
        if (_wallPreviewPosition!.row < GameConstants.boardSize - 1) {
          newPosition = Position(
            _wallPreviewPosition!.row + 1,
            _wallPreviewPosition!.col,
          );
        }
        break;
      case 'left':
        if (_wallPreviewPosition!.col > 0) {
          newPosition = Position(
            _wallPreviewPosition!.row,
            _wallPreviewPosition!.col - 1,
          );
        }
        break;
      case 'right':
        if (_wallPreviewPosition!.col < GameConstants.boardSize - 1) {
          newPosition = Position(
            _wallPreviewPosition!.row,
            _wallPreviewPosition!.col + 1,
          );
        }
        break;
    }
    if (newPosition != null) {
      _moveWallPreview(context, newPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: GameAppBar(onGameInfoPressed: () => _showGameInfo(context)),
      drawer: _game.isInitialized
          ? GameDrawer(
              onNewGame: _game.newGame,
              onSaveGame: () => _saveGame(context),
              onTogglePlayerMode: _game.togglePlayerMode,
              onToggleValidMoves: () {
                setState(() {
                  _showValidMoves = !_showValidMoves;
                });
                _game.showValidMoves(_showValidMoves);
                _showGameMessage(
                  _showValidMoves ? 'Valid moves shown' : 'Valid moves hidden',
                );
                closeMenu();
              },
              onToggleDarkMode: () =>
                  isDarkModeNotifier.value = !isDarkModeNotifier.value,
              showValidMoves: _showValidMoves,
              isDarkMode: isDarkModeNotifier.value,
              isPlayer2AI: _game.gameState.player2.isAI,
            )
          : null,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Expanded(
                  child: GameWidget<QuoridorGame>.controlled(
                    gameFactory: () => _game,
                  ),
                ),
                if (_game.isInitialized)
                  Column(
                    children: [
                      if (_game.gameState.currentPlayer.hasWallsRemaining)
                        WallControls(
                          orientation: _selectedWallOrientation,
                          onOrientationChanged: (orientation) {
                            setState(() {
                              _selectedWallOrientation = orientation;
                            });
                            _game.setWallOrientation(orientation);
                            if (_wallPreviewPosition != null) {
                              _moveWallPreview(context, _wallPreviewPosition);
                            }
                          },
                          onWallMovement: (dir) =>
                              _handleWallMovement(context, dir),
                          onWallPlacementConfirmed: () =>
                              _confirmWallPlacement(context),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: PlayerInfoWidget(
                              playerId: 1,
                              name: 'Player 1',
                              wallsRemaining:
                                  _game.gameState.player1.wallsRemaining,
                              isCurrentPlayer:
                                  _game.gameState.currentPlayer.id == 1,
                              isAI: false,
                            ),
                          ),
                          Expanded(
                            child: PlayerInfoWidget(
                              playerId: 2,
                              name: 'Player 2',
                              wallsRemaining:
                                  _game.gameState.player2.wallsRemaining,
                              isCurrentPlayer:
                                  _game.gameState.currentPlayer.id == 2,
                              isAI: _game.gameState.player2.isAI,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                if (_showMessage)
                  AnimatedBuilder(
                    animation: _messageController,
                    builder: (context, child) {
                      return GameMessageToast(
                        message: _currentMessage,
                        opacity: _messageController.value,
                      );
                    },
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi / 2,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
                Colors.yellow,
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: -pi / 4,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
                Colors.yellow,
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: -3 * pi / 4,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
                Colors.yellow,
              ],
            ),
          ),
          // if (_isAIThinking)
          //   Container(
          //     color: Colors.black.withValues(alpha: 0.3),
          //     child: const Center(child: CircularProgressIndicator()),
          //   ),
        ],
      ),
    );
  }
}
