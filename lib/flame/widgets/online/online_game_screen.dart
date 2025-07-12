import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../controller/online_game_controller.dart';
import '../../controller/online_game_events.dart';
import '../../controller/online_game_states.dart';
import '../../constants.dart';
import '../game/game_board.dart';

class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({super.key});

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Game'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showGameInfo,
            icon: const Icon(Icons.info),
            tooltip: 'Game Info',
          ),
          IconButton(
            onPressed: _leaveGame,
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Leave Game',
          ),
        ],
      ),
      body: BlocConsumer<OnlineGameController, OnlineGameStates>(
        listener: (context, state) {
          if (state is OnlineGameErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error), backgroundColor: Colors.red),
            );
          } else if (state is OnlineGameOverState) {
            _showGameOverDialog(state);
          } else if (state is OnlineGameDisconnectedState) {
            _showDisconnectedDialog(state);
          }
        },
        builder: (context, state) {
          if (state is OnlineGameLoadingState) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(state.message),
                ],
              ),
            );
          }

          if (state is OnlineGamePlayingState) {
            return _buildGameLayout(state);
          }

          return const Center(child: Text('Waiting for game to start...'));
        },
      ),
    );
  }

  Widget _buildGameLayout(OnlineGamePlayingState state) {
    return Column(
      children: [
        _buildGameHeader(state),
        Expanded(
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildGameBoard(state)),
              if (MediaQuery.of(context).size.width > 800)
                Expanded(flex: 1, child: _buildSidePanel(state)),
            ],
          ),
        ),
        _buildGameControls(state),
      ],
    );
  }

  Widget _buildGameHeader(OnlineGamePlayingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room: ${state.roomState.roomName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Current Turn: ${state.gameState.currentPlayer.name}',
                  style: TextStyle(
                    fontSize: 14,
                    color: state.isMyTurn ? Colors.green : Colors.grey,
                    fontWeight: state.isMyTurn
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (state.currentMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                state.currentMessage!,
                style: TextStyle(color: Colors.blue[700], fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGameBoard(OnlineGamePlayingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ValueListenableBuilder(
                valueListenable: cellSizeNotifier,
                builder: (context, value, child) {
                  return SizedBox(
                    width:
                        (value + GameConstants.cellSpacing) *
                            GameConstants.boardSize +
                        GameConstants.boardPadding * 2,
                    height:
                        (value + GameConstants.cellSpacing) *
                            GameConstants.boardSize +
                        GameConstants.boardPadding * 2,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Game Board\n(Online Mode)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(OnlineGamePlayingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Players',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: state.gameState.players.length,
              itemBuilder: (context, index) {
                final player = state.gameState.players[index];
                final isCurrentPlayer =
                    player.id == state.gameState.currentPlayerId;
                final isMe = player.id == state.myPlayerId;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: isCurrentPlayer ? Colors.blue[50] : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getPlayerColor(player.id),
                      child: Text(
                        player.id.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            player.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isMe)
                          const Chip(
                            label: Text('You'),
                            backgroundColor: Colors.blue,
                            labelStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        if (isCurrentPlayer)
                          const Icon(Icons.play_arrow, color: Colors.green),
                      ],
                    ),
                    subtitle: Text(
                      'Walls: ${player.wallsRemaining}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (state.chatMessages.isNotEmpty) ...[
            Text(
              'Chat',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: state.chatMessages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        state.chatMessages[index],
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGameControls(OnlineGamePlayingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Row(
        children: [
          if (state.isMyTurn) ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _toggleValidMoves,
                icon: Icon(
                  state.showValidMoves
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                label: Text(
                  state.showValidMoves
                      ? 'Hide Valid Moves'
                      : 'Show Valid Moves',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _leaveGame,
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Leave Game'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPlayerColor(int playerId) {
    switch (playerId) {
      case 1:
        return const Color(0xFF6F61EF);
      case 2:
        return const Color(0xFF006400);
      case 3:
        return const Color(0xFFE74C3C);
      case 4:
        return const Color(0xFFF39C12);
      default:
        return Colors.grey;
    }
  }

  void _onPawnMove(Position position) {
    final currentState = context.read<OnlineGameController>().state;
    if (currentState is OnlineGamePlayingState) {
      context.read<OnlineGameController>().add(
        MakeOnlineMove(GameMove.pawnMove(position, currentState.myPlayerId)),
      );
    }
  }

  void _onWallPlace(Wall wall) {
    final currentState = context.read<OnlineGameController>().state;
    if (currentState is OnlineGamePlayingState) {
      context.read<OnlineGameController>().add(
        MakeOnlineMove(GameMove.wallPlace(wall, currentState.myPlayerId)),
      );
    }
  }

  void _onWallPreview(Wall? wall) {
    // Handle wall preview if needed
  }

  void _toggleValidMoves() {
    // This would toggle valid moves display
    // Implementation depends on your existing game logic
  }

  void _showGameInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Game Info'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Click on a valid position to move your pawn'),
            Text('• Click on wall positions to place walls'),
            Text('• Be the first to reach the opposite side'),
            Text('• You can block other players with walls'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _leaveGame() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Game'),
        content: const Text('Are you sure you want to leave this game?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<OnlineGameController>().add(LeaveRoom());
              Navigator.pop(context);
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog(OnlineGameOverState state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Game Over!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Winner: ${state.winner}'),
            const SizedBox(height: 8),
            Text('Total Moves: ${state.totalMoves}'),
            Text('Duration: ${_formatDuration(state.gameDuration)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<OnlineGameController>().add(LeaveRoom());
              Navigator.pop(context);
            },
            child: const Text('Back to Lobby'),
          ),
        ],
      ),
    );
  }

  void _showDisconnectedDialog(OnlineGameDisconnectedState state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Disconnected'),
        content: Text('You have been disconnected: ${state.reason}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<OnlineGameController>().add(LeaveRoom());
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }
}
