import 'package:flutter/material.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_display_options.dart';

import '../../controller/game_controller.dart';
import 'drawer_game_controls.dart';

class DrawerBody extends StatelessWidget {
  const DrawerBody({this.onMessage, this.gameController, super.key});

  final void Function(String message)? onMessage;
  final GameController? gameController;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 24,
          children: [
            DrawerGameControls(
              onMessage: onMessage,
              gameController: gameController,
            ),
            // DrawerAiDifficulty(gameController: gameController),
            DrawerDisplayOptions(gameController: gameController),
          ],
        ),
      ),
    );
  }
}
