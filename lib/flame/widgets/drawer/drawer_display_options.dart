import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/controller/game_states.dart';
import 'package:quoridor/flame/services/local_storage.dart';
import 'package:quoridor/flame/services/localizations.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_menu_section.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_switch_item.dart';
import 'package:quoridor/theme.dart';

import '../../controller/game_controller.dart';

class DrawerDisplayOptions extends StatefulWidget {
  const DrawerDisplayOptions({this.gameController, super.key});

  final GameController? gameController;

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
    if (widget.gameController != null) {
      widget.gameController!.add(ToggleValidMoves());
    }

    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameController, GameStates>(
      builder: (context, state) {
        final showValidMoves = state is GamePlayingState
            ? state.gameState.showValidMoves
            : false;

        return DrawerMenuSection(
          title: AppLocale.displayOptions.getString(context),
          children: [
            DrawerSwitchItem(
              icon: CupertinoIcons.mic,
              title: AppLocale.soundEnabled.getString(context),
              subtitle: AppLocale.soundEnabledSubtitles.getString(context),
              value: CacheHelper.getData(key: "soundEnabled") ?? true,
              onChanged: () {
                CacheHelper.saveData(
                  key: "soundEnabled",
                  value: !(CacheHelper.getData(key: "soundEnabled") ?? true),
                );
                _closeMenu();
              },
            ),
            DrawerSwitchItem(
              icon: Icons.visibility,
              title: AppLocale.showValidMoves.getString(context),
              subtitle: AppLocale.highlightPossibleMoves.getString(context),
              value: showValidMoves,
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
      },
    );
  }
}
