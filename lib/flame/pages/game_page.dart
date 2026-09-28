import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'dart:async';
import 'dart:math' show pi;

import '../constants.dart';
import '../../flame/game/quoridor_game.dart';
import '../../flame/services/app_strings.dart';
import '../../flame/services/audio_service.dart';
import '../../flame/services/settings_service.dart';
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
  AIDifficulty _currentDifficulty = SettingsService.instance.difficulty.value;

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
          ? context.l10n.shareCodeToInvite(controller.roomCode ?? '')
          : context.l10n.connectedGoodLuck,
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
    _showGameMessage(didWin ? context.l10n.youWin : context.l10n.opponentWins);
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
    _showGameMessage(context.l10n.leftOnlineGame);
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
            Text(context.l10n.gameOverTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.nameWins('${_game.gameState.winner}'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.playAgainSuggestion,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(context.l10n.notNow),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _newGame();
            },
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.playAgain),
          ),
        ],
      ),
    );
  }

  void _newGame() {
    if (_isOnline) {
      _showGameMessage(context.l10n.leaveOnlineFirst);
      closeMenu();
      return;
    }
    _game.newGame();
    _showGameMessage(context.l10n.newGameStarted);
    closeMenu();
  }

  void _toggleValidMoves() {
    setState(() {
      _showValidMoves = !_showValidMoves;
    });
    _game.showValidMoves(_showValidMoves);
    _showGameMessage(
      _showValidMoves
          ? context.l10n.validMovesShown
          : context.l10n.validMovesHidden,
    );
    closeMenu();
  }

  /// Switches between English and Arabic, which also flips the layout
  /// direction for the whole app.
  void _toggleLanguage() {
    SettingsService.instance.toggleLanguage();
    setState(() {});
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
    _showGameMessage(
      audio.enabled.value ? context.l10n.soundOn : context.l10n.soundOff,
    );
    closeMenu();
  }

  void _changeDifficulty(AIDifficulty difficulty) {
    setState(() {
      _currentDifficulty = difficulty;
    });
    SettingsService.instance.difficulty.value = difficulty;
    _game.setDifficulty(difficulty);
    _showGameMessage(
      context.l10n.difficultySetTo(_difficultyLabel(difficulty)),
    );
  }

  void _togglePlayerMode() {
    _game.togglePlayerMode();
    closeMenu();
  }

  Future<void> _saveGame() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      _showGameMessage(context.l10n.signInToSave);
      closeMenu();
      return;
    }

    // Read the strings before awaiting: the screen may be gone by the time
    // the save returns.
    final saved = context.l10n.gameSaved;
    final failed = context.l10n.gameSaveFailed;

    final gameId = await FirebaseService.saveGame(_game.gameState);
    if (!mounted) return;

    _showGameMessage(gameId != null ? saved : failed);
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
              context.l10n.chooseGameMode,
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
                    title: context.l10n.playVsAI,
                    subtitle: context.l10n.playVsAISubtitle,
                    onTap: () {
                      if (!_game.gameState.player2.isAI) {
                        _game.togglePlayerMode();
                      } else {
                        _game.updateGameState(_game.gameState);
                      }
                      Navigator.pop(context);
                      _showGameMessage(context.l10n.aiModeActivated);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModeCard(
                    icon: Icons.public,
                    title: context.l10n.playOnline,
                    subtitle: context.l10n.playOnlineSubtitle,
                    onTap: () {
                      Navigator.pop(context);
                      _startOnlineGame();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildModeCard(
                    icon: Icons.people,
                    title: context.l10n.twoPlayers,
                    subtitle: context.l10n.twoPlayersSubtitle,
                    onTap: () {
                      if (_game.gameState.player2.isAI) {
                        _game.togglePlayerMode();
                      } else {
                        _game.updateGameState(_game.gameState);
                      }
                      Navigator.pop(context);
                      _showGameMessage(context.l10n.twoPlayerModeActivated);
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
                          _buildMenuSection(context.l10n.gameControls, [
                            if (_isOnline)
                              _buildMenuItem(
                                Icons.logout_rounded,
                                context.l10n.leaveOnlineGame,
                                context.l10n.leaveOnlineGameSubtitle,
                                _leaveOnlineGame,
                              )
                            else
                              _buildMenuItem(
                                Icons.public,
                                context.l10n.playOnline,
                                context.l10n.playOnlineSubtitleShort,
                                _startOnlineGame,
                              ),
                            _buildMenuItem(
                              Icons.refresh,
                              context.l10n.newGame,
                              context.l10n.newGameSubtitle,
                              _newGame,
                            ),
                            _buildMenuItem(
                              Icons.save,
                              context.l10n.saveGame,
                              context.l10n.saveGameSubtitle,
                              _saveGame,
                            ),
                            if (_game.isInitialized)
                              _buildMenuItem(
                                Icons.people,
                                context.l10n.togglePlayerMode,
                                _game.gameState.player2.isAI
                                    ? context.l10n.switchToTwoPlayers
                                    : context.l10n.switchToAI,
                                _togglePlayerMode,
                              ),
                          ]),

                          const SizedBox(height: 24),

                          _buildMenuSection(context.l10n.displayOptions, [
                            _buildSwitchItem(
                              Icons.visibility,
                              context.l10n.showValidMoves,
                              context.l10n.showValidMovesSubtitle,
                              _showValidMoves,
                              _toggleValidMoves,
                            ),
                            _buildSwitchItem(
                              Icons.dark_mode,
                              context.l10n.darkMode,
                              context.l10n.darkModeSubtitle,
                              isDarkModeNotifier.value,
                              () => isDarkModeNotifier.value =
                                  !isDarkModeNotifier.value,
                            ),
                            _buildMenuItem(
                              Icons.language,
                              context.l10n.language,
                              context.l10n.languageSubtitle,
                              _toggleLanguage,
                            ),
                            _buildSwitchItem(
                              AudioService.instance.enabled.value
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              context.l10n.soundEffects,
                              AudioService.instance.isUnavailable
                                  ? context.l10n.soundUnavailable
                                  : context.l10n.soundEffectsSubtitle,
                              AudioService.instance.enabled.value,
                              _toggleSound,
                            ),
                          ]),

                          const SizedBox(height: 24),

                          _buildMenuSection(context.l10n.aiDifficulty, [
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
                    return _buildStatusLine();
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
            context.l10n.appTitle,
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
          _difficultyLabel(difficulty),
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
        return context.l10n.easySubtitle;
      case AIDifficulty.medium:
        return context.l10n.mediumSubtitle;
      case AIDifficulty.hard:
        return context.l10n.hardSubtitle;
    }
  }

  String _difficultyLabel(AIDifficulty difficulty) {
    switch (difficulty) {
      case AIDifficulty.easy:
        return context.l10n.easy;
      case AIDifficulty.medium:
        return context.l10n.medium;
      case AIDifficulty.hard:
        return context.l10n.hard;
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
        text = context.l10n.connecting;

      case OnlineConnectionState.waitingForOpponent:
        color = const Color(0xFFD97706);
        icon = Icons.hourglass_top_rounded;
        text = context.l10n.waitingForOpponentWithCode(online.roomCode ?? '');
        action = TextButton.icon(
          onPressed: () => _copyRoomCode(online.roomCode),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: Text(context.l10n.copy),
        );

      case OnlineConnectionState.opponentAway:
        color = const Color(0xFFD97706);
        icon = Icons.cloud_off_rounded;
        text =
            '${online.session?.opponent?.displayName ?? context.l10n.opponent} '
            'has gone quiet';

      case OnlineConnectionState.offline:
        color = const Color(0xFFDC2626);
        icon = Icons.wifi_off_rounded;
        text = context.l10n.lostContact;

      case OnlineConnectionState.ended:
        color = scheme.onSurface.withValues(alpha: 0.7);
        icon = Icons.flag_rounded;
        text = context.l10n.gameOverShort;

      case OnlineConnectionState.live:
        final yourTurn = online.isLocalTurn;
        color = yourTurn ? const Color(0xFF16A34A) : scheme.primary;
        icon = yourTurn
            ? Icons.play_circle_outline_rounded
            : Icons.more_horiz_rounded;
        text = yourTurn
            ? context.l10n.yourTurn
            : '${online.session?.opponent?.displayName ?? context.l10n.opponent} '
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
    if (mounted) _showGameMessage(context.l10n.codeCopied(code));
  }

  // --- Status line ---------------------------------------------------------

  /// The strip under the board: both players, their walls, and whose turn it
  /// is.
  ///
  /// Online, "you" is whichever seat this device holds -- it is not always
  /// seat 1. Reading the seats positionally showed the opponent's wall count
  /// as your own for whoever joined second.
  Widget _buildStatusLine() {
    final state = _game.gameState;
    final online = _online;
    final localSeat = online?.localPlayerId ?? 1;
    final opponentSeat = 3 - localSeat;

    final localPlayer = localSeat == 1 ? state.player1 : state.player2;
    final opponentPlayer = localSeat == 1 ? state.player2 : state.player1;

    final String opponentLabel;
    if (online != null) {
      opponentLabel =
          online.session?.opponent?.displayName ?? context.l10n.opponent;
    } else if (opponentPlayer.isAI) {
      opponentLabel = context.l10n.ai;
    } else {
      opponentLabel = context.l10n.playerN(opponentSeat);
    }

    return Row(
      children: [
        Expanded(
          child: _buildPlayerStatus(
            label: context.l10n.you,
            color: _seatColor(localSeat),
            walls: localPlayer.wallsRemaining,
            isActive: state.currentPlayerId == localSeat,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildPlayerStatus(
            label: opponentLabel,
            color: _seatColor(opponentSeat),
            walls: opponentPlayer.wallsRemaining,
            isActive: state.currentPlayerId == opponentSeat,
            trailing: true,
          ),
        ),
      ],
    );
  }

  static Color _seatColor(int seat) => Color(
    seat == 1 ? GameConstants.player1Color : GameConstants.player2Color,
  );

  /// One player's pill. The player to move gets their colour and says so; the
  /// other fades back, so whose turn it is reads at a glance rather than from
  /// a weight difference in the text.
  Widget _buildPlayerStatus({
    required String label,
    required Color color,
    required int walls,
    required bool isActive,
    bool trailing = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    final badge = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: isActive ? color : color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$walls',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.white : color,
        ),
      ),
    );

    final text = Flexible(
      child: Column(
        crossAxisAlignment: trailing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface.withValues(alpha: isActive ? 1 : 0.55),
            ),
          ),
          Text(
            isActive ? context.l10n.toPlay : context.l10n.wallsCount(walls),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isActive
                  ? color
                  : scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? color.withValues(alpha: 0.6)
              : scheme.outline.withValues(alpha: 0.25),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: trailing
            ? [text, const SizedBox(width: 10), badge]
            : [badge, const SizedBox(width: 10), text],
      ),
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
          Expanded(child: Text(context.l10n.howToPlay)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoSection(
              context.l10n.objective,
              context.l10n.objectiveBody,
            ),
            _buildInfoSection(
              context.l10n.yourTurnSection,
              context.l10n.yourTurnBody,
            ),
            _buildInfoSection(
              context.l10n.movement,
              'The squares you can reach are ringed in your colour — tap one to move there. You may jump over your opponent if they are in your way.',
            ),
            _buildInfoSection(
              context.l10n.wallsSection,
              context.l10n.wallsBody,
            ),
            _buildInfoSection(context.l10n.winning, context.l10n.winningBody),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.gotIt),
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
