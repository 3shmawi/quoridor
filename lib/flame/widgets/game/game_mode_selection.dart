import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';

import '../../controller/game_controller.dart';
import '../../services/localizations.dart';
import '../app/copywrite.dart';

/// A bottom sheet widget for selecting the game mode in Quoridor.
///
/// This widget allows players to choose between playing against AI
/// or playing with another player on the same device.
class GameModeSelection extends StatelessWidget {
  /// Creates a new instance of [GameModeSelection].
  final QuoridorGame game;
  final Function(String)? onMessage;
  final GameController? gameController;

  const GameModeSelection({
    required this.game,
    this.onMessage,
    this.gameController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          // Title
          Text(
            AppLocale.chooseGameMode.getString(context),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 32),
          // Mode selection cards
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shrinkWrap: true,
              children: [
                _buildModeCard(
                  context,
                  icon: Icons.people,
                  title: AppLocale.twoPlayers.getString(context),
                  subtitle: AppLocale.playWithAFriendOnTheSameDevice.getString(
                    context,
                  ),
                  onTap: () {
                    if (gameController != null) {
                      // Initialize 2-player game with human players
                      gameController!.add(
                        InitializeMultiPlayerGame(
                          playerCount: 2,
                          playerNames: ['Player 1', 'Player 2'],
                        ),
                      );
                    }
                    Navigator.pop(context);
                    onMessage?.call(AppLocale.twoPlayerModeActivated);
                  },
                ),
                const SizedBox(height: 16),
                _buildModeCard(
                  context,
                  icon: Icons.groups,
                  title: '3 Players',
                  subtitle: 'Play with 2 friends',
                  onTap: () {
                    if (gameController != null) {
                      // Initialize 3-player game
                      gameController!.add(
                        InitializeMultiPlayerGame(
                          playerCount: 3,
                          playerNames: ['Player 1', 'Player 2', 'Player 3'],
                        ),
                      );
                    }
                    Navigator.pop(context);
                    onMessage?.call('3-player mode activated');
                  },
                ),
                const SizedBox(height: 16),
                _buildModeCard(
                  context,
                  icon: CupertinoIcons.group,
                  title: '4 Players',
                  subtitle: 'Play with 3 friends ',
                  onTap: () {
                    if (gameController != null) {
                      // Initialize 4-player game
                      gameController!.add(
                        InitializeMultiPlayerGame(
                          playerCount: 4,
                          playerNames: [
                            'Player 1',
                            'Player 2',
                            'Player 3',
                            'Player 4',
                          ],
                        ),
                      );
                    }
                    Navigator.pop(context);
                    onMessage?.call('4-player mode activated');
                  },
                ),
              ],
            ),
          ),
          AppCopyWrite(),
        ],
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
