import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/services/game_session_service.dart';
import 'package:quoridor/flame/widgets/game_chat_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OnlineGameWidget extends StatefulWidget {
  final String sessionId;
  final bool isHost;

  const OnlineGameWidget({
    Key? key,
    required this.sessionId,
    required this.isHost,
  }) : super(key: key);

  @override
  State<OnlineGameWidget> createState() => _OnlineGameWidgetState();
}

class _OnlineGameWidgetState extends State<OnlineGameWidget> {
  final GameSessionService _sessionService = GameSessionService();
  late QuoridorGame _game;
  bool _isGameOver = false;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _game = QuoridorGame(
      sessionId: widget.sessionId,
      isHost: widget.isHost,
      onGameOver: _handleGameOver,
    );
  }

  void _handleGameOver() {
    setState(() {
      _isGameOver = true;
    });
  }

  Future<void> _restartGame() async {
    if (widget.isHost) {
      final success = await _sessionService.restartSession(widget.sessionId);
      if (success) {
        setState(() {
          _isGameOver = false;
          _game = QuoridorGame(
            sessionId: widget.sessionId,
            isHost: widget.isHost,
            onGameOver: _handleGameOver,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Online Game - ${widget.isHost ? "Host" : "Guest"}'),
        actions: [
          if (widget.isHost)
            StreamBuilder<DocumentSnapshot>(
              stream: _db
                  .collection('game_sessions')
                  .doc(widget.sessionId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final isChatEnabled = data['isChatEnabled'] as bool? ?? false;

                return IconButton(
                  icon: Icon(
                    isChatEnabled ? Icons.chat : Icons.chat_bubble_outline,
                    color: isChatEnabled ? Colors.green : null,
                  ),
                  onPressed: () async {
                    await _sessionService.setChatEnabled(
                      widget.sessionId,
                      !isChatEnabled,
                    );
                  },
                  tooltip: isChatEnabled ? 'Disable Chat' : 'Enable Chat',
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          GameWidget(game: _game),
          GameChatWidget(
            sessionId: widget.sessionId,
            sessionService: _sessionService,
            game: _game,
          ),
          if (_isGameOver && widget.isHost)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: ElevatedButton(
                onPressed: _restartGame,
                child: const Text('Play Again'),
              ),
            ),
        ],
      ),
    );
  }
}
