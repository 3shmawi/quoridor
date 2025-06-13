import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/flame/widgets/game/game_celebrate.dart';
import 'package:quoridor/flame/widgets/game/game_message_toast.dart';
import 'package:quoridor/flame/widgets/game/game_small_screen.dart';
import 'package:quoridor/flame/widgets/game/game_wide_screen.dart';

import '/flame/components/board_component.dart';
import '/flame/constants.dart';
import '/flame/widgets/game/game_drawer.dart';
import '/flame/widgets/game/game_mode_selection.dart';
import '../../flame/game/quoridor_game.dart';
import '../../flame/models/game_state.dart';
import '../../flame/services/firebase_service.dart';
import '../widgets/game/game_app_bar.dart';

class GamePage extends StatefulWidget {
  final GameState? initialGameState;

  const GamePage({super.key, this.initialGameState});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  late QuoridorGame _game;
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
    _game = QuoridorGame();

    if (widget.initialGameState != null) {
      _game.updateGameState(widget.initialGameState!);
    }

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

  void _showGameModeSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          GameModeSelection(game: _game, onMessage: _showGameMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: isWideScreen
              ? null
              : AppBar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  automaticallyImplyLeading: false,
                  title: GameAppBar(),
                ),
          drawer: GameDrawer(game: _game, onMessage: _showGameMessage),
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
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: isWideScreen
                    ? GameWideScreen(_game, key: const ValueKey('wide'))
                    : GameSmallScreen(_game, key: const ValueKey('small')),
              ),
            ),
          ),
          bottomSheet: _showMessage
              ? GameMessageToast(message: _currentMessage)
              : null,
        );
      },
    );
  }
}
