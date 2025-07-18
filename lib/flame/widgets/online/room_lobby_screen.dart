import 'dart:async';

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
  bool _isStartingGame = false;
  Stream<RoomState>? _roomStream;

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

    // Create a single stream instance to share
    final roomId = widget.roomState.roomId;
    if (roomId.isNotEmpty) {
      print('DEBUG: Creating shared stream for room: $roomId');
      _roomStream = OnlineGameService.watchRoom(roomId);
    }

    print('DEBUG: RoomLobbyScreen initialized with StreamBuilder approach');
  }

  @override
  Widget build(BuildContext context) {
    if (_roomStream == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Room: ${widget.roomState.roomName}'),
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Error: No room stream available')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<RoomState>(
          stream: _roomStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Room: ${widget.roomState.roomName} (Error)');
            }
            if (!snapshot.hasData) {
              return Text('Room: ${widget.roomState.roomName}');
            }
            return Text('Room: ${snapshot.data!.roomName}');
          },
        ),
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
          print('DEBUG: RoomLobbyScreen received state: ${state.runtimeType}');

          if (state is OnlineGameErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error), backgroundColor: Colors.red),
            );
          } else if (state is OnlineGameLoadingState &&
              state.message.contains('start')) {
            // Game is starting
            setState(() {
              _isStartingGame = true;
            });
          } else if (state is OnlineGamePlayingState) {
            // Navigate to online game screen with the same controller
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => BlocProvider.value(
                  value: context.read<OnlineGameController>(),
                  child: const OnlineGameScreen(),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          return StreamBuilder<RoomState>(
            stream: _roomStream,
            builder: (context, snapshot) {
              print(
                'DEBUG: StreamBuilder update - hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}',
              );
              print(
                'DEBUG: StreamBuilder connection state: ${snapshot.connectionState}',
              );
              if (snapshot.hasError) {
                print('DEBUG: StreamBuilder error: ${snapshot.error}');
              }

              if (snapshot.hasError) {
                print('DEBUG: StreamBuilder error: ${snapshot.error}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 64),
                      const SizedBox(height: 16),
                      Text('Error: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData) {
                print('DEBUG: StreamBuilder waiting for data...');
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading room...'),
                    ],
                  ),
                );
              }

              final roomState = snapshot.data!;
              print(
                'DEBUG: StreamBuilder received room state: ${roomState.roomName}',
              );
              print('DEBUG: Players count: ${roomState.players.length}');
              print('DEBUG: Can start: ${roomState.canStart}');

              // Check if current user is still in the room
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser != null) {
                final isInRoom = roomState.players.any(
                  (p) => p.userId == currentUser.uid,
                );

                if (!isInRoom) {
                  print(
                    'DEBUG: Current user is no longer in the room, navigating back',
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You were removed from the room'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      Navigator.pop(context);
                    }
                  });
                  return const Center(
                    child: Text('You were removed from the room'),
                  );
                }

                // Update ready status based on current user
                try {
                  final myPlayer = roomState.players.firstWhere(
                    (p) => p.userId == currentUser.uid,
                    orElse: () => roomState.players.first,
                  );
                  if (_isReady != myPlayer.isReady) {
                    print(
                      'DEBUG: Updating ready status from ${_isReady} to ${myPlayer.isReady}',
                    );
                    setState(() {
                      _isReady = myPlayer.isReady;
                    });
                  }
                } catch (e) {
                  print('DEBUG: Error finding my player: $e');
                }
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          _buildRoomInfo(roomState),
                          const SizedBox(height: 24),
                          _buildPlayersList(roomState),
                          const SizedBox(height: 24),
                          _buildReadySection(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStartButton(state, roomState),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRoomInfo(RoomState roomState) {
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
                    roomState.roomName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
                if (roomState.isPrivate)
                  const Chip(
                    label: Text('Private'),
                    backgroundColor: Colors.orange,
                    labelStyle: TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Room ID: ${roomState.roomId}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Players: ${roomState.players.length}/${roomState.maxPlayers}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersList(RoomState roomState) {
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
            ...roomState.players.map(
              (player) => _buildPlayerTile(player, roomState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerTile(RoomPlayer player, RoomState roomState) {
    final isHost = roomState.hostId == player.userId;
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
                print('DEBUG: Ready switch changed to: $value');
                setState(() {
                  _isReady = value;
                });
                // Update ready status directly using the service
                try {
                  print(
                    'DEBUG: Calling OnlineGameService.setPlayerReady($value)',
                  );
                  await OnlineGameService.setPlayerReady(value);
                  print('DEBUG: setPlayerReady completed successfully');
                } catch (e) {
                  print('DEBUG: Error in setPlayerReady: $e');
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

  Widget _buildStartButton(OnlineGameStates state, RoomState roomState) {
    final isHost = roomState.isHost;
    final canStart = roomState.canStart;

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
                  onPressed: _isStartingGame ? null : _startGame,
                  icon: _isStartingGame
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isStartingGame ? 'Starting...' : 'Start Game'),
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
    try {
      print('DEBUG: Starting game...');

      // Set the flag immediately to prevent multiple taps
      setState(() {
        _isStartingGame = true;
      });

      final controller = context.read<OnlineGameController>();
      print('DEBUG: Controller state: ${controller.state.runtimeType}');
      print('DEBUG: Controller is closed: ${controller.isClosed}');

      // Check if the controller is still active
      if (!controller.isClosed) {
        print('DEBUG: Adding StartOnlineGame event to controller');
        controller.add(StartOnlineGame());
      } else {
        print('DEBUG: Controller is closed, cannot start game');
        // Reset the flag if controller is closed
        setState(() {
          _isStartingGame = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot start game - controller is closed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error starting game: $e');
      // Reset the flag on error
      setState(() {
        _isStartingGame = false;
      });
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
              print('DEBUG: Leaving room...');

              // Leave the room directly using the service
              try {
                await OnlineGameService.leaveRoom();
                print('DEBUG: Successfully left room');
                if (mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                print('DEBUG: Error leaving room: $e');
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
