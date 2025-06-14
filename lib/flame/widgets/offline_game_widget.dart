import 'package:flutter/material.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/widgets/game/game_app_bar.dart';
import 'package:quoridor/flame/widgets/game/game_board.dart';
import 'package:quoridor/flame/widgets/game/game_player_info_widget.dart';
import 'package:quoridor/flame/widgets/game/game_wall_controls.dart';

class OfflineGameWidget extends StatefulWidget {
  const OfflineGameWidget({super.key});

  @override
  State<OfflineGameWidget> createState() => _OfflineGameWidgetState();
}

class _OfflineGameWidgetState extends State<OfflineGameWidget> {
  late QuoridorGame _game;
  bool _isGameOver = false;

  @override
  void initState() {
    super.initState();
    _game = QuoridorGame(onGameOver: _handleGameOver);
  }

  void _handleGameOver() {
    setState(() {
      _isGameOver = true;
    });
  }

  void _restartGame() {
    setState(() {
      _isGameOver = false;
      _game = QuoridorGame(onGameOver: _handleGameOver);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const GameAppBar(),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Row(
              children: [
                Expanded(flex: 2, child: GameBoard(_game)),
                Expanded(
                  child: Column(
                    children: [
                      GamePlayerInfoWidget(
                        playerId: 1,
                        name: 'Player 1',
                        wallsRemaining: _game.gameState.player1.wallsRemaining,
                        isCurrentPlayer: _game.currentPlayerId == 1,
                        isAI: false,
                      ),
                      const SizedBox(height: 16),
                      GamePlayerInfoWidget(
                        playerId: 2,
                        name: 'Player 2',
                        wallsRemaining: _game.gameState.player2.wallsRemaining,
                        isCurrentPlayer: _game.currentPlayerId == 2,
                        isAI: _game.gameState.player2.isAI,
                      ),
                      const SizedBox(height: 16),
                      GameWallControls(game: _game),
                    ],
                  ),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                Expanded(child: GameBoard(_game)),
                GamePlayerInfoWidget(
                  playerId: 1,
                  name: 'Player 1',
                  wallsRemaining: _game.gameState.player1.wallsRemaining,
                  isCurrentPlayer: _game.currentPlayerId == 1,
                  isAI: false,
                ),
                const SizedBox(height: 16),
                GamePlayerInfoWidget(
                  playerId: 2,
                  name: 'Player 2',
                  wallsRemaining: _game.gameState.player2.wallsRemaining,
                  isCurrentPlayer: _game.currentPlayerId == 2,
                  isAI: _game.gameState.player2.isAI,
                ),
                const SizedBox(height: 16),
                GameWallControls(game: _game),
              ],
            );
          }
        },
      ),
    );
  }
}
