import 'package:firebase_auth/firebase_auth.dart';

import '../constants.dart';

class RoomState {
  final String roomId;
  final String roomName;
  final List<RoomPlayer> players;
  final GameStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int maxPlayers;
  final bool isPrivate;
  final String? hostId;

  RoomState({
    required this.roomId,
    required this.roomName,
    required this.players,
    this.status = GameStatus.waiting,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.maxPlayers = 2,
    this.isPrivate = false,
    this.hostId,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isFull => players.length >= maxPlayers;
  bool get canStart => players.length >= 2 && players.every((p) => p.isReady);
  bool get isHost => hostId == FirebaseAuth.instance.currentUser?.uid;

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'roomName': roomName,
    'players': players.map((p) => p.toJson()).toList(),
    'status': status.index,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'maxPlayers': maxPlayers,
    'isPrivate': isPrivate,
    'hostId': hostId,
  };

  static RoomState fromJson(Map<String, dynamic> json) {
    return RoomState(
      roomId: json['roomId'],
      roomName: json['roomName'],
      players: (json['players'] as List)
          .map((p) => RoomPlayer.fromJson(p))
          .toList(),
      status: GameStatus.values[json['status'] as int],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      maxPlayers: json['maxPlayers'] as int? ?? 2,
      isPrivate: json['isPrivate'] as bool? ?? false,
      hostId: json['hostId'],
    );
  }
}

class RoomPlayer {
  final String userId;
  final String displayName;
  final int playerId;
  final bool isReady;
  final bool isOnline;
  final DateTime lastSeen;

  RoomPlayer({
    required this.userId,
    required this.displayName,
    required this.playerId,
    this.isReady = false,
    this.isOnline = true,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'playerId': playerId,
    'isReady': isReady,
    'isOnline': isOnline,
    'lastSeen': lastSeen.toIso8601String(),
  };

  static RoomPlayer fromJson(Map<String, dynamic> json) {
    return RoomPlayer(
      userId: json['userId'],
      displayName: json['displayName'],
      playerId: json['playerId'],
      isReady: json['isReady'] as bool? ?? false,
      isOnline: json['isOnline'] as bool? ?? true,
      lastSeen: DateTime.parse(json['lastSeen']),
    );
  }

  RoomPlayer copyWith({
    String? userId,
    String? displayName,
    int? playerId,
    bool? isReady,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return RoomPlayer(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      playerId: playerId ?? this.playerId,
      isReady: isReady ?? this.isReady,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
