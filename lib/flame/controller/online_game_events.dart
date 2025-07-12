import '../models/room_state.dart';
import '../models/game_state.dart';
import '../constants.dart';

// Online game events
abstract class OnlineGameEvent {}

// Create a new room
class CreateRoom extends OnlineGameEvent {
  final String roomName;
  final int maxPlayers;
  final bool isPrivate;

  CreateRoom({
    required this.roomName,
    this.maxPlayers = 2,
    this.isPrivate = false,
  });
}

// Join an existing room
class JoinRoom extends OnlineGameEvent {
  final String roomId;

  JoinRoom(this.roomId);
}

// Leave current room
class LeaveRoom extends OnlineGameEvent {}

// Set player ready status
class SetPlayerReady extends OnlineGameEvent {
  final bool isReady;

  SetPlayerReady(this.isReady);
}

// Start the game
class StartOnlineGame extends OnlineGameEvent {}

// Make a move in online game
class MakeOnlineMove extends OnlineGameEvent {
  final GameMove move;

  MakeOnlineMove(this.move);
}

// Watch room state
class WatchRoom extends OnlineGameEvent {
  final String roomId;

  WatchRoom(this.roomId);
}

// Watch game state
class WatchGame extends OnlineGameEvent {
  final String gameId;

  WatchGame(this.gameId);
}

// Get available rooms
class GetAvailableRooms extends OnlineGameEvent {}

// Connect to online game
class ConnectToOnlineGame extends OnlineGameEvent {
  final String gameId;
  final int playerId;

  ConnectToOnlineGame({required this.gameId, required this.playerId});
}

// Disconnect from online game
class DisconnectFromOnlineGame extends OnlineGameEvent {}

// Update player status
class UpdatePlayerStatus extends OnlineGameEvent {
  final bool isOnline;
  final DateTime lastSeen;

  UpdatePlayerStatus({required this.isOnline, required this.lastSeen});
}

// Send chat message
class SendChatMessage extends OnlineGameEvent {
  final String message;

  SendChatMessage(this.message);
}

// Kick player from room
class KickPlayer extends OnlineGameEvent {
  final String playerId;

  KickPlayer(this.playerId);
}

// Transfer room ownership
class TransferOwnership extends OnlineGameEvent {
  final String newHostId;

  TransferOwnership(this.newHostId);
}

// Update room settings
class UpdateRoomSettings extends OnlineGameEvent {
  final String roomName;
  final int maxPlayers;
  final bool isPrivate;

  UpdateRoomSettings({
    required this.roomName,
    required this.maxPlayers,
    required this.isPrivate,
  });
}
