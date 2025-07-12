import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../controller/online_game_controller.dart';
import '../../controller/online_game_events.dart';
import '../../controller/online_game_states.dart';
import '../../models/room_state.dart';
import '../../services/online_game_service.dart';
import 'online_game_screen.dart';

class RoomLobbyScreen extends StatefulWidget {
  final RoomState roomState;

  const RoomLobbyScreen({super.key, required this.roomState});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    // Set initial ready status
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _isReady = widget.roomState.players
          .firstWhere(
            (p) => p.userId == currentUser.uid,
            orElse: () => widget.roomState.players.first,
          )
          .isReady;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomState.roomName}'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _leaveRoom,
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Leave Room',
          ),
        ],
      ),
      body: BlocConsumer<OnlineGameController, OnlineGameStates>(
        listener: (context, state) {
          if (state is OnlineGameErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error), backgroundColor: Colors.red),
            );
          } else if (state is OnlineGamePlayingState) {
            // Navigate to online game screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => OnlineGameScreen()),
            );
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

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      _buildRoomInfo(),
                      const SizedBox(height: 24),
                      _buildPlayersList(),
                      const SizedBox(height: 24),
                      _buildReadySection(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildStartButton(state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRoomInfo() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.room, color: Colors.blue[700], size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.roomState.roomName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
                if (widget.roomState.isPrivate)
                  const Chip(
                    label: Text('Private'),
                    backgroundColor: Colors.orange,
                    labelStyle: TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Room ID: ${widget.roomState.roomId}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Players: ${widget.roomState.players.length}/${widget.roomState.maxPlayers}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersList() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            ...widget.roomState.players.map(
              (player) => _buildPlayerTile(player),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerTile(RoomPlayer player) {
    final isHost = widget.roomState.hostId == player.userId;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMe = currentUser != null && player.userId == currentUser.uid;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isMe ? Colors.blue[50] : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getPlayerColor(player.playerId),
          child: Text(
            player.playerId.toString(),
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
                player.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isHost)
              const Chip(
                label: Text('Host'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white, fontSize: 10),
              ),
            if (isMe)
              const Chip(
                label: Text('You'),
                backgroundColor: Colors.blue,
                labelStyle: TextStyle(color: Colors.white, fontSize: 10),
              ),
          ],
        ),
        subtitle: Text(
          player.isReady ? 'Ready' : 'Not Ready',
          style: TextStyle(
            color: player.isReady ? Colors.green : Colors.red,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: player.isReady
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.schedule, color: Colors.orange),
      ),
    );
  }

  Widget _buildReadySection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ready Status',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('I\'m Ready'),
              subtitle: Text(_isReady ? 'Ready to play!' : 'Click when ready'),
              value: _isReady,
              onChanged: (value) async {
                setState(() {
                  _isReady = value;
                });
                // Update ready status directly using the service
                try {
                  await OnlineGameService.setPlayerReady(value);
                } catch (e) {
                  // Revert the UI state if the service call fails
                  if (mounted) {
                    setState(() {
                      _isReady = !value;
                    });
                  }
                  // Only show error if widget is still mounted and context is valid
                  if (mounted && context.mounted) {
                    try {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating ready status: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } catch (scaffoldError) {
                      // If we can't show snackbar, just print the error
                      print('Error updating ready status: $e');
                    }
                  }
                }
              },
              activeColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton(OnlineGameStates state) {
    final isHost = widget.roomState.isHost;
    final canStart = widget.roomState.canStart;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isHost && canStart)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startGame,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Game'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              )
            else if (isHost && !canStart)
              const Card(
                color: Colors.orange,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Waiting for all players to be ready',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Card(
                color: Colors.blue,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Waiting for host to start the game',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _leaveRoom,
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Leave Room'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
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

  void _startGame() {
    context.read<OnlineGameController>().add(StartOnlineGame());
  }

  void _leaveRoom() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Room'),
        content: const Text('Are you sure you want to leave this room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Leave the room directly using the service
              try {
                await OnlineGameService.leaveRoom();
                if (mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                // Only show error if widget is still mounted and context is valid
                if (mounted && context.mounted) {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error leaving room: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } catch (scaffoldError) {
                    // If we can't show snackbar, just print the error
                    print('Error leaving room: $e');
                  }
                }
              }
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}
