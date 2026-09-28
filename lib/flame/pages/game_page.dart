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
import '../../flame/services/turn_clock.dart';
import 'online_lobby_page.dart';
import '../../flame/models/game_state.dart';
import '../../flame/models/player.dart';
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

  /// Counts down the turn in front of whoever is to play.
  final TurnClock _clock = TurnClock();

  /// True while a sheet or dialog is covering the board.
  ///
  /// The clock is paused under one: the mode sheet opens on the very first
  /// frame, and a player reading it should not come back to a turn that has
  /// already been played for them.
  bool _menuOpen = false;

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

    _clock.limit = SettingsService.instance.turnLimit.value;
    _clock.onExpired = _handleTurnExpired;
    SettingsService.instance.turnLimit.addListener(_handleTurnLimitChanged);
  }

  void _handleTurnLimitChanged() {
    _clock.limit = SettingsService.instance.turnLimit.value;
    _syncClock();
    if (mounted) setState(() {});
  }

  /// Keeps the clock pointed at the turn actually in front of the player.
  ///
  /// Called after anything that could have changed whose turn it is. The key
  /// carries the move count as well as the seat, so a game where both sides
  /// are the same player still restarts the clock on every move.
  void _syncClock() {
    if (!_game.isInitialized) return;

    final state = _game.gameState;

    // Nothing to count down while the computer is thinking, once somebody has
    // won, or under an open menu.
    if (state.isGameOver || state.currentPlayer.isAI || _menuOpen) {
      _clock.stop();
      return;
    }

    _clock.beginTurn(
      '${state.gameId}:${state.moveHistory.length}:${state.currentPlayerId}',
    );
  }

  void _handleTurnExpired() {
    if (!mounted) return;
    _showGameMessage(context.l10n.outOfTime);
    _game.playForCurrentPlayer();
  }

  void closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _detachOnline(abandon: false);
    SettingsService.instance.turnLimit.removeListener(_handleTurnLimitChanged);
    _clock.dispose();
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
    _syncClock();
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
    _syncClock();
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
    _whileMenuOpen(
      showDialog<void>(
        context: context,
        builder: (context) => _buildGameInfoDialog(),
      ),
    );
  }

  /// Holds the clock while [barrier] is on screen, and starts it again after.
  void _whileMenuOpen(Future<void> barrier) {
    _menuOpen = true;
    _syncClock();
    barrier.whenComplete(() {
      if (!mounted) return;
      _menuOpen = false;
      _syncClock();
      setState(() {});
    });
  }

  void _showGameModeSelection() {
    _whileMenuOpen(
      showModalBottomSheet<void>(
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
                        _detachOnline(abandon: true);
                        // Coming back from a four-player game has to put the
                        // board back to two, not just swap in the computer.
                        if (_game.gameState.playerCount != 2 ||
                            !_game.gameState.player2.isAI) {
                          _game.startGame(playerCount: 2, againstAI: true);
                        }
                        Navigator.pop(context);
                        _syncClock();
                        setState(() {});
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
                      onTap: () => _startLocalGame(2),
                    ),
                    const SizedBox(height: 16),
                    _buildModeCard(
                      icon: Icons.groups,
                      title: context.l10n.threePlayers,
                      subtitle: context.l10n.threePlayersSubtitle,
                      onTap: () => _startLocalGame(3),
                    ),
                    const SizedBox(height: 16),
                    _buildModeCard(
                      icon: Icons.groups_3,
                      title: context.l10n.fourPlayers,
                      subtitle: context.l10n.fourPlayersSubtitle,
                      onTap: () => _startLocalGame(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Starts a hotseat game for [playerCount] on this device.
  void _startLocalGame(int playerCount) {
    _detachOnline(abandon: true);
    _game.startGame(playerCount: playerCount, againstAI: false);
    Navigator.pop(context);
    _syncClock();
    setState(() {});
    _showGameMessage(
      playerCount == 2
          ? context.l10n.twoPlayerModeActivated
          : context.l10n.localGameStarted(playerCount),
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
      // The drawer covers the board, so the turn under it is not being played.
      onDrawerChanged: (isOpen) {
        _menuOpen = isOpen;
        _syncClock();
      },
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

                          _buildMenuSection(context.l10n.turnTimer, [
                            for (final limit in TurnLimit.values)
                              _buildTurnLimitItem(limit),
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

  Widget _buildTurnLimitItem(TurnLimit limit) {
    final isSelected = SettingsService.instance.turnLimit.value == limit;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? scheme.primary.withValues(alpha: 0.1)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? scheme.primary
              : scheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        onTap: () => SettingsService.instance.turnLimit.value = limit,
        leading: Icon(
          limit == TurnLimit.off ? Icons.all_inclusive : Icons.timer_outlined,
          color: isSelected
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: 0.7),
        ),
        title: Text(
          limit == TurnLimit.off
              ? context.l10n.turnTimerOff
              : context.l10n.turnTimerSeconds(limit.seconds),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? scheme.primary : scheme.onSurface,
          ),
        ),
        subtitle: Text(
          limit == TurnLimit.off
              ? context.l10n.turnTimerOffSubtitle
              : context.l10n.turnTimerSecondsSubtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : null,
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
    // Only this strip rebuilds on a tick, not the board with it.
    return ValueListenableBuilder<Duration?>(
      valueListenable: _clock.remaining,
      builder: (context, remaining, _) => _buildStatusRow(remaining),
    );
  }

  Widget _buildStatusRow(Duration? remaining) {
    final state = _game.gameState;
    final online = _online;

    // Online there is a "you"; on one device passed around there is not, so
    // every seat is simply named.
    final localSeat = online?.localPlayerId;

    // Two pills can each afford a name and a wall count. Four cannot, so past
    // two they shrink to the badge and the seat's name, and only the player
    // to move spells out what is going on.
    final compact = state.playerCount > 2;

    final pills = <Widget>[];
    for (final player in state.players) {
      if (pills.isNotEmpty) pills.add(SizedBox(width: compact ? 6 : 10));

      pills.add(
        Expanded(
          child: _buildPlayerStatus(
            seat: player.id,
            label: _labelFor(player, localSeat),
            color: _seatColor(player.id),
            walls: player.wallsRemaining,
            isActive: state.currentPlayerId == player.id,
            remaining: state.currentPlayerId == player.id ? remaining : null,
            compact: compact,
            // The last pill leans its badge outwards, so the row reads as a
            // pair of ends rather than everything crowding to the left.
            trailing: !compact && player.id != state.players.first.id,
          ),
        ),
      );
    }

    return Row(children: pills);
  }

  /// What to call a seat: you, the person you are playing, or its number.
  String _labelFor(Player player, int? localSeat) {
    if (localSeat != null) {
      if (player.id == localSeat) return context.l10n.you;
      return _online?.session?.opponent?.displayName ?? context.l10n.opponent;
    }

    if (player.isAI) return context.l10n.ai;
    return context.l10n.playerN(player.id);
  }

  /// Seconds left, rounded up, so the clock shows 1 for the whole of the last
  /// second rather than sitting on 0 while there is still time to move.
  static int _clockSeconds(Duration remaining) =>
      (remaining.inMilliseconds / 1000).ceil();

  /// A countdown as m:ss, or just seconds when under a minute.
  static String _formatClock(int seconds) {
    if (seconds < 60) return '$seconds';
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  static Color _seatColor(int seat) => Color(GameConstants.colorForSeat(seat));

  /// One player's pill. The player to move gets their colour and says so; the
  /// other fades back, so whose turn it is reads at a glance rather than from
  /// a weight difference in the text.
  Widget _buildPlayerStatus({
    required int seat,
    required String label,
    required Color color,
    required int walls,
    required bool isActive,
    Duration? remaining,
    bool trailing = false,
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    // The last five seconds go red, so the countdown is noticed without being
    // watched — the board is where the player is looking, not here. The test
    // is on the number actually shown, so the colour and the digit never
    // disagree about how much time is left.
    final shown = remaining == null ? null : _clockSeconds(remaining);
    final isUrgent = shown != null && shown <= 5;
    final liveColor = isUrgent ? scheme.error : color;

    final badgeSize = compact ? 26.0 : 30.0;

    // With four at the board the badge shows the seat number rather than the
    // wall count, because that is the number printed on the pawn: a row of
    // pills that all read "5" says nothing about which one is you.
    final badgeText = compact ? '$seat' : '$walls';

    final badge = Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: isActive ? color : color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        badgeText,
        style: TextStyle(
          fontSize: compact ? 12 : 13,
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
          if (!compact)
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shown != null) ...[
                Icon(Icons.timer_outlined, size: 12, color: liveColor),
                const SizedBox(width: 3),
                Text(
                  _formatClock(shown),
                  style: TextStyle(
                    fontSize: 11,
                    // Tabular figures, so the text does not twitch sideways
                    // as the digits change.
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: isUrgent ? FontWeight.bold : FontWeight.w500,
                    color: liveColor,
                  ),
                ),
              ] else
                Flexible(
                  child: Text(
                    isActive
                        ? context.l10n.toPlay
                        : (compact
                              ? context.l10n.wallsShort(walls)
                              : context.l10n.wallsCount(walls)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? color
                          : scheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? liveColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? liveColor.withValues(alpha: 0.6)
              : scheme.outline.withValues(alpha: 0.25),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: trailing
            ? [text, SizedBox(width: compact ? 6 : 10), badge]
            : [badge, SizedBox(width: compact ? 6 : 10), text],
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
