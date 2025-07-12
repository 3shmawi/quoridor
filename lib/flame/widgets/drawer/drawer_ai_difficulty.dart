import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_difficulty_item.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_menu_section.dart';

import '../../controller/game_controller.dart';
import '../../services/localizations.dart';

class DrawerAiDifficulty extends StatelessWidget {
  const DrawerAiDifficulty({this.gameController, super.key});

  final GameController? gameController;

  @override
  Widget build(BuildContext context) {
    return DrawerMenuSection(
      title: AppLocale.aiDifficulty.getString(context),
      children: [
        DrawerDifficultyItem(
          difficulty: AIDifficulty.easy,
          gameController: gameController,
        ),
        DrawerDifficultyItem(
          difficulty: AIDifficulty.medium,
          gameController: gameController,
        ),
        DrawerDifficultyItem(
          difficulty: AIDifficulty.hard,
          gameController: gameController,
        ),
      ],
    );
  }
}
