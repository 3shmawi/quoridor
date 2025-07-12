import '../../flame/constants.dart';
import '../../flame/game/pathfinding.dart';
import '../../flame/models/game_state.dart';
import '../../flame/models/player.dart';
import 'ai_service.dart';

class GameService {
  // Validate if a move is legal
  static bool isValidMove(GameState gameState, GameMove move) {
    final player = gameState.players.firstWhere((p) => p.id == move.playerId);

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
      players: List.from(gameState.players),
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
  static List<GameMove> getAllValidMoves(GameState gameState) {
    final moves = <GameMove>[];
    final currentPlayer = gameState.currentPlayer;

    // Get valid pawn moves
    final validPositions = gameState.getValidMoves(currentPlayer.position);
    for (final position in validPositions) {
      moves.add(GameMove.pawnMove(position, currentPlayer.id));
    }

    // Get valid wall placements
    if (currentPlayer.hasWallsRemaining) {
      final validWalls = _getValidWallPlacements(gameState);
      for (final wall in validWalls) {
        moves.add(GameMove.wallPlace(wall, currentPlayer.id));
      }
    }

    return moves;
  }

  // Get valid wall placements for current player
  static List<Wall> _getValidWallPlacements(GameState gameState) {
    final walls = <Wall>[];

    // Check all possible wall positions
    for (int row = 0; row < GameConstants.boardSize - 1; row++) {
      for (int col = 0; col < GameConstants.boardSize - 1; col++) {
        // Horizontal wall
        final horizontalWall = Wall(
          Position(row, col),
          WallOrientation.horizontal,
        );
        if (_isValidWallPlacement(
          gameState,
          gameState.currentPlayer,
          horizontalWall,
        )) {
          walls.add(horizontalWall);
        }

        // Vertical wall
        final verticalWall = Wall(Position(row, col), WallOrientation.vertical);
        if (_isValidWallPlacement(
          gameState,
          gameState.currentPlayer,
          verticalWall,
        )) {
          walls.add(verticalWall);
        }
      }
    }

    return walls;
  }

  // Check if pawn move is valid
  static bool _isValidPawnMove(
    GameState gameState,
    Player player,
    Position newPosition,
  ) {
    // Check if it's the player's turn
    if (gameState.currentPlayerId != player.id) {
      return false;
    }

    // Check if game is over
    if (gameState.isGameOver) {
      return false;
    }

    // Check if position is within bounds
    if (newPosition.row < 0 ||
        newPosition.row >= GameConstants.boardSize ||
        newPosition.col < 0 ||
        newPosition.col >= GameConstants.boardSize) {
      return false;
    }

    // Check if position is occupied
    if (gameState.isPositionOccupied(newPosition)) {
      return false;
    }

    // Check if move is blocked by walls
    if (gameState.isWallBlocking(player.position, newPosition)) {
      return false;
    }

    // Check if move is adjacent or a valid jump
    final validMoves = gameState.getValidMoves(player.position);
    return validMoves.contains(newPosition);
  }

  // Check if wall placement is valid
  static bool _isValidWallPlacement(
    GameState gameState,
    Player player,
    Wall wall,
  ) {
    // Check if it's the player's turn
    if (gameState.currentPlayerId != player.id) {
      return false;
    }

    // Check if game is over
    if (gameState.isGameOver) {
      return false;
    }

    // Check if player has walls remaining
    if (!player.hasWallsRemaining) {
      return false;
    }

    // Check wall bounds
    if (wall.position.row < 0 || wall.position.col < 0) {
      return false;
    }

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

    // Check if wall overlaps with existing walls
    for (final existingWall in gameState.walls) {
      if (_wallsOverlap(wall, existingWall)) {
        return false;
      }
    }

    // Check if wall would block all paths
    return !Pathfinding.wouldWallBlockAllPaths(gameState, wall);
  }

  // Check if two walls overlap
  static bool _wallsOverlap(Wall wall1, Wall wall2) {
    if (wall1.orientation != wall2.orientation) {
      return false;
    }

    if (wall1.orientation == WallOrientation.horizontal) {
      return wall1.position.row == wall2.position.row &&
          wall1.position.col < wall2.position.col + 2 &&
          wall1.position.col + 2 > wall2.position.col;
    } else {
      return wall1.position.col == wall2.position.col &&
          wall1.position.row < wall2.position.row + 2 &&
          wall1.position.row + 2 > wall2.position.row;
    }
  }

  // Execute AI turn
  static Future<GameState> executeAITurn(
    GameState gameState,
    AIDifficulty difficulty,
  ) async {
    final aiMove = await AIService.generateMove(gameState, difficulty);
    if (aiMove != null) {
      return executeMove(gameState, aiMove);
    }
    return gameState;
  }

  // Analyze game state
  static GameAnalysis analyzeGame(GameState gameState) {
    final pathLengths = Pathfinding.calculatePathLengths(gameState);
    final validMoves = getAllValidMoves(gameState);
    final gamePhase = _determineGamePhase(gameState);
    final winner = gameState.winner;
    final isGameOver = gameState.isGameOver;

    return GameAnalysis(
      playerPathLengths: pathLengths,
      validMoves: validMoves,
      gamePhase: gamePhase,
      winner: winner,
      isGameOver: isGameOver,
    );
  }

  // Determine game phase
  static GamePhase _determineGamePhase(GameState gameState) {
    final totalWallsPlaced = gameState.walls.length;
    final maxWalls = gameState.players.length * GameConstants.maxWallsPerPlayer;

    if (totalWallsPlaced < maxWalls * 0.3) {
      return GamePhase.opening;
    } else if (totalWallsPlaced < maxWalls * 0.7) {
      return GamePhase.midgame;
    } else {
      return GamePhase.endgame;
    }
  }

  // Check if a player can reach their goal
  static bool canPlayerReachGoal(GameState gameState, int playerId) {
    final player = gameState.players.firstWhere((p) => p.id == playerId);
    final path = Pathfinding.findShortestPath(
      gameState,
      player.position,
      player.goalRow,
    );
    return path != null;
  }

  // Get player's shortest path to goal
  static List<Position>? getPlayerPathToGoal(
    GameState gameState,
    int playerId,
  ) {
    final player = gameState.players.firstWhere((p) => p.id == playerId);
    return Pathfinding.findShortestPath(
      gameState,
      player.position,
      player.goalRow,
    );
  }

  // Create a temporary game state for analysis
  static GameState createTempGameState(GameState original) {
    return GameState(
      gameId: original.gameId,
      players: List.from(original.players),
      walls: List.from(original.walls),
      currentPlayerId: original.currentPlayerId,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
    );
  }
}

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
  // static GameState createNewGame({
  //   String player1Name = 'Player 1',
  //   String player2Name = 'AI',
  //   bool enableAI = true,
  //   AIDifficulty aiDifficulty = AIDifficulty.medium,
  // }) {
  //   return GameStateFactory.createNewGame(
  //     player1Name: player1Name,
  //     player2Name: player2Name,
  //     player2IsAI: enableAI,
  //   );
  // }

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
