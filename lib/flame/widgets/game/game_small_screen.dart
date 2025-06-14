import 'package:flutter/material.dart';
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
        AnimatedCrossFade(
          firstChild: GameWallControls(game: game),
          secondChild: SizedBox.shrink(),
          crossFadeState:
              !game.gameState.isAi && game.gameState.currentPlayer.id == 2
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: Duration(milliseconds: 500),
        ),

        Expanded(child: GameBoard(game)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: [
              AnimatedCrossFade(
                firstChild: GameWallControls(game: game),
                secondChild: SizedBox.shrink(),
                crossFadeState: game.gameState.currentPlayer.id == 1
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: Duration(milliseconds: 500),
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
                            childAspectRatio: 1.6,
                          ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(
                        game.gameState.players.length,
                        (index) => GamePlayerInfoWidget(
                          playerId: game.gameState.players[index].id,
                          name: game.gameState.players[index].name,
                          wallsRemaining:
                              game.gameState.players[index].wallsRemaining,
                          isCurrentPlayer:
                              game.gameState.currentPlayer.id ==
                              game.gameState.players[index].id,
                          isAI: game.gameState.players[index].isAI,
                        ),
                      ),
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
