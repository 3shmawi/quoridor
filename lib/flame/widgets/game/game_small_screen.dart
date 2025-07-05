import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/services/localizations.dart';
import 'package:quoridor/flame/widgets/game/game_player_info_widget.dart';
import 'package:quoridor/flame/widgets/game/game_wall_controls.dart';

import '../../controller/game_controller.dart';
import 'game_board.dart';

class GameSmallScreen extends StatelessWidget {
  final QuoridorGame game;
  final GameController? gameController;

  const GameSmallScreen(this.game, {super.key, this.gameController});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedCrossFade(
          firstChild: GameWallControls(
            game: game,
            gameController: gameController,
          ),
          secondChild: SizedBox.shrink(),
          crossFadeState:
              !(game.gameState?.player2.isAI ?? false) &&
                  (game.gameState?.currentPlayer.id ?? 0) == 2
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: Duration(milliseconds: 500),
        ),
        Expanded(child: GameBoard(game, gameController: gameController)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: [
              AnimatedCrossFade(
                firstChild: GameWallControls(
                  game: game,
                  gameController: gameController,
                ),
                secondChild: SizedBox.shrink(),
                crossFadeState: (game.gameState?.currentPlayer.id ?? 0) == 1
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
                      children: [
                        GamePlayerInfoWidget(
                          playerId: 1,
                          name: AppLocale.player1.getString(context),
                          wallsRemaining:
                              game.gameState?.player1.wallsRemaining ?? 0,
                          isCurrentPlayer:
                              (game.gameState?.currentPlayer.id ?? 0) == 1,
                          isAI: false,
                        ),
                        GamePlayerInfoWidget(
                          playerId: 2,
                          name: AppLocale.player2.getString(context),
                          wallsRemaining:
                              game.gameState?.player2.wallsRemaining ?? 0,
                          isCurrentPlayer:
                              (game.gameState?.currentPlayer.id ?? 0) == 2,
                          isAI: game.gameState?.player2.isAI ?? false,
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
