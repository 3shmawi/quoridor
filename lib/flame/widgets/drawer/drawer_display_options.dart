import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/services/localizations.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_menu_section.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_switch_item.dart';
import 'package:quoridor/theme.dart';

import '../../game/quoridor_game.dart';

class DrawerDisplayOptions extends StatefulWidget {
  const DrawerDisplayOptions(this.game, {super.key});

  final QuoridorGame game;

  @override
  State<DrawerDisplayOptions> createState() => _DrawerDisplayOptionsState();
}

class _DrawerDisplayOptionsState extends State<DrawerDisplayOptions> {
  void _closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  void _toggleValidMoves() {
    widget.game.showValidMoves();

    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerMenuSection(
      title: AppLocale.displayOptions.getString(context),
      children: [
        DrawerSwitchItem(
          icon: Icons.visibility,
          title: AppLocale.showValidMoves.getString(context),
          subtitle: AppLocale.highlightPossibleMoves.getString(context),
          value: widget.game.gameState.showValidMoves,
          onChanged: _toggleValidMoves,
        ),
        DrawerSwitchItem(
          icon: Icons.dark_mode_outlined,
          title: AppLocale.darkMode.getString(context),
          subtitle: AppLocale.toggleDarkMode.getString(context),
          value: isDarkModeNotifier.value,
          onChanged: () {
            isDarkModeNotifier.value = !isDarkModeNotifier.value;
          },
        ),
        DrawerSwitchItem(
          icon: Icons.language,
          title: AppLocale.englishMode.getString(context),
          subtitle: AppLocale.toggleLanguageMode.getString(context),
          value: localization.currentLocale?.languageCode == 'en',
          onChanged: () {
            if (localization.currentLocale?.languageCode == 'en') {
              localization.translate('ar');
            } else {
              localization.translate('en');
            }
          },
        ),
      ],
    );
  }
}
