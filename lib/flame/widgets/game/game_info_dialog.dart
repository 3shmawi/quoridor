import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../services/localizations.dart';

/// A dialog widget that displays information about how to play Quoridor.
///
/// This widget provides a comprehensive guide about the game rules,
/// objectives, and gameplay mechanics in an organized and visually appealing format.
class GameInfoDialog extends StatelessWidget {
  /// Creates a new instance of [GameInfoDialog].
  const GameInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: localization.currentLocale?.languageCode == 'ar'
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(AppLocale.howToPlay.getString(context))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoSection(
                context,
                '🎯 ${AppLocale.objective.getString(context)}',
                AppLocale.objectiveDescription.getString(context),
              ),
              _buildInfoSection(
                context,
                '🎮 ${AppLocale.yourTurn.getString(context)}',
                AppLocale.yourTurnDescription.getString(context),
              ),
              _buildInfoSection(
                context,
                '🚶 ${AppLocale.movement.getString(context)}',
                AppLocale.movementDescription.getString(context),
              ),
              _buildInfoSection(
                context,
                '🧱 ${AppLocale.walls.getString(context)}',
                AppLocale.wallsDescription.getString(context),
              ),
              _buildInfoSection(
                context,
                '🏆 ${AppLocale.winning.getString(context)}',
                AppLocale.winningDescription.getString(context),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocale.gotIt.getString(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
