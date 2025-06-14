import 'package:flutter/material.dart';
import 'package:quoridor/flame/services/game_session_service.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';

class GameChatWidget extends StatefulWidget {
  final String sessionId;
  final GameSessionService sessionService;
  final QuoridorGame game;

  const GameChatWidget({
    Key? key,
    required this.sessionId,
    required this.sessionService,
    required this.game,
  }) : super(key: key);

  @override
  State<GameChatWidget> createState() => _GameChatWidgetState();
}

class _GameChatWidgetState extends State<GameChatWidget> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _showChatSheet = false;
  bool _isChatEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkChatStatus();
    _listenToMessages();
  }

  Future<void> _checkChatStatus() async {
    final isEnabled = await widget.sessionService.isChatEnabled(
      widget.sessionId,
    );
    setState(() {
      _isChatEnabled = isEnabled;
    });
  }

  void _listenToMessages() {
    widget.sessionService.streamChatMessages(widget.sessionId).listen((
      messages,
    ) {
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
      });
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty && _isChatEnabled) {
      widget.sessionService.sendChatMessage(
        widget.sessionId,
        _messageController.text.trim(),
      );
      _messageController.clear();
    }
  }

  void _sendEmoji(String emoji) {
    if (_isChatEnabled) {
      widget.sessionService.sendChatMessage(widget.sessionId, '', emoji: emoji);
      // Show emoji animation in the game
      widget.game.showEmojiAnimation(emoji);
    }
  }

  void _showChatHistory() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: double.maxFinite,
          height: 400,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Chat History',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                message['playerName'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (message['emoji'] != null)
                                Text(
                                  message['emoji'] as String,
                                  style: const TextStyle(fontSize: 20),
                                ),
                            ],
                          ),
                          if (message['message']?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(message['message'] as String),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isChatEnabled) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Messages at the top
        if (_messages.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: _messages.take(3).map((message) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message['emoji'] != null)
                          Text(
                            message['emoji'],
                            style: const TextStyle(fontSize: 20),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          '${message['playerName']}: ${message['message']}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

        // Floating action button
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            mini: true,
            onPressed: _showChatHistory,
            child: const Icon(Icons.chat),
          ),
        ),

        // Chat bottom sheet
        if (_showChatSheet)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Emoji row
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () => _sendEmoji('😊'),
                          icon: const Text('😊'),
                        ),
                        IconButton(
                          onPressed: () => _sendEmoji('😂'),
                          icon: const Text('😂'),
                        ),
                        IconButton(
                          onPressed: () => _sendEmoji('😡'),
                          icon: const Text('😡'),
                        ),
                        IconButton(
                          onPressed: () => _sendEmoji('👍'),
                          icon: const Text('👍'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // Message input
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: const InputDecoration(
                              hintText: 'Type a message...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
