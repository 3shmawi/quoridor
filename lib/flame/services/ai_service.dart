import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../flame/constants.dart';
import '../../flame/game/pathfinding.dart';
import '../../flame/models/game_state.dart';
import '../../flame/models/player.dart';

enum AIDifficulty { easy, medium, hard }

class AIService {
  static const String _apiKey =
      'EM0CslaVtzEsqKb6wNCk-4628bc90f1fb9205d2d0abf780b59f878985d392ff52eca5dc175fe755fa7352';
  static const String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  // Generate AI move using OpenAI strategy analysis
  static Future<GameMove?> generateMove(
    GameState gameState,
    AIDifficulty difficulty,
  ) async {
    try {
      // Get strategic analysis from OpenAI
      final strategy = await _getAIStrategy(gameState, difficulty);

      if (strategy != null) {
        // Execute the recommended move
        return _executeAIMove(gameState, strategy);
      }

      // Fallback to basic AI logic if OpenAI fails
      return _getFallbackMove(gameState, difficulty);
    } catch (e) {
      print('AI Service Error: $e');
      return _getFallbackMove(gameState, difficulty);
    }
  }

  static Future<AIStrategy?> _getAIStrategy(
    GameState gameState,
    AIDifficulty difficulty,
  ) async {
    final gameAnalysis = _analyzeGameState(gameState);
    final prompt = _buildStrategyPrompt(gameAnalysis, difficulty);

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an expert Quoridor game AI strategist. 
Analyze the game state and recommend the optimal move as a JSON object with the following structure:
{
  "moveType": "pawn" or "wall",
  "position": {"row": int, "col": int},
  "orientation": "horizontal" or "vertical" (only for walls),
  "reasoning": "Brief explanation of the strategy"
}''',
            },
            {'role': 'user', 'content': prompt},
          ],
          'response_format': {'type': 'json_object'},
          'max_tokens': 500,
          'temperature': difficulty == AIDifficulty.easy ? 0.8 : 0.3,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices'][0]['message']['content'];
        final strategyJson = jsonDecode(content);

        return AIStrategy.fromJson(strategyJson);
      }
    } catch (e) {
      print('OpenAI API Error: $e');
    }

    return null;
  }

  static String _analyzeGameState(GameState gameState) {
    final pathLengths = Pathfinding.calculatePathLengths(gameState);
    final currentPlayer = gameState.currentPlayer;
    final opponent = gameState.otherPlayers.isNotEmpty
        ? gameState.otherPlayers.first
        : currentPlayer;

    return '''
Current Game State Analysis:
- Current Player: ${currentPlayer.name} (ID: ${currentPlayer.id})
- Player Position: Row ${currentPlayer.position.row}, Col ${currentPlayer.position.col}
- Player Goal: Row ${currentPlayer.goalRow}
- Player Walls Remaining: ${currentPlayer.wallsRemaining}
- Player Path Length: ${pathLengths[currentPlayer.id]}

- Opponent: ${opponent.name} (ID: ${opponent.id})
- Opponent Position: Row ${opponent.position.row}, Col ${opponent.position.col}
- Opponent Goal: Row ${opponent.goalRow}
- Opponent Walls Remaining: ${opponent.wallsRemaining}
- Opponent Path Length: ${pathLengths[opponent.id]}

- Total Walls Placed: ${gameState.walls.length}
- Board Size: ${GameConstants.boardSize}x${GameConstants.boardSize}

Strategic Considerations:
- Path Length Advantage: ${(pathLengths[opponent.id]!) - (pathLengths[currentPlayer.id]!)}
- Wall Efficiency: ${currentPlayer.hasWallsRemaining ? 'Can place walls' : 'No walls remaining'}
- Game Phase: ${gameState.walls.length < 5
        ? 'Early'
        : gameState.walls.length < 15
        ? 'Mid'
        : 'Late'} game
''';
  }

  static String _buildStrategyPrompt(String analysis, AIDifficulty difficulty) {
    final strategyLevel = switch (difficulty) {
      AIDifficulty.easy =>
        'Play a simple strategy focusing mainly on moving toward the goal. Consider walls only when absolutely necessary.',
      AIDifficulty.medium =>
        'Play a balanced strategy, considering both offensive moves and defensive wall placements.',
      AIDifficulty.hard =>
        'Play optimally using advanced tactics like path manipulation, wall timing, and tactical sacrifices.',
    };

    return '''
$analysis

Difficulty Level: ${difficulty.name.toUpperCase()}
Strategy Instructions: $strategyLevel

Please analyze this Quoridor game state and recommend the optimal move. Consider:
1. Path efficiency and shortest routes
2. Wall placement to block opponent
3. Timing of offensive vs defensive moves
4. Endgame positioning

Provide your recommendation as a JSON object.
''';
  }

  static GameMove? _executeAIMove(GameState gameState, AIStrategy strategy) {
    final currentPlayer = gameState.currentPlayer;

    if (strategy.moveType == 'pawn') {
      final newPosition = Position(
        strategy.position.row,
        strategy.position.col,
      );
      final validMoves = gameState.getValidMoves(currentPlayer.position);

      if (validMoves.contains(newPosition)) {
        return GameMove.pawnMove(newPosition, currentPlayer.id);
      }
    } else if (strategy.moveType == 'wall' && currentPlayer.hasWallsRemaining) {
      final wall = Wall(
        Position(strategy.position.row, strategy.position.col),
        strategy.orientation == 'horizontal'
            ? WallOrientation.horizontal
            : WallOrientation.vertical,
      );

      if (!Pathfinding.wouldWallBlockAllPaths(gameState, wall)) {
        return GameMove.wallPlace(wall, currentPlayer.id);
      }
    }

    return null;
  }

  static GameMove _getFallbackMove(
    GameState gameState,
    AIDifficulty difficulty,
  ) {
    final currentPlayer = gameState.currentPlayer;
    final pathLengths = Pathfinding.calculatePathLengths(gameState);

    // Basic AI logic based on difficulty
    switch (difficulty) {
      case AIDifficulty.easy:
        return _getEasyMove(gameState);
      case AIDifficulty.medium:
        return _getMediumMove(gameState, pathLengths);
      case AIDifficulty.hard:
        return _getHardMove(gameState, pathLengths);
    }
  }

  static GameMove _getEasyMove(GameState gameState) {
    final currentPlayer = gameState.currentPlayer;
    final validMoves = gameState.getValidMoves(currentPlayer.position);

    if (validMoves.isNotEmpty) {
      // Move toward goal based on player mode
      Position? bestMove;
      int bestDistance = 999;

      for (final move in validMoves) {
        int distance;

        // For 2-player mode: distance to goal row
        if (currentPlayer.id <= 2) {
          distance = (move.row - currentPlayer.goalRow).abs();
        }
        // For 4-player mode: distance to goal column
        else {
          if (currentPlayer.id == 3) {
            distance = (move.col - 0).abs(); // Distance to left column
          } else {
            distance = (move.col - 8).abs(); // Distance to right column
          }
        }

        if (distance < bestDistance) {
          bestDistance = distance;
          bestMove = move;
        }
      }

      return GameMove.pawnMove(bestMove!, currentPlayer.id);
    }

    // Should not happen, but fallback
    return GameMove.pawnMove(currentPlayer.position, currentPlayer.id);
  }

  static GameMove _getMediumMove(
    GameState gameState,
    Map<int, int> pathLengths,
  ) {
    final currentPlayer = gameState.currentPlayer;

    // Find the most threatening opponent (closest to winning)
    Player? mostThreateningOpponent;
    int shortestOpponentPath = 999;

    for (final opponent in gameState.otherPlayers) {
      final opponentPathLength = pathLengths[opponent.id]!;
      if (opponentPathLength < shortestOpponentPath) {
        shortestOpponentPath = opponentPathLength;
        mostThreateningOpponent = opponent;
      }
    }

    if (mostThreateningOpponent == null) {
      return _getEasyMove(gameState);
    }

    final playerPathLength = pathLengths[currentPlayer.id]!;

    // Consider wall placement if opponent is close to winning
    if (currentPlayer.hasWallsRemaining &&
        shortestOpponentPath < playerPathLength &&
        shortestOpponentPath <= 3) {
      final bestWall = Pathfinding.findBestWallPlacement(
        gameState,
        currentPlayer.id,
      );
      if (bestWall != null) {
        return GameMove.wallPlace(bestWall, currentPlayer.id);
      }
    }

    // Otherwise move toward goal
    return _getEasyMove(gameState);
  }

  static GameMove _getHardMove(GameState gameState, Map<int, int> pathLengths) {
    final currentPlayer = gameState.currentPlayer;

    // Find the most threatening opponent (closest to winning)
    Player? mostThreateningOpponent;
    int shortestOpponentPath = 999;

    for (final opponent in gameState.otherPlayers) {
      final opponentPathLength = pathLengths[opponent.id]!;
      if (opponentPathLength < shortestOpponentPath) {
        shortestOpponentPath = opponentPathLength;
        mostThreateningOpponent = opponent;
      }
    }

    if (mostThreateningOpponent == null) {
      return _getOptimalPawnMove(gameState);
    }

    final playerPathLength = pathLengths[currentPlayer.id]!;

    // Advanced strategy: Use walls more strategically
    if (currentPlayer.hasWallsRemaining) {
      final shouldUseWall = _shouldUseWallStrategically(
        gameState,
        pathLengths,
        shortestOpponentPath,
        playerPathLength,
      );

      if (shouldUseWall) {
        final bestWall = Pathfinding.findBestWallPlacement(
          gameState,
          currentPlayer.id,
        );
        if (bestWall != null) {
          return GameMove.wallPlace(bestWall, currentPlayer.id);
        }
      }
    }

    // Optimal pawn movement
    return _getOptimalPawnMove(gameState);
  }

  static bool _shouldUseWallStrategically(
    GameState gameState,
    Map<int, int> pathLengths,
    int opponentPathLength,
    int playerPathLength,
  ) {
    // Use wall if opponent is ahead
    if (opponentPathLength < playerPathLength) return true;

    // Use wall if opponent is very close to winning
    if (opponentPathLength <= 2) return true;

    // Save walls for late game if paths are equal
    if (opponentPathLength == playerPathLength && gameState.walls.length > 10) {
      return false;
    }

    // Random chance for unpredictability
    return Random().nextDouble() < 0.3;
  }

  static GameMove _getOptimalPawnMove(GameState gameState) {
    final currentPlayer = gameState.currentPlayer;
    final validMoves = gameState.getValidMoves(currentPlayer.position);

    if (validMoves.isEmpty) {
      return GameMove.pawnMove(currentPlayer.position, currentPlayer.id);
    }

    // Find move that leads to shortest path
    Position bestMove = validMoves.first;
    int shortestPath = 999;

    for (final move in validMoves) {
      final tempGameState = _createTempGameStateWithMove(gameState, move);

      final path = Pathfinding.findShortestPath(
        tempGameState,
        move,
        currentPlayer.goalRow,
      );

      if (path != null && path.length < shortestPath) {
        shortestPath = path.length;
        bestMove = move;
      }
    }

    return GameMove.pawnMove(bestMove, currentPlayer.id);
  }

  static GameState _createTempGameStateWithMove(
    GameState original,
    Position move,
  ) {
    final currentPlayer = original.currentPlayer;
    final updatedPlayers = List<Player>.from(original.players);
    final playerIndex = updatedPlayers.indexWhere(
      (p) => p.id == currentPlayer.id,
    );

    if (playerIndex != -1) {
      updatedPlayers[playerIndex] = updatedPlayers[playerIndex].copyWith(
        position: move,
      );
    }

    return GameState(
      gameId: original.gameId,
      players: updatedPlayers,
      walls: original.walls,
      currentPlayerId: original.currentPlayerId,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
    );
  }
}

class AIStrategy {
  final String moveType;
  final Position position;
  final String? orientation;
  final String reasoning;

  AIStrategy({
    required this.moveType,
    required this.position,
    this.orientation,
    required this.reasoning,
  });

  static AIStrategy fromJson(Map<String, dynamic> json) => AIStrategy(
    moveType: json['moveType'] as String,
    position: Position(
      json['position']['row'] as int,
      json['position']['col'] as int,
    ),
    orientation: json['orientation'] as String?,
    reasoning: json['reasoning'] as String,
  );
}
