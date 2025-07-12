# Online Multiplayer Guide for Quoridor

## 🎮 Overview

The online multiplayer functionality allows players to create rooms, invite friends, and play Quoridor together in real-time across different mobile devices using Firebase as the backend.

## 🚀 Getting Started

### 1. Prerequisites

Make sure you have the following dependencies in your `pubspec.yaml`:

```yaml
dependencies:
  flutter_bloc: ^8.1.3
  hydrated_bloc: ^9.1.3
  cloud_firestore: ^4.13.6
  firebase_auth: ^4.15.3
  firebase_core: ^2.24.2
```

### 2. Firebase Setup

1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Enable Firestore Database
3. Enable Anonymous Authentication
4. Download and add the configuration files:
   - `google-services.json` for Android
   - `GoogleService-Info.plist` for iOS
5. Update your Firebase security rules to allow read/write access

### 3. Firebase Security Rules

Add these rules to your Firestore database:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read/write access to game rooms
    match /game_rooms/{roomId} {
      allow read, write: if request.auth != null;
    }
    
    // Allow read/write access to online games
    match /online_games/{gameId} {
      allow read, write: if request.auth != null;
    }
    
    // Allow read/write access to regular games
    match /games/{gameId} {
      allow read, write: if request.auth != null;
    }
    
    // Allow read/write access to user statistics
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## 🎯 How to Use

### 1. Accessing Online Multiplayer

1. Open the Quoridor app
2. On the main menu, tap the **"Online Multiplayer"** button (green button with people icon)
3. You'll be taken to the online lobby

### 2. Creating a Room

1. In the online lobby, you'll see a "Create New Room" section
2. Enter a room name (e.g., "My Game Room")
3. Select the number of players (2-4)
4. Choose if you want the room to be private
5. Tap "Create Room"
6. You'll be taken to the room lobby where you can wait for other players

### 3. Joining a Room

#### Option A: Join by Room ID
1. In the online lobby, scroll to the "Join Room" section
2. Enter the room ID provided by the host
3. Tap "Join Room"

#### Option B: Join from Available Rooms
1. In the online lobby, scroll to the "Available Rooms" section
2. Browse the list of public rooms
3. Tap "Join" on any room that isn't full

### 4. Room Lobby

Once in a room:
1. **Set Ready Status**: Toggle the "I'm Ready" switch when you're ready to play
2. **Wait for Players**: All players must join and be ready
3. **Start Game**: The host can start the game when everyone is ready

### 5. Playing Online

During the game:
- **Turn-based**: Only the current player can make moves
- **Real-time Updates**: All moves are synchronized across devices
- **Chat**: Players can send messages (if implemented)
- **Leave Game**: Use the "Leave Game" button to exit

## 🔧 Technical Implementation

### Key Components

1. **OnlineGameService** (`lib/flame/services/online_game_service.dart`)
   - Handles Firebase operations
   - Manages room and game state
   - Provides real-time streams

2. **OnlineGameController** (`lib/flame/controller/online_game_controller.dart`)
   - Manages online game state
   - Handles events and user interactions
   - Coordinates with the service layer

3. **OnlineGameLobby** (`lib/flame/widgets/online/online_game_lobby.dart`)
   - UI for creating and joining rooms
   - Shows available rooms
   - Handles room management

4. **RoomLobbyScreen** (`lib/flame/widgets/online/room_lobby_screen.dart`)
   - UI for waiting in a room
   - Shows player status
   - Allows starting the game

5. **OnlineGameScreen** (`lib/flame/widgets/online/online_game_screen.dart`)
   - Main game interface for online play
   - Integrates with existing game board
   - Shows player information and chat

### Data Models

1. **RoomState** (`lib/flame/models/room_state.dart`)
   - Represents a game room
   - Contains player information
   - Manages room status

2. **RoomPlayer** (`lib/flame/models/room_state.dart`)
   - Represents a player in a room
   - Contains ready status and connection info

### Events and States

1. **OnlineGameEvent** (`lib/flame/controller/online_game_events.dart`)
   - Events for room management
   - Game move events
   - Player management events

2. **OnlineGameStates** (`lib/flame/controller/online_game_states.dart`)
   - States for different game phases
   - Error and loading states
   - Real-time state management

## 🎮 Game Flow

```
Main Menu → Online Lobby → Create/Join Room → Room Lobby → Game → Game Over
```

1. **Main Menu**: User selects "Online Multiplayer"
2. **Online Lobby**: User creates or joins a room
3. **Room Lobby**: Players wait and set ready status
4. **Game**: Real-time multiplayer gameplay
5. **Game Over**: Winner is determined, return to lobby

## 🔒 Security Features

- **Anonymous Authentication**: Players are authenticated anonymously
- **Room Privacy**: Private rooms require room ID to join
- **Turn Validation**: Only current player can make moves
- **Connection Monitoring**: Heartbeat system detects disconnections

## 🚨 Troubleshooting

### Common Issues

1. **"Failed to create room"**
   - Check Firebase connection
   - Verify authentication is enabled
   - Check Firestore security rules

2. **"Room not found"**
   - Verify room ID is correct
   - Room may have been deleted
   - Check if room is private

3. **"Not your turn"**
   - Wait for your turn
   - Check if you're the current player
   - Refresh the game state

4. **Connection Issues**
   - Check internet connection
   - Restart the app
   - Try rejoining the room

### Debug Mode

Enable debug logging by adding this to your main.dart:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable Firebase debug mode
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  
  runApp(MyApp());
}
```

## 🔮 Future Enhancements

Potential improvements for the online multiplayer system:

1. **User Accounts**: Replace anonymous auth with user accounts
2. **Friend System**: Add friends and invite them directly
3. **Chat System**: Real-time chat during games
4. **Spectator Mode**: Allow watching games without playing
5. **Tournaments**: Organize competitive tournaments
6. **Replay System**: Save and replay games
7. **Achievements**: Add achievements and leaderboards
8. **Custom Rules**: Allow custom game rules and settings

## 📱 Testing

To test the online multiplayer:

1. **Single Device**: Use the app normally
2. **Multiple Devices**: Install the app on different devices
3. **Emulator + Device**: Use Android emulator and physical device
4. **Cross Platform**: Test between iOS and Android

### Test Scenarios

1. **Room Creation**: Create rooms with different settings
2. **Player Joining**: Join rooms with room IDs
3. **Game Flow**: Complete full games from start to finish
4. **Disconnection**: Test what happens when players disconnect
5. **Reconnection**: Test reconnecting to ongoing games
6. **Edge Cases**: Test with maximum players, private rooms, etc.

## 📞 Support

If you encounter issues:

1. Check the Firebase Console for errors
2. Review the app logs for debugging information
3. Verify all dependencies are up to date
4. Test with a fresh Firebase project
5. Check network connectivity and firewall settings

---

**Happy Gaming! 🎲** 