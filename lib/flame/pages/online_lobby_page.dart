import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/online_session.dart';
import '../services/identity_service.dart';
import '../services/online/online_game_controller.dart';
import '../services/online/online_game_service.dart';
import '../services/online/room_code.dart';

/// Where a player starts or rejoins an online game.
///
/// The whole screen is built around one idea: a six-character code is the only
/// thing two people need to exchange. There are no accounts to create and
/// nothing to configure.
class OnlineLobbyPage extends StatefulWidget {
  const OnlineLobbyPage({super.key});

  @override
  State<OnlineLobbyPage> createState() => _OnlineLobbyPageState();
}

class _OnlineLobbyPageState extends State<OnlineLobbyPage> {
  final TextEditingController _codeController = TextEditingController();

  bool _busy = false;
  String? _error;
  List<OnlineGame> _resumable = const [];

  @override
  void initState() {
    super.initState();
    _loadResumableGames();
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
        _error = controller.message ?? 'Could not start the game';
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
        title: const Text('Play online'),
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
                'Games in progress',
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
        return Row(
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
                    identity?.displayName ?? 'Connecting…',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    'Your opponent sees this name',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
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
                  'Start a game',
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
              'You get a six-character code. Share it and your friend joins.',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run((c) => c.createGame()),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Create game'),
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
                  'Join a game',
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
                hintText: 'CODE',
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
              label: const Text('Join game'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumeTile(OnlineGame game) {
    final scheme = Theme.of(context).colorScheme;
    final waiting = game.status == OnlineGameStatus.waiting;
    final opponent =
        game.players[1]?.uid == IdentityService.instance.current?.uid
        ? game.players[2]
        : game.players[1];

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
              ? 'Waiting for an opponent'
              : 'vs ${opponent?.displayName ?? 'Opponent'}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Text(
          'Code ${game.roomCode} · ${game.moveCount} moves',
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
