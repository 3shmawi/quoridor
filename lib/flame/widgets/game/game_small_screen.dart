import 'package:flutter/material.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/widgets/game/game_player_info_widget.dart';
import 'package:quoridor/flame/widgets/game/game_wall_controls.dart';

import 'game_board.dart';

class GameSmallScreen extends StatelessWidget {
  const GameSmallScreen(this.game, {super.key});

  final QuoridorGame game;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: GameBoard(game)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: [
              GameWallControls(
                orientation: WallOrientation.horizontal,
                onOrientationChanged: (n) {},
                onWallMovement: (wall) {},
                onWallPlacementConfirmed: () {},
              ),
              IgnorePointer(
                child: ValueListenableBuilder(
                  valueListenable: isInitializedProvider,
                  builder: (context, value, child) {
                    if (!value) return const SizedBox.shrink();
                    return GridView(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 2.2,
                          ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        GamePlayerInfoWidget(
                          playerId: 1,
                          name: 'Player 1',
                          wallsRemaining: game.gameState.player1.wallsRemaining,
                          isCurrentPlayer: game.gameState.currentPlayer.id == 1,
                          isAI: false,
                        ),
                        GamePlayerInfoWidget(
                          playerId: 2,
                          name: 'Player 2',
                          wallsRemaining: game.gameState.player2.wallsRemaining,
                          isCurrentPlayer: game.gameState.currentPlayer.id == 2,
                          isAI: game.gameState.player2.isAI,
                        ),
                        GamePlayerInfoWidget(
                          playerId: 2,
                          name: 'Player 2',
                          wallsRemaining: game.gameState.player2.wallsRemaining,
                          isCurrentPlayer: game.gameState.currentPlayer.id == 2,
                          isAI: game.gameState.player2.isAI,
                        ),
                        GamePlayerInfoWidget(
                          playerId: 2,
                          name: 'Player 2',
                          wallsRemaining: game.gameState.player2.wallsRemaining,
                          isCurrentPlayer: game.gameState.currentPlayer.id == 2,
                          isAI: game.gameState.player2.isAI,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
      ],
    );
  }
}
