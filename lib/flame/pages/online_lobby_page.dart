import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/online_session.dart';
import '../services/app_strings.dart';
import '../services/identity_service.dart';
import '../services/online/online_game_controller.dart';
import '../services/online/online_game_service.dart';
import '../services/online/room_code.dart';
import 'scan_invite_page.dart';
import '../services/settings_service.dart';
import '../services/turn_clock.dart';

/// Where a player starts or rejoins an online game.
///
/// The whole screen is built around one idea: a six-character code is the only
/// thing two people need to exchange. There are no accounts to create and
/// nothing to configure.
class OnlineLobbyPage extends StatefulWidget {
  const OnlineLobbyPage({super.key, this.joinCode});

  /// A code from an invite link: the lobby joins its game as soon as it
  /// opens.
  final String? joinCode;

  @override
  State<OnlineLobbyPage> createState() => _OnlineLobbyPageState();
}

class _OnlineLobbyPageState extends State<OnlineLobbyPage> {
  final TextEditingController _codeController = TextEditingController();

  bool _busy = false;

  /// Seats in the game this device would create.
  int _playerCount = 2;

  /// The time every player gets for a turn in the game this device would
  /// create. Starts from this player's own setting.
  TurnLimit _turnLimit = SettingsService.instance.turnLimit.value;
  String? _error;
  List<OnlineGame> _resumable = const [];

  @override
  void initState() {
    super.initState();
    _loadResumableGames();
    final code = widget.joinCode;
    if (code != null) {
      _codeController.text = code;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run((c) => c.joinGame(code));
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadResumableGames() async {
    // Sign-in may still be in flight when the lobby opens.
    await IdentityService.instance.ensureSignedIn();
    final games = await OnlineGameService.instance.myActiveGames();
    if (mounted) setState(() => _resumable = games);
  }

  Future<void> _scanInvite() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanInvitePage()));
    if (code == null || !mounted) return;
    _codeController.text = code;
    await _run((c) => c.joinGame(code));
  }

  /// Runs [action] with the busy state held, and reports any failure.
  Future<void> _run(Future<bool> Function(OnlineGameController) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final controller = OnlineGameController();
    final ok = await action(controller);

    if (!mounted) {
      controller.dispose();
      return;
    }

    if (!ok) {
      setState(() {
        _busy = false;
        _error =
            context.l10n.onlineNotice(controller) ?? context.l10n.couldNotStart;
      });
      controller.dispose();
      return;
    }

    setState(() => _busy = false);
    // Hand the live controller to the game screen, which takes ownership.
    Navigator.of(context).pop(controller);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Text(context.l10n.onlineLobbyTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildIdentityCard(),
            const SizedBox(height: 24),
            _buildCreateCard(),
            const SizedBox(height: 16),
            _buildJoinCard(),
            if (_resumable.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                context.l10n.gamesInProgress,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              ..._resumable.map(_buildResumeTile),
            ],
            if (_error != null) ...[
              const SizedBox(height: 20),
              _buildError(_error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return ValueListenableBuilder<LocalIdentity?>(
      valueListenable: IdentityService.instance.identity,
      builder: (context, identity, child) {
        final scheme = Theme.of(context).colorScheme;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: identity == null || _busy ? null : _editName,
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary.withValues(alpha: 0.15),
                child: Icon(Icons.person_outline, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity?.displayName ?? context.l10n.connecting,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      context.l10n.tapToChangeName,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, size: 18),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editName() async {
    final controller = TextEditingController(
      text: IdentityService.instance.current?.displayName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.yourName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: IdentityService.maxNameLength,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await IdentityService.instance.setDisplayName(name);
  }

  Widget _buildCreateCard() {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  context.l10n.startAGame,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.startAGameSubtitle,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.howManyPlayers,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (final count in const [2, 3, 4])
                  ButtonSegment(
                    value: count,
                    label: Text('$count'),
                    icon: const Icon(Icons.person_outline, size: 18),
                  ),
              ],
              selected: {_playerCount},
              showSelectedIcon: false,
              onSelectionChanged: _busy
                  ? null
                  : (selection) =>
                        setState(() => _playerCount = selection.first),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.timePerTurn,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TurnLimit>(
                key: const Key('lobbyTurnLimit'),
                segments: [
                  for (final limit in TurnLimit.values)
                    ButtonSegment(
                      value: limit,
                      label: Text(
                        limit == TurnLimit.off
                            ? '∞'
                            : context.l10n.secondsShort(limit.seconds),
                      ),
                      tooltip: limit == TurnLimit.off
                          ? context.l10n.turnTimerOff
                          : context.l10n.turnTimerSeconds(limit.seconds),
                    ),
                ],
                selected: {_turnLimit},
                showSelectedIcon: false,
                onSelectionChanged: _busy
                    ? null
                    : (selection) =>
                          setState(() => _turnLimit = selection.first),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _turnLimit == TurnLimit.off
                  ? context.l10n.turnTimerOffSubtitle
                  : context.l10n.timePerTurnHint,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                      (c) => c.createGame(
                        playerCount: _playerCount,
                        turnLimit: _turnLimit,
                      ),
                    ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(context.l10n.createGame),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinCard() {
    final scheme = Theme.of(context).colorScheme;
    final typed = RoomCode.normalize(_codeController.text);
    final canJoin = RoomCode.isValid(typed) && !_busy;

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.login_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  context.l10n.joinAGame,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              maxLength: RoomCode.length + 2,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: context.l10n.codeHint,
                counterText: '',
                hintStyle: TextStyle(
                  letterSpacing: 8,
                  color: scheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
              // Codes are dictated aloud, so what the player types is folded
              // onto the characters codes actually use rather than rejected.
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final cleaned = RoomCode.normalize(newValue.text);
                  return TextEditingValue(
                    text: cleaned,
                    selection: TextSelection.collapsed(offset: cleaned.length),
                  );
                }),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) {
                if (RoomCode.isValid(RoomCode.normalize(value))) {
                  _run((c) => c.joinGame(value));
                }
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canJoin
                  ? () => _run((c) => c.joinGame(_codeController.text))
                  : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(context.l10n.joinGame),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            // On a phone, the friend's QR code joins without typing.
            if (canScanInvites) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('scanInvite'),
                onPressed: _busy ? null : _scanInvite,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(context.l10n.scanQr),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResumeTile(OnlineGame game) {
    final scheme = Theme.of(context).colorScheme;
    final waiting = game.status == OnlineGameStatus.waiting;
    final myUid = IdentityService.instance.current?.uid;
    final opponents = [
      for (final player in game.players.values)
        if (player.uid != myUid) player.displayName,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        leading: Icon(
          waiting ? Icons.hourglass_empty_rounded : Icons.sports_esports,
          color: scheme.primary,
        ),
        title: Text(
          waiting
              ? context.l10n.waitingForOpponent
              : context.l10n.versName(
                  opponents.isEmpty
                      ? context.l10n.opponent
                      : opponents.join(', '),
                ),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Text(
          [
            context.l10n.codeAndMoves(game.roomCode, game.moveCount),
            if (game.turnLimit != TurnLimit.off)
              context.l10n.secondsShort(game.turnLimit.seconds),
          ].join(' · '),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _busy ? null : () => _run((c) => c.resumeGame(game.gameId)),
      ),
    );
  }

  Widget _buildError(String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
