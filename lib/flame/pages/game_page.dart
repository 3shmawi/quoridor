import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'dart:async';
import 'dart:math' show pi;
import 'dart:ui' show ImageFilter;

import '../constants.dart';
import '../../flame/game/quoridor_game.dart';
import '../../flame/services/app_strings.dart';
import '../../flame/services/audio_service.dart';
import '../../flame/services/settings_service.dart';
import '../../flame/services/online/online_game_controller.dart';
import '../../flame/services/turn_clock.dart';
import '../services/update/update_service.dart';
import '../models/online_chat.dart';
import '../models/online_session.dart';
import '../widgets/online_chat.dart';
import '../widgets/invite_sheet.dart';
import 'online_lobby_page.dart';
import '../services/online/invite/invite_link.dart';
import '../../flame/models/game_state.dart';
import '../../flame/models/move_notation.dart';
import '../../flame/models/player.dart';
import '../../flame/services/ai_service.dart';
import '../../flame/services/saved_game_service.dart';
import '../../theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, this.openLobby, this.inviteCode});

  /// Opens the online lobby and returns the game it started, if any, joining
  /// the game with the code given straight away. Tests put their own here;
  /// the app uses [OnlineLobbyPage].
  @visibleForTesting
  final Future<OnlineGameController?> Function(
    BuildContext context,
    String? joinCode,
  )?
  openLobby;

  /// The room code of an invite link the app was opened with: the game it
  /// joins instead of showing the mode sheet.
  final String? inviteCode;

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

  /// True until a game is picked from the mode sheet. The board behind it is
  /// only a backdrop until then, with a button to bring the sheet back, so
  /// closing the sheet never leaves the player stuck.
  bool _awaitingStart = true;

  bool get _isOnline => _online != null;

  /// Plays the sound for each message the others send.
  StreamSubscription<ChatMessage>? _chatSound;

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

    // Show game mode selection after the widget is built, with the game
    // left unfinished last time already on the board behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _whenBoardLoaded();
      await _restoreSavedGame();
      if (!mounted) return;
      final invite = widget.inviteCode;
      if (invite != null) {
        // Opened from an invite: straight into joining that game. Coming
        // back without joining lands on the start screen.
        forgetInviteInPage();
        unawaited(_startOnlineGame(joinCode: invite));
      } else {
        _showGameModeSelection();
      }
    });
  }

  /// Shows the strip under the board once the board exists.
  ///
  /// It used to wait for the first change of game state, and picking "Play
  /// vs AI" on a fresh launch keeps the board already loaded rather than
  /// changing it, so the players stayed hidden until somebody moved.
  Future<void> _whenBoardLoaded() async {
    try {
      await _game.loaded.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return;
    }
    if (!mounted) return;
    isInitializedProvider.value = true;
    setState(() {});
  }

  /// Puts back the local game the app was closed in the middle of.
  Future<void> _restoreSavedGame() async {
    // Storage that never answers must not keep the mode sheet away.
    final saved = await SavedGameService.instance.load().timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    if (saved == null || !mounted) return;

    if (!mounted || _isOnline || !_game.isInitialized) return;
    _game.updateGameState(saved);
  }

  /// Whether the board holds a local game worth going back to.
  bool get _canContinue =>
      _game.isInitialized &&
      !_isOnline &&
      !_game.gameState.isGameOver &&
      _game.gameState.moveHistory.isNotEmpty;

  void _initializeGame() {
    _game = QuoridorGame();

    _game.onGameStateChanged = _handleGameStateChanged;
    _game.onGameWon = _showConfetti;
    _game.onTurnPassed = _handleTurnPassed;
    _game.onInteractionChanged = () {
      if (mounted) setState(() {});
    };
    isInitializedProvider.value = _game.isInitialized;

    _clock.limit = SettingsService.instance.turnLimit.value;
    _clock.onExpired = _handleTurnExpired;
    SettingsService.instance.turnLimit.addListener(_handleTurnLimitChanged);
  }

  /// The time a turn lasts: the host's choice online, this device's own
  /// setting otherwise.
  TurnLimit get _turnLimit =>
      _online?.turnLimit ?? SettingsService.instance.turnLimit.value;

  void _handleTurnLimitChanged() {
    _clock.limit = _turnLimit;
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
    // Online, the clock waits for every seat to fill: until then nobody
    // can move, so there is no turn to run out.
    final online = _online;
    final waitingForPlayers = online != null && !(online.game?.isFull ?? false);

    if (state.isGameOver ||
        state.currentPlayer.isAI ||
        _menuOpen ||
        _awaitingStart ||
        waitingForPlayers) {
      _clock.stop();
      return;
    }

    _clock.beginTurn(
      '${state.gameId}:${state.moveHistory.length}:${state.currentPlayerId}',
    );
  }

  void _handleTurnPassed(int seat) {
    if (!mounted || !_game.isInitialized) return;
    final player = _game.gameState.playerById(seat);
    _showGameMessage(
      context.l10n.turnPassed(_labelFor(player, _online?.localPlayerId)),
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
  Future<void> _startOnlineGame({String? joinCode}) async {
    if (joinCode == null) closeMenu();

    final openLobby =
        widget.openLobby ??
        (context, joinCode) => Navigator.of(context).push<OnlineGameController>(
          MaterialPageRoute(
            builder: (_) => OnlineLobbyPage(joinCode: joinCode),
          ),
        );
    final controller = await openLobby(context, joinCode);

    if (controller == null || !mounted) {
      controller?.dispose();
      return;
    }

    _detachOnline(abandon: true);
    _online = controller;
    _awaitingStart = false;
    _clock.limit = _turnLimit;

    // The server's board is the one being rendered from here on.
    _game.localPlayerId = controller.localPlayerId;
    _game.turnGate = () => controller.isLocalTurn;
    _game.viewTurns = viewTurnsForSeat(controller.localPlayerId);
    _game.onSubmitMove = controller.submitMove;
    controller.onRemoteUpdate = _game.updateGameState;
    controller.onGameOver = _handleOnlineGameOver;
    controller.onDrawOffered = () {
      HapticFeedback.mediumImpact();
      AudioService.instance.play(Sfx.chat);
    };
    controller.onDrawDeclined = () {
      if (mounted) {
        _showGameMessage(context.l10n.drawDeclined(_opponentName));
      }
    };
    controller.addListener(_handleOnlineChanged);
    _chatSound = controller.chatArrivals.listen(_handleChatArrived);

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

    // A rematch can seat this device differently from the game before it.
    final online = _online;
    if (online != null && online.localPlayerId != _game.localPlayerId) {
      _game.localPlayerId = online.localPlayerId;
      _game.viewTurns = viewTurnsForSeat(online.localPlayerId);
    }

    _clock.limit = _turnLimit;

    final message = online == null ? null : context.l10n.onlineNotice(online);
    if (message != null) {
      _showGameMessage(message);
      _online?.consumeMessage();
    }
    _syncClock();
    setState(() {});
  }

  /// The other player of a two-player online game, by name.
  String get _opponentName =>
      _online?.session?.opponent?.displayName ?? context.l10n.opponent;

  void _handleOnlineGameOver(bool? didWin) {
    if (!mounted) return;
    if (didWin == true) _showConfetti(offerReplay: false);
    final reason = _online?.game?.outcomeReason;
    final l10n = context.l10n;
    _showGameMessage(switch ((didWin, reason)) {
      (null, _) => l10n.drawAgreed,
      (true, OnlineOutcomeReason.resign) => l10n.opponentResignedYouWin(
        _opponentName,
      ),
      (true, OnlineOutcomeReason.timeout) => l10n.opponentLeftYouWin(
        _opponentName,
      ),
      (true, _) => l10n.youWin,
      (false, OnlineOutcomeReason.resign) => l10n.youResigned,
      (false, _) => l10n.opponentWins,
    });
  }

  // --- Resigning and draws ---------------------------------------------------

  Future<void> _resign() async {
    final online = _online;
    if (online == null || !online.canResign) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.flag_rounded),
        title: Text(context.l10n.resignTitle),
        content: Text(context.l10n.resignGivesWin(_opponentName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.keepPlaying),
          ),
          FilledButton(
            key: const Key('confirmResign'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.resign),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (!await online.resign() && mounted) {
      _showGameMessage(context.l10n.backendError);
    }
  }

  Future<void> _offerDraw() async {
    final online = _online;
    if (online == null) return;
    final offered = await online.offerDraw();
    if (!mounted) return;
    _showGameMessage(
      offered
          ? context.l10n.drawOfferedTo(_opponentName)
          : context.l10n.backendError,
    );
  }

  Future<void> _answerDraw({required bool accept}) async {
    final online = _online;
    if (online == null) return;
    final done = accept
        ? await online.acceptDraw()
        : await online.declineDraw();
    if (!done && mounted) _showGameMessage(context.l10n.backendError);
  }

  /// The flag in the top bar of a two-player online game: offer a draw, or
  /// resign.
  Widget _buildGameActions(OnlineGameController online) {
    final canOffer = online.canOfferDraw && online.drawOfferToAnswer == null;
    return PopupMenuButton<void Function()>(
      key: const Key('gameActions'),
      tooltip: context.l10n.gameActions,
      icon: const Icon(Icons.flag_outlined),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('offerDraw'),
          value: _offerDraw,
          enabled: canOffer,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.handshake_outlined),
            title: Text(context.l10n.offerDraw),
            subtitle: canOffer
                ? null
                : Text(
                    online.drawOffered
                        ? context.l10n.drawPending
                        : context.l10n.drawOncePerMove,
                  ),
          ),
        ),
        PopupMenuItem(
          key: const Key('resign'),
          value: _resign,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.flag_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(context.l10n.resign),
          ),
        ),
      ],
    );
  }

  /// Tears down any online session and returns the board to local play.
  void _detachOnline({required bool abandon}) {
    final controller = _online;
    if (controller == null) return;

    _online = null;
    controller.removeListener(_handleOnlineChanged);
    _chatSound?.cancel();
    _chatSound = null;
    unawaited(controller.leave(abandon: abandon));
    controller.dispose();

    _clock.limit = _turnLimit;
    _game.localPlayerId = null;
    _game.turnGate = null;
    _game.viewTurns = 0;
    _game.onSubmitMove = null;
  }

  void _handleChatArrived(ChatMessage message) {
    if (message.seat == _online?.localPlayerId) return;
    AudioService.instance.play(Sfx.chat);
    HapticFeedback.selectionClick();
  }

  /// What the chat calls a seat: "You", or the name the player chose.
  String _chatName(int seat) {
    if (seat == _online?.localPlayerId) return context.l10n.you;
    return _online?.game?.players[seat]?.displayName ?? context.l10n.opponent;
  }

  void _openChat() {
    final online = _online;
    if (online == null) return;
    showChatSheet(
      context,
      controller: online,
      nameOf: _chatName,
      colorOf: _seatColor,
    );
  }

  Future<void> _leaveOnlineGame() async {
    closeMenu();
    // Leaving a two-player game under way gives it to the other player, so
    // that is said before it happens.
    final online = _online;
    if (online != null && online.leavingResigns) {
      final opponent =
          online.session?.opponent?.displayName ?? context.l10n.opponent;
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.leaveGameTitle),
          content: Text(context.l10n.leaveGameGivesWin(opponent)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.stay),
            ),
            FilledButton(
              key: const Key('confirmLeave'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.leaveGame),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    _detachOnline(abandon: true);
    _game.newGame();
    _awaitingStart = true;
    _syncClock();
    setState(() {});
    _showGameMessage(context.l10n.leftOnlineGame);
    // Straight on to picking the next game.
    _showGameModeSelection();
  }

  void _handleGameStateChanged(GameState gameState) {
    // Local games are kept so closing the app does not lose them; an online
    // game is the server's to keep.
    if (!_isOnline) unawaited(SavedGameService.instance.save(gameState));

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

  /// Celebrates a win, then offers another game.
  ///
  /// Online there is no "play again" to offer: a new game there means leaving
  /// this one, which the menu already does.
  void _showConfetti({bool offerReplay = true}) {
    _confettiController.play();
    if (!offerReplay) return;
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
            // Wraps rather than overflowing when the title runs long.
            Flexible(child: Text(context.l10n.gameOverTitle)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.nameWins(_winnerLabel),
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
              _restartGame();
            },
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.playAgain),
          ),
        ],
      ),
    );
  }

  /// The same kind of game again, from the start.
  void _restartGame() {
    _game.newGame();
    _showGameMessage(context.l10n.newGameStarted);
  }

  /// Brings up the mode sheet, the one way every game starts. Online, the
  /// game has to be left first, so it is not given up by accident.
  void _openNewGame() {
    if (_isOnline) {
      _showGameMessage(context.l10n.leaveOnlineFirst);
      return;
    }
    _showGameModeSelection();
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
      audio.stopAll();
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

  void _undo() {
    _game.clearInteraction();
    _game.undo();
    setState(() {});
  }

  /// Every move of the game so far, newest at the bottom.
  void _showMoveHistory() {
    final state = _game.gameState;
    final localSeat = _online?.localPlayerId;

    _whileMenuOpen(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        builder: (context) {
          final theme = Theme.of(context);
          final moves = state.moveHistory;
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    context.l10n.moveHistory,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (moves.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.noMovesYet,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      reverse: true,
                      itemCount: moves.length,
                      itemBuilder: (context, index) {
                        final number = moves.length - index;
                        final move = moves[number - 1];
                        final player = state.playerById(move.playerId);
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: _seatColor(move.playerId),
                            child: Text(
                              '$number',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(_labelFor(player, localSeat)),
                          trailing: Text(
                            MoveNotation.of(move) ?? context.l10n.passed,
                            // Squares are written in Latin letters either
                            // way, and read left to right.
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
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
        builder: _buildModeSheet,
      ).whenComplete(() {
        // Closing the sheet over a game in progress carries on with it.
        if (_awaitingStart && _canContinue) _awaitingStart = false;
      }),
    );
  }

  Widget _buildModeSheet(BuildContext context) {
    return Container(
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
                  key: const Key('mode_online'),
                  icon: Icons.public,
                  title: context.l10n.playOnline,
                  subtitle: context.l10n.playOnlineSubtitle,
                  featured: true,
                  onTap: () {
                    Navigator.pop(context);
                    _startOnlineGame();
                  },
                ),
                const SizedBox(height: 16),
                if (_canContinue) ...[
                  _buildModeCard(
                    icon: Icons.play_arrow_rounded,
                    title: context.l10n.continueGame,
                    subtitle: context.l10n.movesPlayed(
                      _game.gameState.moveHistory.length,
                    ),
                    onTap: () {
                      _awaitingStart = false;
                      Navigator.pop(context);
                      _syncClock();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                _buildModeCard(
                  icon: Icons.computer,
                  title: context.l10n.playVsAI,
                  subtitle: context.l10n.playVsAISubtitle,
                  onTap: () {
                    _detachOnline(abandon: true);
                    _awaitingStart = false;
                    // Coming back from a four-player game has to put the
                    // board back to two, not just swap in the computer.
                    // A game under way is left through "Continue", so
                    // this always means a fresh one.
                    if (_game.gameState.playerCount != 2 ||
                        !_game.gameState.player2.isAI ||
                        _game.gameState.moveHistory.isNotEmpty) {
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
                  icon: Icons.smart_toy_outlined,
                  title: context.l10n.playVsAIs,
                  subtitle: context.l10n.playVsAIsSubtitle,
                  onTap: _startGameAgainstSeveralAIs,
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
    );
  }

  /// Starts a hotseat game for [playerCount] on this device.
  /// Asks how many computers to play, then starts that table.
  Future<void> _startGameAgainstSeveralAIs() async {
    final opponents = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.howManyAIs),
        children: [
          for (final n in const [2, 3])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, n),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(context.l10n.aiOpponents(n)),
              ),
            ),
        ],
      ),
    );
    if (opponents == null || !mounted) return;

    _detachOnline(abandon: true);
    _awaitingStart = false;
    _game.startGame(playerCount: opponents + 1, againstAI: true);
    Navigator.pop(context);
    _syncClock();
    setState(() {});
    _showGameMessage(context.l10n.aiModeActivated);
  }

  void _startLocalGame(int playerCount) {
    _detachOnline(abandon: true);
    _awaitingStart = false;
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

  /// One choice in the mode sheet. The [featured] one is filled in the
  /// app's colour so it is the first thing the eye lands on.
  Widget _buildModeCard({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool featured = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = featured ? Colors.white : scheme.onSurface;

    return Card(
      key: key,
      elevation: featured ? 4 : 0,
      shadowColor: scheme.primary.withValues(alpha: 0.5),
      clipBehavior: Clip.antiAlias,
      color: featured ? null : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: featured
            ? BorderSide.none
            : BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Ink(
        decoration: featured
            ? const BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
              )
            : null,
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
                    color: featured
                        ? Colors.white.withValues(alpha: 0.2)
                        : scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: featured ? Colors.white : scheme.primary,
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: foreground,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground.withValues(alpha: 0.75),
                        ),
                      ),
                      if (featured) ...[
                        const SizedBox(height: 8),
                        // A peek at the reactions waiting in an online game.
                        Row(
                          children: [
                            for (final item in const [
                              QuickChat.laugh,
                              QuickChat.thinking,
                              QuickChat.angry,
                              QuickChat.scared,
                            ])
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 2,
                                ),
                                child: ChatGlyph(item, size: 16),
                              ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                context.l10n.chat,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: foreground.withValues(alpha: 0.5),
                ),
              ],
            ),
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
                            // Stays here after "Later", so the update is one
                            // tap away for as long as it is waiting.
                            if (UpdateService.instance.available.value
                                case final update?)
                              _buildMenuItem(
                                Icons.system_update_rounded,
                                context.l10n.updateWaiting(update.version),
                                context.l10n.updateWaitingSubtitle,
                                () {
                                  closeMenu();
                                  unawaited(UpdateService.instance.update());
                                },
                              ),
                            // Every game starts from the mode sheet, so
                            // this is the one way to a new one. Online, the
                            // game is left first, on purpose.
                            if (_isOnline)
                              _buildMenuItem(
                                Icons.logout_rounded,
                                context.l10n.leaveOnlineGame,
                                context.l10n.leaveOnlineGameSubtitle,
                                _leaveOnlineGame,
                              )
                            else
                              _buildMenuItem(
                                Icons.add_circle_outline_rounded,
                                context.l10n.newGame,
                                context.l10n.newGameSubtitle,
                                () {
                                  closeMenu();
                                  _openNewGame();
                                },
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
                              context.l10n.soundEffectsSubtitle,
                              AudioService.instance.enabled.value,
                              _toggleSound,
                            ),
                          ]),

                          const SizedBox(height: 24),

                          _buildMenuSection(context.l10n.turnTimer, [
                            // Online, everyone plays to the host's clock.
                            if (_isOnline)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 8,
                                  left: 4,
                                  right: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.lock_outline_rounded,
                                      size: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        context.l10n.turnTimerSetByHost,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                      text: "Mohager",
                      style: TextStyle(color: Colors.cyan),
                    ),
                  ],
                ),
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
                  // A tap anywhere off the game area -- the status strip, the
                  // padding, the banner -- puts down whatever was lined up.
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: TapRegion(
                          onTapOutside: (_) => _game.clearInteraction(),
                          // Online, the board dims while it is someone else's turn:
                          // it can be watched but not touched until the turn
                          // comes back.
                          child: AnimatedOpacity(
                            opacity: _isOnline && !_game.canActNow ? 0.75 : 1,
                            duration: const Duration(milliseconds: 200),
                            // Each online player sees the board from their own side,
                            // with their pawn starting at the bottom.
                            child: RotatedBox(
                              quarterTurns: _game.viewTurns,
                              child: GameWidget<QuoridorGame>.controlled(
                                gameFactory: () => _game,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Until a game is picked, the board is a backdrop
                      // for the way back to the mode sheet.
                      if (_awaitingStart && !_isOnline)
                        Positioned.fill(child: _buildStartPrompt()),
                      // Messages pop up in the board's corners.
                      if (_online case final online?)
                        Positioned.fill(
                          child: ChatBubbleLayer(
                            arrivals: online.chatArrivals,
                            localSeat: online.localPlayerId,
                            nameOf: _chatName,
                            colorOf: _seatColor,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isOnline) _buildOnlineBanner(),
                ValueListenableBuilder(
                  valueListenable: isInitializedProvider,
                  builder: (context, value, child) {
                    if (!value) return const SizedBox.shrink();
                    // Kept in place while hidden, so the board does not
                    // jump when the game starts.
                    return Visibility(
                      visible: !_awaitingStart,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: _buildStatusLine(),
                    );
                  },
                ),
              ],
            ),
          ),
          // Floats over the page rather than taking a place in the column:
          // in the column it shrank and moved the board while it showed, so
          // a tap in that moment landed on the wrong square. It drops in at
          // the top, where it is read first and covers neither the players
          // under the board nor the board itself on most screens, and taps go
          // through it to whatever is underneath.
          if (_showMessage)
            Positioned(
              left: 20,
              right: 20,
              top: 8,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _messageController,
                  builder: (context, child) {
                    final shown = Curves.easeOut.transform(
                      _messageController.value,
                    );
                    return Opacity(
                      opacity: shown,
                      child: Transform.translate(
                        offset: Offset(0, -16 * (1 - shown)),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: const Key('toast'),
                    child: _buildMessageToast(),
                  ),
                ),
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

        // The title, and under it the game being played. Tapping it is a
        // shortcut to the mode sheet.
        Expanded(child: _buildTitle()),

        if (_game.isInitialized && !_isOnline && !_awaitingStart)
          IconButton(
            key: const Key('undo'),
            tooltip: context.l10n.undo,
            onPressed: _game.canUndo ? _undo : null,
            icon: const Icon(Icons.undo_rounded),
          ),

        if (_online case final online? when online.canResign)
          _buildGameActions(online),

        if (_game.isInitialized && !_awaitingStart)
          IconButton(
            key: const Key('moveHistory'),
            tooltip: context.l10n.moveHistory,
            onPressed: _showMoveHistory,
            icon: const Icon(Icons.format_list_numbered_rounded),
          ),

        const SizedBox(width: 4),

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

  /// What is being played, in a few words, or null before anything is.
  String? get _modeLabel {
    if (_online case final online?) {
      final limit = online.turnLimit;
      return limit == TurnLimit.off
          ? context.l10n.modeOnline
          : context.l10n.modeOnlineTimed(limit.seconds);
    }
    if (_awaitingStart || !_game.isInitialized) return null;
    final state = _game.gameState;
    final computers = state.players.where((p) => p.isAI).length;
    if (computers == 1) {
      return context.l10n.modeVsAI(_difficultyLabel(_currentDifficulty));
    }
    if (computers > 1) return context.l10n.modeVsAIs(computers);
    return context.l10n.modeLocal(state.playerCount);
  }

  Widget _buildTitle() {
    final scheme = Theme.of(context).colorScheme;
    final label = _modeLabel;
    return Tooltip(
      message: _isOnline ? '' : context.l10n.newGame,
      child: InkWell(
        key: const Key('modeLabel'),
        borderRadius: BorderRadius.circular(12),
        onTap: _isOnline ? null : _openNewGame,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.appTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              if (label != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    if (!_isOnline)
                      Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown over the board until a game is picked: closing the mode sheet
  /// leads here rather than to a board nobody chose.
  Widget _buildStartPrompt() {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: ColoredBox(
            color: scheme.surface.withValues(alpha: 0.6),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.videogame_asset_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.readyToPlay,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.readyToPlaySubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Breathing(
                      child: FilledButton.icon(
                        key: const Key('startGame'),
                        onPressed: _openNewGame,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(context.l10n.startAGame),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
    final isSelected = _turnLimit == limit;
    final locked = _isOnline;
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
        enabled: !locked || isSelected,
        onTap: locked
            ? null
            : () => SettingsService.instance.turnLimit.value = limit,
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

    late Color color;
    late IconData icon;
    late String text;
    Widget? action;

    /// An action too wide to share the line with the text, shown under it.
    Widget? actionBelow;

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
          key: const Key('invite'),
          onPressed: () => _invite(online.roomCode),
          icon: const Icon(Icons.qr_code_2_rounded, size: 16),
          label: Text(context.l10n.invite),
        );

      case OnlineConnectionState.opponentAway:
        color = const Color(0xFFD97706);
        icon = Icons.cloud_off_rounded;
        text = context.l10n.nameGoneQuiet(
          online.awayPlayer?.displayName ?? context.l10n.opponent,
        );
        // In a two-player game, the win can be taken from a player who has
        // gone for good; until then, how long is left is counted down.
        final claimIn = online.claimWinIn;
        if (claimIn != null) {
          action = FilledButton.tonal(
            key: const Key('claimWin'),
            onPressed: claimIn == Duration.zero ? _claimWin : null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              claimIn == Duration.zero
                  ? context.l10n.claimWin
                  : context.l10n.claimWinIn(
                      (claimIn.inMilliseconds / 1000).ceil(),
                    ),
            ),
          );
        }

      case OnlineConnectionState.offline:
        color = const Color(0xFFDC2626);
        icon = Icons.wifi_off_rounded;
        text = context.l10n.lostContact;

      case OnlineConnectionState.ended:
        final offer = online.rematchOffer;
        color = offer != null
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.7);
        icon = offer != null ? Icons.replay_rounded : Icons.flag_rounded;
        text = offer != null
            ? context.l10n.rematchOffered(
                online.game?.players[offer.by]?.displayName ??
                    context.l10n.opponent,
              )
            : context.l10n.gameOverShort;
        if (online.canRematch || online.isRematching) {
          action = TextButton.icon(
            key: const Key('rematch'),
            onPressed: online.canRematch ? _requestRematch : null,
            icon: const Icon(Icons.replay_rounded, size: 16),
            label: Text(
              offer != null ? context.l10n.joinRematch : context.l10n.rematch,
            ),
          );
        }

      case OnlineConnectionState.live:
        final yourTurn = online.isLocalTurn;
        color = yourTurn ? const Color(0xFF16A34A) : scheme.primary;
        icon = yourTurn
            ? Icons.play_circle_outline_rounded
            : Icons.more_horiz_rounded;
        text = yourTurn
            ? context.l10n.yourTurn
            : context.l10n.nameThinking(
                online.playerToMove?.displayName ?? context.l10n.opponent,
              );
        if (online.drawOffered) text = '$text · ${context.l10n.drawPending}';
    }

    // A draw offered to this device takes over the strip until it is
    // answered, or lapses with the next move.
    if (online.drawOfferToAnswer != null) {
      color = scheme.primary;
      icon = Icons.handshake_rounded;
      text = context.l10n.opponentOffersDraw(_opponentName);
      action = null;
      actionBelow = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: const Key('declineDraw'),
            onPressed: () => _answerDraw(accept: false),
            child: Text(context.l10n.declineDraw),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: const Key('acceptDraw'),
            onPressed: () => _answerDraw(accept: true),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(context.l10n.acceptDraw),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
              ?action,
              if (online.game != null && online.localPlayerId != null) ...[
                const SizedBox(width: 8),
                ChatButton(
                  unread: online.unreadChat,
                  onPressed: _openChat,
                  arrivals: online.chatArrivals,
                  localSeat: online.localPlayerId,
                ),
              ],
            ],
          ),
          if (actionBelow != null) ...[const SizedBox(height: 6), actionBelow],
        ],
      ),
    );
  }

  /// Starts or joins the rematch, and moves the board over to it.
  Future<void> _requestRematch() async {
    final online = _online;
    if (online == null) return;

    final joined = await online.requestRematch();
    if (!mounted || !joined) return;

    _syncClock();
    setState(() {});
    _showGameMessage(
      online.connection == OnlineConnectionState.waitingForOpponent
          ? context.l10n.shareCodeToInvite(online.roomCode ?? '')
          : context.l10n.connectedGoodLuck,
    );
  }

  /// Shows the QR code, the code and the link that bring a friend into this
  /// game.
  Future<void> _invite(String? code) async {
    if (code == null) return;
    final copied = await showInviteSheet(context, code);
    if (copied && mounted) _showGameMessage(context.l10n.inviteCopied);
  }

  Future<void> _claimWin() async {
    final claimed = await _online?.claimWin() ?? false;
    if (!claimed && mounted) _showGameMessage(context.l10n.backendError);
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
          // Everyone but the player to move fades well back, so whose turn
          // it is reads at a glance.
          child: AnimatedOpacity(
            opacity: state.currentPlayerId == player.id ? 1 : 0.35,
            duration: const Duration(milliseconds: 200),
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
        ),
      );
    }

    return Row(children: pills);
  }

  /// The winner as the board names them: "AI" and "Player 2" are stored in
  /// English, so they are never shown as they are.
  String get _winnerLabel {
    final id = _game.gameState.winnerId;
    if (id == null) return '';
    return _labelFor(_game.gameState.playerById(id), _online?.localPlayerId);
  }

  /// What to call a seat: you, the person you are playing, or its number.
  String _labelFor(Player player, int? localSeat) {
    if (localSeat != null) {
      if (player.id == localSeat) return context.l10n.you;
      return _online?.game?.players[player.id]?.displayName ??
          context.l10n.opponent;
    }

    if (player.isAI) {
      // One computer is "AI"; several are told apart by their seat.
      final computers = _game.gameState.players.where((p) => p.isAI).length;
      return computers > 1 ? context.l10n.aiN(player.id) : context.l10n.ai;
    }
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

/// Quarter turns (clockwise) that put [seat]'s starting edge at the bottom.
///
/// Seat 1 starts at the bottom already, seat 2 at the top, seat 3 on the left
/// and seat 4 on the right.
int viewTurnsForSeat(int? seat) {
  switch (seat) {
    case 2:
      return 2;
    case 3:
      return 3;
    case 4:
      return 1;
    default:
      return 0;
  }
}

/// Grows and shrinks a little, over and over, to draw the eye to [child].
/// Still when the platform asks for less motion.
class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 1,
        end: 1.05,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
