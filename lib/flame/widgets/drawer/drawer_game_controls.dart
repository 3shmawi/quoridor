import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/services/localizations.dart';
import '../../controller/game_controller.dart';
import '../../game/quoridor_game.dart';
import '../../services/firebase_service.dart';
import 'drawer_menu_item.dart';
import 'drawer_menu_section.dart';

class DrawerGameControls extends StatefulWidget {
  const DrawerGameControls(
    this.game, {
    this.onMessage,
    this.gameController,
    super.key,
  });

  final QuoridorGame game;
  final void Function(String message)? onMessage;
  final GameController? gameController;

  @override
  State<DrawerGameControls> createState() => _DrawerGameControlsState();
}

class _DrawerGameControlsState extends State<DrawerGameControls> {
  void _closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  void _newGame() {
    if (widget.gameController != null) {
      widget.gameController!.add(StartNewGame());
    } else {
      widget.game.newGame();
    }
    _closeMenu();
  }

  Future<void> _saveGame() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      widget.onMessage?.call(
        AppLocale.pleaseLogInToSaveGame.getString(context),
      );

      _closeMenu();
      return;
    }

    if (widget.gameController != null) {
      widget.gameController!.add(SaveGame());
    } else {
      final gameId = await FirebaseService.saveGame(widget.game.gameState!);
      if (gameId != null) {
        widget.onMessage?.call(
          AppLocale.gameSavedSuccessfullyWithId.getString(context),
        );
      } else {
        widget.onMessage?.call(AppLocale.failedToSaveGame.getString(context));
      }
    }
    _closeMenu();
  }

  void _togglePlayerMode() {
    if (widget.gameController != null) {
      widget.gameController!.add(TogglePlayerMode());
    } else {
      widget.game.togglePlayerMode();
    }
    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerMenuSection(
      title: AppLocale.gameControls.getString(context),
      children: [
        DrawerMenuItem(
          icon: Icons.refresh,
          title: AppLocale.newGame.getString(context),
          subtitle: AppLocale.startAFreshGame.getString(context),
          onTap: _newGame,
        ),
        DrawerMenuItem(
          icon: Icons.save,
          title: AppLocale.saveGame.getString(context),
          subtitle: AppLocale.saveCurrentProgress.getString(context),
          onTap: _saveGame,
        ),
        DrawerMenuItem(
          icon: Icons.people,
          title: AppLocale.togglePlayerMode.getString(context),
          subtitle: widget.game.gameState?.currentPlayer.isAI ?? false
              ? AppLocale.switchToTwoPlayers.getString(context)
              : AppLocale.switchToAI.getString(context),
          onTap: _togglePlayerMode,
        ),
      ],
    );
  }
}
