import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../services/localizations.dart';
import 'game_info_dialog.dart';

/// A custom app bar widget for the Quoridor game.
///
/// This widget displays the game title, menu button, and game info button.
/// It provides a consistent header for the game interface.
class GameAppBar extends StatefulWidget {
  /// Callback function when the game info button is pressed

  /// Creates a new instance of [GameAppBar].
  const GameAppBar({super.key});

  @override
  State<GameAppBar> createState() => _GameAppBarState();
}

class _GameAppBarState extends State<GameAppBar> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Menu Button
        Builder(
          builder: (context) {
            return IconButton(
              onPressed: Scaffold.of(context).openDrawer,
              icon: Icon(
                Icons.menu,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.1),
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          },
        ),

        const SizedBox(width: 16),

        // Game Title
        Expanded(
          child: Center(
            child: Text(
              AppLocale.title.getString(context),
              overflow: TextOverflow.ellipsis,
              textDirection:
                  Localizations.localeOf(context).languageCode == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
          ),
        ),

        // Game Info Button
        IconButton(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => GameInfoDialog(),
          ),
          icon: Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.secondary.withOpacity(0.1),
            foregroundColor: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    );
  }
}
