import '../../flame/constants.dart';
import 'player.dart';

class GameState {
  final String gameId;

  /// Everyone at the board, in seat order.
  ///
  /// Two entries for the classic game, three or four for the bigger ones.
  /// Nothing outside this list decides how many are playing.
  final List<Player> players;

  final List<Wall> walls;
  int currentPlayerId;
  GameStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<GameMove> moveHistory;

  GameState({
    required this.gameId,
    required this.players,
    List<Wall>? walls,
    this.currentPlayerId = 1,
    this.status = GameStatus.playing,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GameMove>? moveHistory,
  }) : walls = walls ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       moveHistory = moveHistory ?? [];

  /// How many are playing.
  int get playerCount => players.length;

  /// This state with the given parts replaced, keeping every seat.
  ///
  /// Copying used to be written out by hand at each call site, naming the
  /// first two players — which quietly dropped seats three and four the
  /// moment they existed, and left a three-player game playing as two.
  /// Going through here means a copy cannot lose anybody.
  GameState copyWith({
    List<Player>? players,
    List<Wall>? walls,
    int? currentPlayerId,
    GameStatus? status,
    DateTime? updatedAt,
    List<GameMove>? moveHistory,
    bool clonePlayers = false,
  }) => GameState(
    gameId: gameId,
    players:
        players ??
        (clonePlayers
            ? [for (final player in this.players) player.copyWith()]
            : this.players),
    walls: walls ?? List<Wall>.of(this.walls),
    currentPlayerId: currentPlayerId ?? this.currentPlayerId,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    moveHistory: moveHistory ?? List<GameMove>.of(this.moveHistory),
  );

  /// The first two seats, which the two-player game is written in terms of.
  Player get player1 => players[0];
  Player get player2 => players[1];

  Player get currentPlayer => playerById(currentPlayerId);

  /// The seat after [currentPlayerId], which in a two-player game is the
  /// opponent. With more players this is simply whoever is next to move.
  Player get otherPlayer => playerById(nextPlayerId);

  /// Everyone except [id].
  List<Player> opponentsOf(int id) =>
      players.where((player) => player.id != id).toList();

  Player playerById(int id) => players.firstWhere((player) => player.id == id);

  /// Whose turn it is after this one, going round the table in seat order.
  int get nextPlayerId {
    final index = players.indexWhere((player) => player.id == currentPlayerId);
    return players[(index + 1) % players.length].id;
  }

  bool get isGameOver => status != GameStatus.playing;

  /// The seat that won, or null while the game is still on.
  int? get winnerId {
    for (final player in players) {
      if (status == GameStatus.wonBy(player.id)) return player.id;
    }
    return null;
  }

  String? get winner {
    final id = winnerId;
    return id == null ? null : playerById(id).name;
  }

  void switchTurn() {
    currentPlayerId = nextPlayerId;
    updatedAt = DateTime.now();
  }

  void addWall(Wall wall) {
    walls.add(wall);
    currentPlayer.useWall();
    updatedAt = DateTime.now();
  }

  void movePawn(Position newPosition) {
    currentPlayer.moveTo(newPosition);
    updatedAt = DateTime.now();
  }

  void checkWinCondition() {
    for (final player in players) {
      if (player.hasReachedGoal) {
        status = GameStatus.wonBy(player.id);
        break;
      }
    }
    updatedAt = DateTime.now();
  }

  void addMoveToHistory(GameMove move) {
    moveHistory.add(move);
    updatedAt = DateTime.now();
  }

  bool isPositionOccupied(Position position) =>
      players.any((player) => player.position == position);

  bool isWallBlocking(Position from, Position to) {
    // Check if there's a wall blocking movement between two adjacent positions
    for (final wall in walls) {
      if (_wallBlocksMovement(wall, from, to)) {
        return true;
      }
    }
    return false;
  }

  bool _wallBlocksMovement(Wall wall, Position from, Position to) {
    final wallRow = wall.position.row;
    final wallCol = wall.position.col;

    if (wall.orientation == WallOrientation.horizontal) {
      // Horizontal wall blocks vertical movement
      if (from.col == to.col) {
        final maxRow = from.row < to.row ? to.row : from.row;

        return wallRow == maxRow &&
            wallCol <= from.col &&
            wallCol + 1 >= from.col;
      }
    } else {
      // Vertical wall blocks horizontal movement
      if (from.row == to.row) {
        final maxCol = from.col < to.col ? to.col : from.col;

        return wallCol == maxCol &&
            wallRow <= from.row &&
            wallRow + 1 >= from.row;
      }
    }

    return false;
  }

  List<Position> getValidMoves(Position position) {
    final validMoves = <Position>[];
    final directions = [
      Position(-1, 0), // Up
      Position(1, 0), // Down
      Position(0, -1), // Left
      Position(0, 1), // Right
    ];

    for (final direction in directions) {
      final newPos = Position(
        position.row + direction.row,
        position.col + direction.col,
      );

      // Check bounds
      if (newPos.row < 0 ||
          newPos.row >= GameConstants.boardSize ||
          newPos.col < 0 ||
          newPos.col >= GameConstants.boardSize) {
        continue;
      }

      // Check wall blocking
      if (isWallBlocking(position, newPos)) {
        continue;
      }

      // Check if position is occupied
      if (isPositionOccupied(newPos)) {
        // Check for jump moves
        final jumpPos = Position(
          newPos.row + direction.row,
          newPos.col + direction.col,
        );

        // Jump over opponent if possible
        if (jumpPos.row >= 0 &&
            jumpPos.row < GameConstants.boardSize &&
            jumpPos.col >= 0 &&
            jumpPos.col < GameConstants.boardSize &&
            !isWallBlocking(newPos, jumpPos) &&
            !isPositionOccupied(jumpPos)) {
          validMoves.add(jumpPos);
        } else {
          // Diagonal jump if blocked behind
          final diagonalMoves = [
            Position(newPos.row - 1, newPos.col), // Up from opponent
            Position(newPos.row + 1, newPos.col), // Down from opponent
            Position(newPos.row, newPos.col - 1), // Left from opponent
            Position(newPos.row, newPos.col + 1), // Right from opponent
          ];

          for (final diagPos in diagonalMoves) {
            if (diagPos.row >= 0 &&
                diagPos.row < GameConstants.boardSize &&
                diagPos.col >= 0 &&
                diagPos.col < GameConstants.boardSize &&
                !isWallBlocking(newPos, diagPos) &&
                !isPositionOccupied(diagPos)) {
              validMoves.add(diagPos);
            }
          }
        }
      } else {
        validMoves.add(newPos);
      }
    }

    return validMoves;
  }

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'players': players.map((p) => p.toJson()).toList(),
    // Still written so a save from this build opens in an older one.
    'player1': player1.toJson(),
    'player2': player2.toJson(),
    'walls': walls.map((w) => w.toJson()).toList(),
    'currentPlayerId': currentPlayerId,
    'status': status.index,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'moveHistory': moveHistory.map((m) => m.toJson()).toList(),
  };

  static GameState fromJson(Map<String, dynamic> json) => GameState(
    gameId: json['gameId'] as String,
    players: _playersFrom(json),
    walls: (json['walls'] as List).map((w) => Wall.fromJson(w)).toList(),
    currentPlayerId: json['currentPlayerId'] as int,
    status: GameStatus.values[json['status'] as int],
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
    moveHistory: (json['moveHistory'] as List)
        .map((m) => GameMove.fromJson(m))
        .toList(),
  );

  /// Reads the seats, falling back to the two a game saved before three and
  /// four existed carries instead.
  static List<Player> _playersFrom(Map<String, dynamic> json) {
    final listed = json['players'] as List?;
    if (listed != null && listed.isNotEmpty) {
      return listed
          .map((p) => Player.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return [
      Player.fromJson(json['player1'] as Map<String, dynamic>),
      Player.fromJson(json['player2'] as Map<String, dynamic>),
    ];
  }
}

// Factory for creating new games
class GameStateFactory {
  static GameState createNewGame({
    String? gameId,
    String player1Name = 'Player 1',
    String player2Name = 'AI',
    bool player2IsAI = true,
    int playerCount = 2,
  }) {
    gameId ??= 'game_${DateTime.now().millisecondsSinceEpoch}';

    return GameState(
      gameId: gameId,
      players: [
        PlayerFactory.seat(1, name: player1Name, playerCount: playerCount),
        PlayerFactory.seat(
          2,
          name: player2Name,
          isAI: player2IsAI,
          playerCount: playerCount,
        ),
        for (var seat = 3; seat <= playerCount; seat++)
          PlayerFactory.seat(seat, playerCount: playerCount),
      ],
    );
  }
}
