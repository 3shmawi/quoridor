import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/widgets/game/game_celebrate.dart';
import 'package:quoridor/flame/widgets/game/game_message_toast.dart';
import 'package:quoridor/flame/widgets/game/game_small_screen.dart';
import 'package:quoridor/flame/widgets/game/game_wide_screen.dart';

import '/flame/components/board_component.dart';
import '/flame/constants.dart';
import '/flame/controller/game_controller.dart';
import '/flame/controller/game_states.dart';
import '/flame/widgets/game/game_drawer.dart';
import '/flame/widgets/game/game_mode_selection.dart';
import '../../flame/game/quoridor_game.dart';
import '../../flame/models/game_state.dart';
import '../../flame/services/firebase_service.dart';
import '../services/localizations.dart';
import '../widgets/game/game_app_bar.dart';

class GamePage extends StatefulWidget {
  final GameState? initialGameState;
  final QuoridorGame game;

  const GamePage(this.game, {super.key, this.initialGameState});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  late final QuoridorGame _game = widget.game;
  late AnimationController _messageController;
  late ConfettiController _confettiController;
  bool _isInitialized = false;

  String _currentMessage = '';
  bool _showMessage = false;

  @override
  void initState() {
    super.initState();

    _messageController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    // Show game mode selection after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showGameModeSelection();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _initializeGame();
      _isInitialized = true;
    }
  }

  void _initializeGame() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final totalSpacing =
        (GameConstants.boardSize - 1) * GameConstants.cellSpacing;
    final totalPadding = GameConstants.boardPadding * 2;

    // Define breakpoints for different screen sizes
    final isWideScreen = screenWidth > 700;
    final isExtraWideScreen = screenWidth > 1200;

    // Calculate available width based on screen size
    double availableWidth;
    if (isExtraWideScreen) {
      // For extra wide screens, reserve more space for the sidebar
      availableWidth = screenWidth - totalPadding - totalSpacing - 400;
    } else if (isWideScreen) {
      // For wide screens, reserve some space for the sidebar
      availableWidth = screenWidth - totalPadding - totalSpacing - 300;
    } else {
      // For mobile/tablet, use full width minus padding
      availableWidth = screenWidth - totalPadding - totalSpacing;
    }

    // Calculate available height
    // Reserve space for app bar, player info (if not in sidebar), and message toast
    final appBarHeight = 64.0; // Standard app bar height
    final playerInfoHeight = isWideScreen
        ? 0.0
        : 100.0; // Height of player info when at bottom
    final messageToastHeight = 60.0; // Height for message toast
    final bottomPadding = 20.0; // Additional bottom padding
    final availableHeight =
        screenHeight -
        appBarHeight -
        playerInfoHeight -
        messageToastHeight -
        bottomPadding;

    // Calculate cell size based on both width and height
    final widthBasedCellSize = availableWidth / GameConstants.boardSize;
    final heightBasedCellSize = availableHeight / GameConstants.boardSize;

    // Use the smaller of the two to ensure the board fits both dimensions
    final rawCellSize = widthBasedCellSize < heightBasedCellSize
        ? widthBasedCellSize
        : heightBasedCellSize;

    // Apply minimum and maximum constraints
    final minCellSize = 30.0; // Minimum cell size for playability
    final maxCellSize = 60.0; // Maximum cell size for aesthetics
    final cellSize = rawCellSize.clamp(minCellSize, maxCellSize);

    cellSizeNotifier.value = cellSize;

    // Initialize game with controller if initial state is provided
    if (widget.initialGameState != null) {
      context.read<GameController>().add(
        LoadGame(widget.initialGameState!.gameId),
      );
    }

    // Set up game callbacks to work with controller
    _game.onGameStateChanged = _handleGameStateChanged;
    _game.onGameMessage = _showGameMessage;
    _game.onGameWon = _showConfetti;
    isInitializedProvider.value = _game.isInitialized;
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
      _currentMessage = message.getString(context);
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
    final gameController = context.read<GameController>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BlocProvider.value(
        value: gameController,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.emoji_events,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(AppLocale.gameOver.getString(context)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BlocBuilder<GameController, GameStates>(
                builder: (context, state) {
                  String winner = 'Unknown';
                  if (state is GameOverState) {
                    winner = state.winner;
                  } else if (state is GamePlayingState &&
                      state.gameState.isGameOver) {
                    winner = state.gameState.winner ?? 'Unknown';
                  }

                  return Text(
                    '$winner ${AppLocale.wins.getString(context)}!',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                AppLocale.playAgainSuggestion.getString(context),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(AppLocale.notNow.getString(context)),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                gameController.add(StartNewGame());
              },
              icon: const Icon(Icons.refresh),
              label: Text(AppLocale.playAgain.getString(context)),
            ),
          ],
        ),
      ),
    );
  }

  void _showGameModeSelection() {
    final gameController = context.read<GameController>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BlocProvider.value(
        value: gameController,
        child: BlocBuilder<GameController, GameStates>(
          builder: (context, state) {
            return GameModeSelection(
              game: _game,
              onMessage: _showGameMessage,
              gameController: gameController,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GameController, GameStates>(
      listener: (context, state) {
        // Handle state changes and update the game accordingly
        if (state is GamePlayingState) {
          _game.updateFromController();

          // Show messages from controller
          if (state.currentMessage != null) {
            _showGameMessage(state.currentMessage!);
          }
        } else if (state is GameOverState) {
          _game.updateFromController();
          _showConfetti();
        } else if (state is GameErrorState) {
          _showGameMessage(state.error);
        } else if (state is GameAIThinkingState) {
          _game.updateFromController();
          _showGameMessage(state.message);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;
          final totalSpacing =
              (GameConstants.boardSize - 1) * GameConstants.cellSpacing;
          final totalPadding = GameConstants.boardPadding * 2;

          // Define breakpoints for different screen sizes
          final isWideScreen = screenWidth > 700;
          final isExtraWideScreen = screenWidth > 1200;

          // Calculate available width based on screen size
          double availableWidth;
          if (isExtraWideScreen) {
            // For extra wide screens, reserve more space for the sidebar
            availableWidth = screenWidth - totalPadding - totalSpacing - 400;
          } else if (isWideScreen) {
            // For wide screens, reserve some space for the sidebar
            availableWidth = screenWidth - totalPadding - totalSpacing - 300;
          } else {
            // For mobile/tablet, use full width minus padding
            availableWidth = screenWidth - totalPadding - totalSpacing;
          }

          // Calculate available height
          // Reserve space for app bar, player info (if not in sidebar), and message toast
          final appBarHeight = 64.0; // Standard app bar height
          final playerInfoHeight = isWideScreen
              ? 0.0
              : 100.0; // Height of player info when at bottom
          final messageToastHeight = 60.0; // Height for message toast
          final bottomPadding = 20.0; // Additional bottom padding
          final availableHeight =
              screenHeight -
              appBarHeight -
              playerInfoHeight -
              messageToastHeight -
              bottomPadding;

          // Calculate cell size based on both width and height
          final widthBasedCellSize = availableWidth / GameConstants.boardSize;
          final heightBasedCellSize = availableHeight / GameConstants.boardSize;

          // Use the smaller of the two to ensure the board fits both dimensions
          final rawCellSize = widthBasedCellSize < heightBasedCellSize
              ? widthBasedCellSize
              : heightBasedCellSize;

          // Apply minimum and maximum constraints
          final minCellSize = 30.0; // Minimum cell size for playability
          final maxCellSize = 60.0; // Maximum cell size for aesthetics
          final cellSize = rawCellSize.clamp(minCellSize, maxCellSize);

          cellSizeNotifier.value = cellSize;

          return BlocBuilder<GameController, GameStates>(
            builder: (context, state) {
              // Show loading state
              if (state is GameLoadingState) {
                return Scaffold(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(state.message),
                      ],
                    ),
                  ),
                );
              }

              // Show error state
              if (state is GameErrorState) {
                return Scaffold(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.error,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        if (state.suggestion != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            state.suggestion!,
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            context.read<GameController>().add(StartNewGame());
                          },
                          child: const Text('Start New Game'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Show paused state
              if (state is GamePausedState) {
                return Scaffold(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.pause_circle_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.reason,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            context.read<GameController>().add(ResumeGame());
                          },
                          child: const Text('Resume Game'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Show main game interface
              return Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                appBar: isWideScreen
                    ? null
                    : AppBar(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        automaticallyImplyLeading: false,
                        title: GameAppBar(),
                      ),
                drawer: GameDrawer(
                  game: _game,
                  onMessage: _showGameMessage,
                  gameController: context.read<GameController>(),
                ),
                body: SafeArea(
                  minimum: isWideScreen
                      ? const EdgeInsets.all(GameConstants.boardPadding)
                      : EdgeInsets.zero,
                  child: GameCelebrate(
                    confettiController: _confettiController,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                      child: isWideScreen
                          ? GameWideScreen(
                              _game,
                              key: const ValueKey('wide'),
                              gameController: context.read<GameController>(),
                            )
                          : GameSmallScreen(
                              _game,
                              key: const ValueKey('small'),
                              gameController: context.read<GameController>(),
                            ),
                    ),
                  ),
                ),
                bottomSheet: _showMessage
                    ? GameMessageToast(message: _currentMessage)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
