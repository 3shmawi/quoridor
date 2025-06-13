import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../components/board_component.dart';
import '../../constants.dart';
import '../../game/quoridor_game.dart';

class GameBoard extends StatelessWidget {
  const GameBoard(this.game, {super.key});

  final QuoridorGame game;

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
            child: GameWidget<QuoridorGame>.controlled(gameFactory: () => game),
          );
        },
      ),
    );
  }
}
