import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quoridor/flame/services/game_session_service.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/widgets/online_game_widget.dart';

class OnlineGamePage extends StatefulWidget {
  const OnlineGamePage({super.key});

  @override
  State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage> {
  final GameSessionService _sessionService = GameSessionService();
  final TextEditingController _sessionIdController = TextEditingController();
  String? _currentSessionId;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showCopiedMessage = false;

  @override
  void dispose() {
    _sessionIdController.dispose();
    super.dispose();
  }

  Future<void> _copySessionId() async {
    if (_currentSessionId != null) {
      await Clipboard.setData(ClipboardData(text: _currentSessionId!));
      setState(() {
        _showCopiedMessage = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showCopiedMessage = false;
          });
        }
      });
    }
  }

  Future<void> _createNewSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Create initial game state
      final initialState = GameStateFactory.createNewGame();
      final sessionId = await _sessionService.createSession();

      setState(() {
        _currentSessionId = sessionId;
        _isLoading = false;
      });

      // Show the session ID before navigating to the game
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Game Created!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share this session ID with your friend:'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentSessionId!,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: _copySessionId,
                        tooltip: 'Copy to clipboard',
                      ),
                    ],
                  ),
                ),
                if (_showCopiedMessage)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Copied to clipboard!',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OnlineGameWidget(
                        sessionId: _currentSessionId!,
                        isHost: true,
                      ),
                    ),
                  );
                },
                child: const Text('Start Game'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to create session: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _joinSession() async {
    final sessionId = _sessionIdController.text.trim();
    if (sessionId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a session ID';
      });
      return;
    }

    // Validate session ID format
    if (!_sessionService.isValidSessionId(sessionId)) {
      setState(() {
        _errorMessage =
            'Invalid session ID format. Please enter a 5-digit number (10001-99999)';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isJoinable = await _sessionService.isSessionJoinable(sessionId);
      if (!isJoinable) {
        setState(() {
          _errorMessage = 'Session not found or not joinable';
          _isLoading = false;
        });
        return;
      }

      final success = await _sessionService.joinSession(sessionId);
      if (!success) {
        setState(() {
          _errorMessage = 'Failed to join session';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _currentSessionId = sessionId;
        _isLoading = false;
      });

      // Navigate to game with the session ID
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                OnlineGameWidget(sessionId: sessionId, isHost: false),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error joining session: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Online Game')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: _isLoading ? null : _createNewSession,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Create New Game'),
            ),
            const SizedBox(height: 32),
            const Text('OR', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 32),
            TextField(
              controller: _sessionIdController,
              decoration: const InputDecoration(
                labelText: 'Enter Session ID',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _joinSession,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Join Game'),
            ),
          ],
        ),
      ),
    );
  }
}
