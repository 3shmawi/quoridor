import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:quoridor/flame/controller/game_states.dart';
import 'package:quoridor/flame/widgets/game/game_player_info_widget.dart';
import 'package:quoridor/flame/widgets/game/game_wall_controls.dart';

import '../../controller/game_controller.dart';
import '../../constants.dart';
import 'game_board.dart';

class GameSmallScreen extends StatefulWidget {
  final GameController? gameController;

  const GameSmallScreen({super.key, this.gameController});

  @override
  State<GameSmallScreen> createState() => _GameSmallScreenState();
}

class _GameSmallScreenState extends State<GameSmallScreen> {
  late final gameController = context.read<GameController>();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameController, GameStates>(
      builder: (context, state) {
        if (state is! GamePlayingState) {
          return const SizedBox.shrink();
        }

        final gameState = state.gameState;

        return Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Divider(),
            GameWallControls(gameController: widget.gameController),
            Expanded(child: GameBoard(gameController: widget.gameController)),
            IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: isInitializedProvider,
                builder: (context, value, child) {
                  if (!value) return const SizedBox.shrink();
                  return GridView(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 0,
                          crossAxisSpacing: 16,
                          childAspectRatio: 2,
                        ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (int i = 0; i < gameState.players.length; i++)
                        GamePlayerInfoWidget(
                          playerId: gameState.players[i].id,
                          name: gameState.players[i].name,
                          wallsRemaining: gameState.players[i].wallsRemaining,
                          isCurrentPlayer:
                              gameState.currentPlayer.id ==
                              gameState.players[i].id,
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}
