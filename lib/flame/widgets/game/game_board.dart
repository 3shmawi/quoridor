import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../constants.dart';
import '../../controller/game_controller.dart';
import '../../controller/game_states.dart';
import '../../components/board_component.dart';

class GameBoard extends StatelessWidget {
  final GameController? gameController;

  const GameBoard({super.key, this.gameController});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameController, GameStates>(
      builder: (context, state) {
        if (state is! GamePlayingState) {
          return const SizedBox.shrink();
        }

        return Center(
          child: ValueListenableBuilder(
            valueListenable: cellSizeNotifier,
            builder: (context, value, child) {
              return SizedBox(
                width:
                    (value + GameConstants.cellSpacing) *
                        GameConstants.boardSize +
                    GameConstants.boardPadding * 2,
                height:
                    (value + GameConstants.cellSpacing) *
                        GameConstants.boardSize +
                    GameConstants.boardPadding * 2,
                child: GameWidget.controlled(
                  gameFactory: () => _BoardGame(gameController: gameController),
                  overlayBuilderMap: {
                    'gameController': (context, game) => gameController != null
                        ? BlocBuilder<GameController, GameStates>(
                            builder: (context, state) {
                              // Update game state from controller
                              if (state is GamePlayingState) {
                                (game as _BoardGame?)?.updateFromController();
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
      },
    );
  }
}

class _BoardGame extends FlameGame with TapCallbacks {
  final GameController? gameController;
  late BoardComponent _boardComponent;

  _BoardGame({this.gameController}) {
    _boardComponent = BoardComponent(gameController: gameController);
    _boardComponent.onMoveAttempted = _handleMoveAttempt;
    _boardComponent.onWallPlaceAttempted = _handleWallPlaceAttempt;
    add(_boardComponent);
  }

  void _handleMoveAttempt(Position newPosition) {
    if (gameController != null) {
      gameController!.add(MakePawnMove(newPosition));
    }
  }

  void _handleWallPlaceAttempt(Wall wall) {
    if (gameController != null) {
      gameController!.add(PlaceWall(wall));
    }
  }

  void updateFromController() {
    if (gameController != null) {
      final currentState = gameController!.state;
      if (currentState is GamePlayingState) {
        _boardComponent.updateFromState(currentState);
      }
    }
  }

  @override
  bool onTapDown(TapDownEvent event) {
    // Convert screen coordinates to local board coordinates
    final localPosition = event.localPosition - _boardComponent.position;

    // Pass tap to board component
    _boardComponent.handleTap(localPosition);
    return true;
  }

  @override
  Color backgroundColor() => Colors.transparent;
}
