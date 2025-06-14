import 'package:flutter/material.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_ai_difficulty.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_display_options.dart';

import 'drawer_game_controls.dart';

class DrawerBody extends StatelessWidget {
  const DrawerBody(this.game, {this.onMessage, super.key});

  final QuoridorGame game;
  final void Function(String message)? onMessage;

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
            DrawerGameControls(game, onMessage: onMessage),
            DrawerAiDifficulty(game),
            DrawerDisplayOptions(game),
          ],
        ),
      ),
    );
  }
}
