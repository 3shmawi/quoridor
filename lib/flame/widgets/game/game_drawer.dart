import 'package:flutter/material.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_body.dart';
import 'package:quoridor/flame/widgets/drawer/drawer_footer.dart';

import '/flame/game/quoridor_game.dart';
import '../../controller/game_controller.dart';
import '../drawer/drawer_header.dart';

/// A custom drawer widget for the Quoridor game.
///
/// This widget provides a navigation menu with game controls, display options,
/// and other settings. It's organized into sections for better user experience.
class GameDrawer extends StatelessWidget {
  /// Callback function when new game is requested
  final QuoridorGame game;
  final Function(String)? onMessage;
  final GameController? gameController;

  /// Creates a new instance of [GameDrawer].
  const GameDrawer({
    super.key,
    required this.game,
    this.onMessage,
    this.gameController,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // Menu Header
            DrawerAppHeader(),

            // Menu Body
            DrawerBody(game, gameController: gameController),

            // Menu Footer
            DrawerFooter(),
          ],
        ),
      ),
    );
  }
}
