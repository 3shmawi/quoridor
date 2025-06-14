import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/core/dimensions.dart';
import 'package:quoridor/flame/widgets/game/game_celebrate.dart';
import 'package:quoridor/flame/widgets/game/game_message_toast.dart';
import 'package:quoridor/flame/widgets/game/game_small_screen.dart';
import 'package:quoridor/flame/widgets/game/game_wide_screen.dart';

import '/flame/components/board_component.dart';
import '/flame/widgets/game/game_drawer.dart';
import '/flame/widgets/game/game_mode_selection.dart';
import '../../flame/game/quoridor_game.dart';
import '../../flame/models/game_state.dart';
import '../../flame/services/firebase_service.dart';
import '../core/constants.dart';
import '../services/localizations.dart';
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
    final cellSize = GameBoardDimensions(
      screenHeight: screenHeight,
      screenWidth: screenWidth,
    ).calculateCellSize();
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
            Text(AppLocale.gameOver.getString(context)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_game.gameState.winner} ${AppLocale.wins.getString(context)}!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
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
              _game.newGame();
            },
            icon: const Icon(Icons.refresh),
            label: Text(AppLocale.playAgain.getString(context)),
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
      isDismissible: false,
      useRootNavigator: false,
      enableDrag: false,
      requestFocus: true,
      showDragHandle: false,

      builder: (context) => PopScope(
        canPop: false, // Prevents back button
        child: GameModeSelection(game: _game, onMessage: _showGameMessage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final dimensions = GameBoardDimensions(
          screenHeight: screenHeight,
          screenWidth: screenWidth,
        );
        final isWideScreen = dimensions.isWideScreen;
        final cellSize = dimensions.calculateCellSize();

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
