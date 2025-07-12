import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:quoridor/flame/controller/game_states.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/widgets/game/game_player_info_widget.dart';
import 'package:quoridor/flame/widgets/game/game_wall_controls.dart';

import '../../controller/game_controller.dart';
import 'game_board.dart';

class GameSmallScreen extends StatefulWidget {
  final QuoridorGame game;
  final GameController? gameController;

  const GameSmallScreen(this.game, {super.key, this.gameController});

  @override
  State<GameSmallScreen> createState() => _GameSmallScreenState();
}

class _GameSmallScreenState extends State<GameSmallScreen> {
  late final gameController = context.read<GameController>();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Divider(),
        GameWallControls(
          game: widget.game,
          gameController: widget.gameController,
        ),
        Expanded(
          child: GameBoard(widget.game, gameController: widget.gameController),
        ),
        if (gameController.state is GamePlayingState)
          IgnorePointer(
            child: ValueListenableBuilder(
              valueListenable: isInitializedProvider,
              builder: (context, value, child) {
                if (!value) return const SizedBox.shrink();
                return GridView(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 0,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (
                      int i = 0;
                      i < (widget.game.gameState?.players.length ?? 0);
                      i++
                    )
                      GamePlayerInfoWidget(
                        playerId: (gameController.state as GamePlayingState)
                            .gameState
                            .players[i]
                            .id,
                        name: (gameController.state as GamePlayingState)
                            .gameState
                            .players[i]
                            .name,
                        wallsRemaining:
                            (gameController.state as GamePlayingState)
                                .gameState!
                                .players[i]
                                .wallsRemaining,
                        isCurrentPlayer:
                            ((gameController.state as GamePlayingState)
                                    .gameState
                                    .currentPlayer
                                    .id ??
                                0) ==
                            (gameController.state as GamePlayingState)
                                .gameState
                                .players[i]
                                .id,
                      ),
                  ],
                );
              },
            ),
          ),

        const SizedBox(height: 10),
      ],
    );
  }
}
