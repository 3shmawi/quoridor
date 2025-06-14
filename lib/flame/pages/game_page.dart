import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/widgets/game/game_celebrate.dart';
import 'package:quoridor/flame/widgets/game/game_message_toast.dart';
import 'package:quoridor/flame/widgets/offline_game_widget.dart';

import '/flame/components/board_component.dart';
import '/flame/constants.dart';
import '/flame/widgets/game/game_drawer.dart';
import '/flame/widgets/game/game_mode_selection.dart';
import '../../flame/game/quoridor_game.dart';
import '../../flame/models/game_state.dart';
import '../../flame/services/firebase_service.dart';
import '../services/localizations.dart';

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
    // Calculate cell size based on screen size
    final screenSize = MediaQuery.of(context).size;
    final rawCellSize = (screenSize.width - 32) / GameConstants.boardSize;

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

  void _showGameModeSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          GameModeSelection(game: _game, onMessage: _showGameMessage),
    );
  }

  void _showReplayDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocale.gameOver.getString(context)),
        content: Text(AppLocale.playAgainSuggestion.getString(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocale.notNow.getString(context)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _game.newGame();
            },
            child: Text(AppLocale.playAgain.getString(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: GameDrawer(game: _game, onMessage: _showGameMessage),
      body: GameCelebrate(
        confettiController: _confettiController,
        child: Stack(
          children: [
            const OfflineGameWidget(),
            if (_showMessage) GameMessageToast(message: _currentMessage),
          ],
        ),
      ),
    );
  }
}
