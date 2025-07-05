import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../constants.dart';
import '../../controller/game_controller.dart';
import '../../controller/game_states.dart';
import '../../game/quoridor_game.dart';

class GameBoard extends StatelessWidget {
  final QuoridorGame game;
  final GameController? gameController;

  const GameBoard(this.game, {super.key, this.gameController});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ValueListenableBuilder(
        valueListenable: cellSizeNotifier,
        builder: (context, value, child) {
          return SizedBox(
            width:
                (value + GameConstants.cellSpacing) * GameConstants.boardSize +
                GameConstants.boardPadding * 2,
            height:
                (value + GameConstants.cellSpacing) * GameConstants.boardSize +
                GameConstants.boardPadding * 2,
            child: GameWidget<QuoridorGame>.controlled(
              gameFactory: () => game,
              overlayBuilderMap: {
                'gameController': (context, game) => gameController != null
                    ? BlocBuilder<GameController, GameStates>(
                        builder: (context, state) {
                          // Update game state from controller
                          if (state is GamePlayingState) {
                            game.updateFromController();
                          }
                          return const SizedBox.shrink();
                        },
                      )
                    : const SizedBox.shrink(),
              },
            ),
          );
        },
      ),
    );
  }
}
