import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../controller/online_game_controller.dart';
import '../../controller/online_game_events.dart';
import '../../controller/online_game_states.dart';
import '../../models/room_state.dart';
import 'room_lobby_screen.dart';

class OnlineGameLobby extends StatefulWidget {
  const OnlineGameLobby({super.key});

  @override
  State<OnlineGameLobby> createState() => _OnlineGameLobbyState();
}

class _OnlineGameLobbyState extends State<OnlineGameLobby> {
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  int _selectedPlayerCount = 2;
  bool _isPrivate = false;

  @override
  void initState() {
    super.initState();
    print('DEBUG: OnlineGameLobby initState called');
    // Load available rooms when screen opens
    try {
      print('DEBUG: Trying to read OnlineGameController');
      context.read<OnlineGameController>().add(GetAvailableRooms());
      print('DEBUG: Successfully added GetAvailableRooms event');
    } catch (e) {
      print('DEBUG: Error reading OnlineGameController: $e');
    }
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Multiplayer'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: BlocConsumer<OnlineGameController, OnlineGameStates>(
        listener: (context, state) {
          print('DEBUG: OnlineGameLobby received state: ${state.runtimeType}');

          if (state is OnlineGameErrorState) {
            print('DEBUG: Error state: ${state.error}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error), backgroundColor: Colors.red),
            );
          } else if (state is RoomLobbyState) {
            print(
              'DEBUG: RoomLobbyState received, navigating to RoomLobbyScreen',
            );
            // Get the controller before navigation
            final controller = context.read<OnlineGameController>();
            // Navigate to room lobby with the same controller
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => BlocProvider.value(
                  value: controller,
                  child: RoomLobbyScreen(roomState: state.roomState),
                ),
              ),
            );
          } else if (state is WaitingForPlayersState) {
            print('DEBUG: WaitingForPlayersState received');
          } else if (state is OnlineGameLoadingState) {
            print('DEBUG: Loading state: ${state.message}');
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCreateRoomSection(),
                const SizedBox(height: 32),
                _buildJoinRoomSection(),
                const SizedBox(height: 32),
                _buildAvailableRoomsSection(state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCreateRoomSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create New Room',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(
                labelText: 'Room Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.room),
              ),
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                DropdownButtonFormField<int>(
                  value: _selectedPlayerCount,
                  decoration: const InputDecoration(
                    labelText: 'Max Players',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.people),
                  ),
                  items: [2, 3, 4].map((count) {
                    return DropdownMenuItem(
                      value: count,
                      child: Text('$count Players'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedPlayerCount = value!;
                    });
                  },
                ),
                const SizedBox(width: 16),
                SwitchListTile(
                  title: const Text('Private'),
                  subtitle: const Text('Invite only'),
                  value: _isPrivate,
                  onChanged: (value) {
                    setState(() {
                      _isPrivate = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _createRoom,
                icon: const Icon(Icons.add),
                label: const Text('Create Room'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinRoomSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Join Room',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _roomIdController,
              decoration: const InputDecoration(
                labelText: 'Room ID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
                hintText: 'Enter room ID to join',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _joinRoom,
                icon: const Icon(Icons.login),
                label: const Text('Join Room'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableRoomsSection(OnlineGameStates state) {
    List<RoomState> availableRooms = [];
    bool isLoading = false;

    if (state is RoomSelectionState) {
      availableRooms = state.availableRooms;
      isLoading = state.isLoading;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Available Rooms',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    context.read<OnlineGameController>().add(
                      GetAvailableRooms(),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (availableRooms.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No rooms available\nCreate a new room to get started!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: availableRooms.length,
                  itemBuilder: (context, index) {
                    final room = availableRooms[index];
                    return _buildRoomCard(room);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(RoomState room) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue[100],
          child: Text(
            '${room.players.length}/${room.maxPlayers}',
            style: TextStyle(
              color: Colors.blue[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          room.roomName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Host: ${room.players.first.displayName}'),
            Text('Created: ${_formatDate(room.createdAt)}'),
            if (room.isPrivate)
              const Chip(
                label: Text('Private'),
                backgroundColor: Colors.orange,
                labelStyle: TextStyle(color: Colors.white, fontSize: 12),
              ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: room.isFull ? null : () => _joinSpecificRoom(room.roomId),
          child: Text(room.isFull ? 'Full' : 'Join'),
        ),
      ),
    );
  }

  void _createRoom() {
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a room name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    context.read<OnlineGameController>().add(
      CreateRoom(
        roomName: roomName,
        maxPlayers: _selectedPlayerCount,
        isPrivate: _isPrivate,
      ),
    );
  }

  void _joinRoom() {
    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a room ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    context.read<OnlineGameController>().add(JoinRoom(roomId));
  }

  void _joinSpecificRoom(String roomId) {
    context.read<OnlineGameController>().add(JoinRoom(roomId));
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
