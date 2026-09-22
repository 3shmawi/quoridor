import '../../flame/constants.dart';
import '../../flame/game/pathfinding.dart';
import '../../flame/models/game_state.dart';
import '../../flame/models/player.dart';
import 'ai_service.dart';

class GameService {
  // Validate if a move is legal
  static bool isValidMove(GameState gameState, GameMove move) {
    final player = move.playerId == 1 ? gameState.player1 : gameState.player2;

    if (move.type == MoveType.pawnMove) {
      return _isValidPawnMove(gameState, player, move.newPosition!);
    } else {
      return _isValidWallPlacement(gameState, player, move.wall!);
    }
  }

  // Execute a validated move
  static GameState executeMove(GameState gameState, GameMove move) {
    if (!isValidMove(gameState, move)) {
      throw ArgumentError('Invalid move attempted');
    }

    // Create a new game state (immutable approach)
    final newGameState = GameState(
      gameId: gameState.gameId,
      player1: gameState.player1,
      player2: gameState.player2,
      walls: List.from(gameState.walls),
      currentPlayerId: gameState.currentPlayerId,
      status: gameState.status,
      createdAt: gameState.createdAt,
      updatedAt: DateTime.now(),
      moveHistory: List.from(gameState.moveHistory),
    );

    // Execute the move
    if (move.type == MoveType.pawnMove) {
      newGameState.movePawn(move.newPosition!);
    } else {
      newGameState.addWall(move.wall!);
    }

    // Add move to history
    newGameState.addMoveToHistory(move);

    // Check win condition
    newGameState.checkWinCondition();

    // Switch turns if game is still playing
    if (!newGameState.isGameOver) {
      newGameState.switchTurn();
    }

    return newGameState;
  }

  // Get all valid moves for current player
  static List<GameMove> getValidMoves(GameState gameState) {
    final currentPlayer = gameState.currentPlayer;
    final validMoves = <GameMove>[];

    // Add valid pawn moves
    final validPositions = gameState.getValidMoves(currentPlayer.position);
    for (final position in validPositions) {
      validMoves.add(GameMove.pawnMove(position, currentPlayer.id));
    }

    // Add valid wall placements
    if (currentPlayer.hasWallsRemaining) {
      final validWalls = _getValidWallPlacements(gameState);
      for (final wall in validWalls) {
        validMoves.add(GameMove.wallPlace(wall, currentPlayer.id));
      }
    }

    return validMoves;
  }

  // Execute AI turn
  static Future<GameState> executeAITurn(
    GameState gameState,
    AIDifficulty difficulty,
  ) async {
    if (!gameState.currentPlayer.isAI || gameState.isGameOver) {
      return gameState;
    }

    final aiMove = await AIService.generateMove(gameState, difficulty);

    if (aiMove != null && isValidMove(gameState, aiMove)) {
      return executeMove(gameState, aiMove);
    }

    // Fallback: get any valid move
    final validMoves = getValidMoves(gameState);
    if (validMoves.isNotEmpty) {
      return executeMove(gameState, validMoves.first);
    }

    return gameState;
  }

  // Analyze game state for UI feedback
  static GameAnalysis analyzeGameState(GameState gameState) {
    final pathLengths = Pathfinding.calculatePathLengths(gameState);
    final validMoves = getValidMoves(gameState);

    return GameAnalysis(
      playerPathLengths: pathLengths,
      validMoves: validMoves,
      gamePhase: _determineGamePhase(gameState),
      winner: gameState.winner,
      isGameOver: gameState.isGameOver,
    );
  }

  // Private helper methods
  static bool _isValidPawnMove(
    GameState gameState,
    Player player,
    Position newPosition,
  ) {
    final validMoves = gameState.getValidMoves(player.position);
    return validMoves.contains(newPosition);
  }

  static bool _isValidWallPlacement(
    GameState gameState,
    Player player,
    Wall wall,
  ) {
    return validateWallPlacement(gameState, player, wall).isValid;
  }

  /// Checks a wall placement and explains why it was rejected.
  ///
  /// The UI uses the reason to tell the player what is wrong *before* they
  /// commit the wall, instead of silently refusing the tap.
  static WallPlacementResult validateWallPlacement(
    GameState gameState,
    Player player,
    Wall wall,
  ) {
    if (!player.hasWallsRemaining) {
      return const WallPlacementResult(WallRejection.noWallsLeft);
    }

    if (!isWallInBounds(wall)) {
      return const WallPlacementResult(WallRejection.outOfBounds);
    }

    for (final existingWall in gameState.walls) {
      if (_wallsOverlap(wall, existingWall)) {
        return const WallPlacementResult(WallRejection.overlaps);
      }
      if (_wallsCross(wall, existingWall)) {
        return const WallPlacementResult(WallRejection.crosses);
      }
    }

    // A wall may never seal a player off from their goal row.
    final tempGameState = _createTempGameStateWithWall(gameState, wall);

    final player1Path = Pathfinding.findShortestPath(
      tempGameState,
      tempGameState.player1.position,
      tempGameState.player1.goalRow,
    );

    final player2Path = Pathfinding.findShortestPath(
      tempGameState,
      tempGameState.player2.position,
      tempGameState.player2.goalRow,
    );

    if (player1Path == null || player2Path == null) {
      return const WallPlacementResult(WallRejection.blocksPlayer);
    }

    return const WallPlacementResult(WallRejection.none);
  }

  /// Whether a wall sits on a real groove between cells.
  ///
  /// A horizontal wall at (r, c) lies above row r and covers columns c and
  /// c+1, so r must be an interior row. A vertical wall at (r, c) lies to the
  /// left of column c and covers rows r and r+1, so c must be an interior
  /// column. Walls on the board's outer edge are meaningless: they would sit
  /// on top of the boundary and block nothing.
  static bool isWallInBounds(Wall wall) {
    final row = wall.position.row;
    final col = wall.position.col;

    if (wall.orientation == WallOrientation.horizontal) {
      return row >= 1 &&
          row <= GameConstants.boardSize - 1 &&
          col >= 0 &&
          col <= GameConstants.boardSize - 2;
    }
    return col >= 1 &&
        col <= GameConstants.boardSize - 1 &&
        row >= 0 &&
        row <= GameConstants.boardSize - 2;
  }

  static GameState _createTempGameStateWithWall(GameState original, Wall wall) {
    return GameState(
      gameId: original.gameId,
      player1: original.player1,
      player2: original.player2,
      walls: [...original.walls, wall],
      currentPlayerId: original.currentPlayerId,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
      moveHistory: List.from(original.moveHistory),
    );
  }

  static List<Wall> _getValidWallPlacements(GameState gameState) {
    final validWalls = <Wall>[];

    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        // Try horizontal wall
        final horizontalWall = Wall(
          Position(row, col),
          WallOrientation.horizontal,
        );

        if (_isValidWallPlacement(
          gameState,
          gameState.currentPlayer,
          horizontalWall,
        )) {
          validWalls.add(horizontalWall);
        }

        // Try vertical wall
        final verticalWall = Wall(Position(row, col), WallOrientation.vertical);

        if (_isValidWallPlacement(
          gameState,
          gameState.currentPlayer,
          verticalWall,
        )) {
          validWalls.add(verticalWall);
        }
      }
    }

    return validWalls;
  }

  /// Two walls of the same orientation overlap when they share the same
  /// groove and their two-cell spans touch.
  static bool _wallsOverlap(Wall wall1, Wall wall2) {
    if (wall1.orientation != wall2.orientation) return false;

    if (wall1.orientation == WallOrientation.horizontal) {
      return wall1.position.row == wall2.position.row &&
          (wall1.position.col - wall2.position.col).abs() <= 1;
    }
    return wall1.position.col == wall2.position.col &&
        (wall1.position.row - wall2.position.row).abs() <= 1;
  }

  /// A horizontal and a vertical wall may not cross at the same intersection.
  ///
  /// Each wall is centred on a grid intersection: a horizontal wall at (r, c)
  /// is centred on (r, c + 1) and a vertical wall at (r, c) on (r + 1, c).
  /// Sharing that centre would make the two walls intersect, which the rules
  /// forbid.
  static bool _wallsCross(Wall wall1, Wall wall2) {
    if (wall1.orientation == wall2.orientation) return false;

    final horizontal = wall1.orientation == WallOrientation.horizontal
        ? wall1
        : wall2;
    final vertical = identical(horizontal, wall1) ? wall2 : wall1;

    return horizontal.position.row == vertical.position.row + 1 &&
        horizontal.position.col + 1 == vertical.position.col;
  }

  static GamePhase _determineGamePhase(GameState gameState) {
    final totalMoves = gameState.moveHistory.length;
    final wallsPlaced = gameState.walls.length;

    if (totalMoves < 6 && wallsPlaced < 2) {
      return GamePhase.opening;
    } else if (wallsPlaced < 12 && totalMoves < 25) {
      return GamePhase.midgame;
    } else {
      return GamePhase.endgame;
    }
  }
}

// Data classes for game analysis
class GameAnalysis {
  final Map<int, int> playerPathLengths;
  final List<GameMove> validMoves;
  final GamePhase gamePhase;
  final String? winner;
  final bool isGameOver;

  GameAnalysis({
    required this.playerPathLengths,
    required this.validMoves,
    required this.gamePhase,
    this.winner,
    required this.isGameOver,
  });
}

enum GamePhase { opening, midgame, endgame }

/// Why a wall placement was refused.
enum WallRejection {
  none,
  noWallsLeft,
  outOfBounds,
  overlaps,
  crosses,
  blocksPlayer,
}

/// The outcome of checking a wall placement, with a message for the player.
class WallPlacementResult {
  final WallRejection rejection;

  const WallPlacementResult(this.rejection);

  bool get isValid => rejection == WallRejection.none;

  /// Short explanation suitable for showing directly in the UI.
  String get message {
    switch (rejection) {
      case WallRejection.none:
        return 'Wall can be placed here';
      case WallRejection.noWallsLeft:
        return 'You have no walls left';
      case WallRejection.outOfBounds:
        return 'Walls must sit between cells';
      case WallRejection.overlaps:
        return 'Another wall is already here';
      case WallRejection.crosses:
        return 'Walls cannot cross each other';
      case WallRejection.blocksPlayer:
        return 'This would leave a player with no way to their goal';
    }
  }
}

// Utility class for game creation and management
class GameManager {
  static GameState createNewGame({
    String player1Name = 'Player 1',
    String player2Name = 'AI',
    bool enableAI = true,
    AIDifficulty aiDifficulty = AIDifficulty.medium,
  }) {
    return GameStateFactory.createNewGame(
      player1Name: player1Name,
      player2Name: player2Name,
      player2IsAI: enableAI,
    );
  }

  static Future<GameState> processPlayerMove(
    GameState gameState,
    GameMove move,
  ) async {
    // Execute player move
    var newGameState = GameService.executeMove(gameState, move);

    // Execute AI turn if next player is AI
    if (!newGameState.isGameOver && newGameState.currentPlayer.isAI) {
      newGameState = await GameService.executeAITurn(
        newGameState,
        AIDifficulty.medium,
      );
    }

    return newGameState;
  }

  static bool canPlayerMove(GameState gameState, int playerId) {
    return gameState.currentPlayerId == playerId && !gameState.isGameOver;
  }

  static List<Position> getValidMovesForPosition(
    GameState gameState,
    Position position,
  ) {
    return gameState.getValidMoves(position);
  }
}
