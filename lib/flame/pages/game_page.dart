import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'dart:async';
import 'dart:math' show pi;

import '../../flame/board_component.dart';
import '../../flame/game/quoridor_game.dart';
import '../../flame/services/audio_service.dart';
import '../../flame/services/online/online_game_controller.dart';
import 'online_lobby_page.dart';
import '../../flame/models/game_state.dart';
import '../../flame/services/ai_service.dart';
import '../../flame/services/firebase_service.dart';
import '../../theme.dart';

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

  String _currentMessage = '';
  bool _showMessage = false;
  bool _showValidMoves = true;
  AIDifficulty _currentDifficulty = AIDifficulty.medium;

  /// Non-null while an online game is in progress.
  OnlineGameController? _online;

  bool get _isOnline => _online != null;

  @override
  void initState() {
    _initializeGame();
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

  void _initializeGame() {
    _game = QuoridorGame();

    if (widget.initialGameState != null) {
      _game.updateGameState(widget.initialGameState!);
    }

    _game.onGameStateChanged = _handleGameStateChanged;
    _game.onGameMessage = _showGameMessage;
    _game.onGameWon = _showConfetti;
    _game.onInteractionChanged = () {
      if (mounted) setState(() {});
    };
    isInitializedProvider.value = _game.isInitialized;
  }

  void closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _detachOnline(abandon: false);
    _messageController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // --- Online play ---------------------------------------------------------

  /// Opens the lobby and, if the player starts or joins a game, hands the
  /// board over to it.
  Future<void> _startOnlineGame() async {
    closeMenu();

    final controller = await Navigator.of(context).push<OnlineGameController>(
      MaterialPageRoute(builder: (_) => const OnlineLobbyPage()),
    );

    if (controller == null || !mounted) {
      controller?.dispose();
      return;
    }

    _detachOnline(abandon: true);
    _online = controller;

    // The server's board is the one being rendered from here on.
    _game.localPlayerId = controller.localPlayerId;
    _game.onSubmitMove = controller.submitMove;
    controller.onRemoteUpdate = _game.updateGameState;
    controller.onGameOver = _handleOnlineGameOver;
    controller.addListener(_handleOnlineChanged);

    final board = controller.game?.board;
    if (board != null) _game.updateGameState(board);

    setState(() {});
    _showGameMessage(
      controller.connection == OnlineConnectionState.waitingForOpponent
          ? 'Share code ${controller.roomCode} to invite a friend'
          : 'Connected — good luck',
    );
  }

  void _handleOnlineChanged() {
    if (!mounted) return;

    final message = _online?.message;
    if (message != null) {
      _showGameMessage(message);
      _online?.consumeMessage();
    }
    setState(() {});
  }

  void _handleOnlineGameOver(bool didWin) {
    if (!mounted) return;
    if (didWin) _showConfetti();
    _showGameMessage(didWin ? 'You win!' : 'Your opponent wins');
  }

  /// Tears down any online session and returns the board to local play.
  void _detachOnline({required bool abandon}) {
    final controller = _online;
    if (controller == null) return;

    _online = null;
    controller.removeListener(_handleOnlineChanged);
    unawaited(controller.leave(abandon: abandon));
    controller.dispose();

    _game.localPlayerId = null;
    _game.onSubmitMove = null;
  }

  Future<void> _leaveOnlineGame() async {
    closeMenu();
    _detachOnline(abandon: true);
    _game.newGame();
    setState(() {});
    _showGameMessage('Left the online game');
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
              _newGame();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  void _newGame() {
    if (_isOnline) {
      _showGameMessage('Leave the online game first');
      closeMenu();
      return;
    }
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

  void _toggleSound() {
    final audio = AudioService.instance;
    setState(() {
      audio.enabled.value = !audio.enabled.value;
    });
    if (!audio.enabled.value) {
      // Silence anything mid-playback so the toggle takes effect immediately.
      unawaited(audio.stopAll());
    }
    _showGameMessage(audio.enabled.value ? 'Sound on' : 'Sound off');
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

  void _showGameModeSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // Title
            Text(
              'Choose Game Mode',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            // Mode selection cards
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shrinkWrap: true,
                children: [
                  _buildModeCard(
                    icon: Icons.computer,
                    title: 'Play vs AI',
                    subtitle: 'Challenge our intelligent AI opponent',
                    onTap: () {
                      if (!_game.gameState.player2.isAI) {
                        _game.togglePlayerMode();
                      } else {
                        _game.updateGameState(_game.gameState);
                      }
                      Navigator.pop(context);
                      _showGameMessage('Playing against AI');
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModeCard(
                    icon: Icons.public,
                    title: 'Play Online',
                    subtitle: 'Invite a friend with a code, or join theirs',
                    onTap: () {
                      Navigator.pop(context);
                      _startOnlineGame();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModeCard(
                    icon: Icons.people,
                    title: 'Two Players',
                    subtitle: 'Play with a friend on the same device',
                    onTap: () {
                      if (_game.gameState.player2.isAI) {
                        _game.togglePlayerMode();
                      } else {
                        _game.updateGameState(_game.gameState);
                      }
                      Navigator.pop(context);
                      _showGameMessage('Two player mode activated');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        automaticallyImplyLeading: false,
        title: _buildTopActionBar(),
      ),
      drawer: Drawer(
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
                            if (_isOnline)
                              _buildMenuItem(
                                Icons.logout_rounded,
                                'Leave Online Game',
                                'Return to playing on this device',
                                _leaveOnlineGame,
                              )
                            else
                              _buildMenuItem(
                                Icons.public,
                                'Play Online',
                                'Invite a friend with a code',
                                _startOnlineGame,
                              ),
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
                            _buildSwitchItem(
                              Icons.dark_mode,
                              'Dark Mode',
                              'Toggle dark mode',
                              isDarkModeNotifier.value,
                              () => isDarkModeNotifier.value =
                                  !isDarkModeNotifier.value,
                            ),
                            _buildSwitchItem(
                              AudioService.instance.enabled.value
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              'Sound Effects',
                              AudioService.instance.isUnavailable
                                  ? 'Unavailable on this device'
                                  : 'Move and wall sounds',
                              AudioService.instance.enabled.value,
                              _toggleSound,
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
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              spacing: 20,
              children: [
                Expanded(
                  child: GameWidget<QuoridorGame>.controlled(
                    gameFactory: () => _game,
                  ),
                ),
                if (_isOnline) _buildOnlineBanner(),
                ValueListenableBuilder(
                  valueListenable: isInitializedProvider,
                  builder: (context, value, child) {
                    if (!value) return const SizedBox.shrink();
                    return _buildTurnControls();
                  },
                ),
                if (_showMessage)
                  AnimatedBuilder(
                    animation: _messageController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _messageController.value,
                        child: _buildMessageToast(),
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
          // Bottom Right Confetti
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
          // Bottom Left Confetti
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
        ],
      ),
    );
  }

  Widget _buildTopActionBar() {
    return Row(
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
                ).colorScheme.primary.withValues(alpha: 0.1),
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
          onPressed: _showGameInfo,
          icon: Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.secondary.withValues(alpha: 0.1),
            foregroundColor: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
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

  // --- Online banner -------------------------------------------------------

  /// A single strip that says what the online game is doing right now.
  ///
  /// The states it distinguishes are the ones a player can act on: waiting for
  /// someone to join (so show the code to share), the opponent having gone
  /// quiet, having lost contact ourselves, or simply whose turn it is.
  Widget _buildOnlineBanner() {
    final online = _online;
    if (online == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    late final Color color;
    late final IconData icon;
    late final String text;
    Widget? action;

    switch (online.connection) {
      case OnlineConnectionState.connecting:
        color = scheme.onSurface.withValues(alpha: 0.7);
        icon = Icons.sync_rounded;
        text = 'Connecting…';

      case OnlineConnectionState.waitingForOpponent:
        color = const Color(0xFFD97706);
        icon = Icons.hourglass_top_rounded;
        text = 'Waiting for an opponent — code ${online.roomCode}';
        action = TextButton.icon(
          onPressed: () => _copyRoomCode(online.roomCode),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy'),
        );

      case OnlineConnectionState.opponentAway:
        color = const Color(0xFFD97706);
        icon = Icons.cloud_off_rounded;
        text =
            '${online.session?.opponent?.displayName ?? 'Opponent'} '
            'has gone quiet';

      case OnlineConnectionState.offline:
        color = const Color(0xFFDC2626);
        icon = Icons.wifi_off_rounded;
        text = 'Lost contact with the game';

      case OnlineConnectionState.ended:
        color = scheme.onSurface.withValues(alpha: 0.7);
        icon = Icons.flag_rounded;
        text = 'Game over';

      case OnlineConnectionState.live:
        final yourTurn = online.isLocalTurn;
        color = yourTurn ? const Color(0xFF16A34A) : scheme.primary;
        icon = yourTurn
            ? Icons.play_circle_outline_rounded
            : Icons.more_horiz_rounded;
        text = yourTurn
            ? 'Your turn'
            : '${online.session?.opponent?.displayName ?? 'Opponent'} '
                  'is thinking…';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Future<void> _copyRoomCode(String? code) async {
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _showGameMessage('Code $code copied');
  }

  // --- Turn controls -------------------------------------------------------

  /// The strip under the board: who is playing, and what a tap will do.
  ///
  /// Walls used to be placed by tapping an invisible strip near a cell edge,
  /// which most players never discovered. The board now has two explicit
  /// modes, and wall placement is a visible, reversible three-step action:
  /// pick a slot, rotate if needed, then confirm.
  Widget _buildTurnControls() {
    final state = _game.gameState;
    final online = _online;

    // Online, the opponent's turn is active but not ours, so the controls
    // must be disabled even though the game is perfectly playable.
    final isAITurn = online != null
        ? !online.isLocalTurn
        : state.currentPlayer.isAI && !state.isGameOver;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPlayerStrip(),
        const SizedBox(height: 12),
        _buildModeSelector(enabled: !isAITurn && !state.isGameOver),
        if (_game.boardMode == BoardInteractionMode.wall && !isAITurn) ...[
          const SizedBox(height: 12),
          _buildWallControls(),
        ],
      ],
    );
  }

  Widget _buildPlayerStrip() {
    final state = _game.gameState;
    return Row(
      children: [
        Expanded(
          child: _buildPlayerChip(
            label: 'You',
            color: const Color(0xFF6F61EF),
            walls: state.player1.wallsRemaining,
            isActive: state.currentPlayerId == 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPlayerChip(
            label: state.player2.isAI ? 'AI' : 'Player 2',
            color: const Color(0xFF39D2C0),
            walls: state.player2.wallsRemaining,
            isActive: state.currentPlayerId == 2,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerChip({
    required String label,
    required Color color,
    required int walls,
    required bool isActive,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isActive ? 0.9 : 0.25),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  '$walls walls left',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (isActive) Icon(Icons.play_arrow_rounded, color: color, size: 20),
        ],
      ),
    );
  }

  /// Big, obvious switch between moving the pawn and placing a wall.
  Widget _buildModeSelector({required bool enabled}) {
    final state = _game.gameState;
    final hasWalls = state.currentPlayer.hasWallsRemaining;

    return Row(
      children: [
        Expanded(
          child: _buildModeButton(
            icon: Icons.directions_walk_rounded,
            label: 'Move',
            selected: _game.boardMode == BoardInteractionMode.move,
            enabled: enabled,
            onTap: () => _setBoardMode(BoardInteractionMode.move),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildModeButton(
            icon: Icons.fence_rounded,
            label: hasWalls
                ? 'Wall (${state.currentPlayer.wallsRemaining})'
                : 'No walls',
            selected: _game.boardMode == BoardInteractionMode.wall,
            enabled: enabled && hasWalls,
            onTap: () => _setBoardMode(BoardInteractionMode.wall),
          ),
        ),
      ],
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? scheme.primary : scheme.surface;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            // 52px keeps the target comfortably above the 48dp minimum.
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outline.withValues(alpha: 0.4),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rotate / place / cancel for the wall being lined up, plus a live reason
  /// when the chosen slot is illegal.
  Widget _buildWallControls() {
    final pending = _game.pendingWall;
    final result = _game.pendingWallResult;
    final scheme = Theme.of(context).colorScheme;

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;

    if (pending == null) {
      statusColor = scheme.onSurface.withValues(alpha: 0.7);
      statusIcon = Icons.touch_app_rounded;
      statusText = 'Tap between two squares to aim the wall';
    } else if (result?.isValid ?? false) {
      statusColor = const Color(0xFF16A34A);
      statusIcon = Icons.check_circle_rounded;
      statusText = 'Ready — tap Place to confirm';
    } else {
      statusColor = const Color(0xFFDC2626);
      statusIcon = Icons.error_rounded;
      statusText = result?.message ?? 'That wall cannot go there';
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  _game.rotatePendingWall();
                  setState(() {});
                },
                icon: const Icon(Icons.rotate_90_degrees_cw_rounded, size: 18),
                label: const Text('Rotate'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _game.canCommitPendingWall
                    ? () {
                        _game.commitPendingWall();
                        setState(() {});
                      }
                    : null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Place wall'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setBoardMode(BoardInteractionMode mode) {
    setState(() {
      _game.boardMode = mode;
    });
    _showGameMessage(
      mode == BoardInteractionMode.wall
          ? 'Wall mode: tap between squares, then Place'
          : 'Move mode: tap a highlighted square',
    );
  }

  Widget _buildMessageToast() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
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
