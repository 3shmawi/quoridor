import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../../services/localizations.dart';
import '../../game/quoridor_game.dart';
import '../../services/ai_service.dart';

class DrawerDifficultyItem extends StatefulWidget {
  const DrawerDifficultyItem({
    required this.difficulty,
    required this.game,
    super.key,
  });

  final AIDifficulty difficulty;
  final QuoridorGame game;

  @override
  State<DrawerDifficultyItem> createState() => _DrawerDifficultyItemState();
}

class _DrawerDifficultyItemState extends State<DrawerDifficultyItem> {
  void _closeMenu() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  void _changeDifficulty(AIDifficulty difficulty) {
    setState(() {
      widget.game.setDifficulty(difficulty);
    });
    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    bool isSelected = widget.game.gameState.difficulty == widget.difficulty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        onTap: () => _changeDifficulty(widget.difficulty),
        leading: Icon(
          _getDifficultyIcon(widget.difficulty),
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        title: Text(
          widget.difficulty.name.getString(context).toUpperCase(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          _getDifficultyDescription(widget.difficulty),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
      ),
    );
  }

  IconData _getDifficultyIcon(AIDifficulty difficulty) {
    switch (difficulty) {
      case AIDifficulty.easy:
        return Icons.sentiment_satisfied;
      case AIDifficulty.medium:
        return Icons.sentiment_neutral;
      case AIDifficulty.hard:
        return Icons.sentiment_very_dissatisfied;
    }
  }

  String _getDifficultyDescription(AIDifficulty difficulty) {
    switch (difficulty) {
      case AIDifficulty.easy:
        return AppLocale.easyDescription.getString(context);
      case AIDifficulty.medium:
        return AppLocale.mediumDescription.getString(context);
      case AIDifficulty.hard:
        return AppLocale.hardDescription.getString(context);
    }
  }
}
