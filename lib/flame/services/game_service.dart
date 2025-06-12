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
    if (!player.hasWallsRemaining) return false;

    // Check bounds
    if (wall.position.row < 0 || wall.position.col < 0) return false;

    if (wall.orientation == WallOrientation.horizontal) {
      if (wall.position.row >= GameConstants.boardSize ||
          wall.position.col >= GameConstants.boardSize - 1) {
        return false;
      }
    } else {
      if (wall.position.row >= GameConstants.boardSize - 1 ||
          wall.position.col >= GameConstants.boardSize) {
        return false;
      }
    }

    // Check for overlapping walls
    for (final existingWall in gameState.walls) {
      if (_wallsOverlap(wall, existingWall)) {
        return false;
      }
    }

    // Create temporary game state with the wall
    final tempGameState = _createTempGameStateWithWall(gameState, wall);

    // Check if both players still have valid paths
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

    // Wall is valid if both players still have a path to their goal
    return player1Path != null && player2Path != null;
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

  static bool _wallsOverlap(Wall wall1, Wall wall2) {
    if (wall1.orientation != wall2.orientation) return false;

    if (wall1.orientation == WallOrientation.horizontal) {
      return wall1.position.row == wall2.position.row &&
          (wall1.position.col == wall2.position.col ||
              wall1.position.col == wall2.position.col + 1 ||
              wall1.position.col == wall2.position.col - 1);
    } else {
      return wall1.position.col == wall2.position.col &&
          (wall1.position.row == wall2.position.row ||
              wall1.position.row == wall2.position.row + 1 ||
              wall1.position.row == wall2.position.row - 1);
    }
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
