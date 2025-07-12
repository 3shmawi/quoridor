import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/services/localizations.dart';
import 'package:quoridor/flame/widgets/game/game_board.dart';
import 'package:quoridor/flame/widgets/game/game_player_info_widget.dart';
import 'package:quoridor/flame/widgets/game/game_wall_controls.dart';

import '../../controller/game_controller.dart';
import '../../game/quoridor_game.dart';
import 'game_app_bar.dart';

class GameWideScreen extends StatelessWidget {
  final QuoridorGame game;
  final GameController? gameController;

  const GameWideScreen(this.game, {super.key, this.gameController});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border(
                right: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                GameAppBar(),
                const SizedBox(height: 20),
                ValueListenableBuilder(
                  valueListenable: isInitializedProvider,
                  builder: (context, value, child) {
                    if (!value) return const SizedBox.shrink();
                    return Wrap(
                      children: [
                        for (
                          int i = 0;
                          i < (game.gameState?.players.length ?? 0);
                          i++
                        ) ...[
                          GamePlayerInfoWidget(
                            playerId: game.gameState!.players[i].id,
                            name: game.gameState!.players[i].name,
                            wallsRemaining:
                                game.gameState!.players[i].wallsRemaining,
                            isCurrentPlayer:
                                (game.gameState?.currentPlayer.id ?? 0) ==
                                game.gameState!.players[i].id,
                          ),
                          if (i < (game.gameState?.players.length ?? 0) - 1)
                            const SizedBox(height: 16),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        GameBoard(game, gameController: gameController),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  "Wall Controls",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                    thickness: 1,
                    height: 20,
                  ),
                ),
                Spacer(),
                GameWallControls(
                  game: game,
                  isWideScreen: true,
                  gameController: gameController,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
