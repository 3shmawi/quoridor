import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_difficulty_item.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_menu_section.dart';

import '../../controller/game_controller.dart';
import '../../game/quoridor_game.dart';
import '../../services/localizations.dart';

class DrawerAiDifficulty extends StatelessWidget {
  const DrawerAiDifficulty(this.game, {this.gameController, super.key});

  final QuoridorGame game;
  final GameController? gameController;

  @override
  Widget build(BuildContext context) {
    return DrawerMenuSection(
      title: AppLocale.aiDifficulty.getString(context),
      children: [
        DrawerDifficultyItem(
            difficulty: AIDifficulty.easy,
            game: game,
            gameController: gameController),
        DrawerDifficultyItem(
            difficulty: AIDifficulty.medium,
            game: game,
            gameController: gameController),
        DrawerDifficultyItem(
            difficulty: AIDifficulty.hard,
            game: game,
            gameController: gameController),
      ],
    );
  }
}
