import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/update/update_checker.dart';
import '../services/update/update_service.dart';

/// Lays the update notice over the whole app.
///
/// Optional: a card at the top, and the game keeps running under it.
/// Forced: the same card over a barrier that cannot be dismissed, with no
/// "Later", so nothing underneath can be touched.
class UpdateOverlay extends StatelessWidget {
  const UpdateOverlay({super.key, required this.child, this.service});

  final Widget child;
  final UpdateService? service;

  @override
  Widget build(BuildContext context) {
    final updates = service ?? UpdateService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([
        updates.available,
        updates.postponed,
        updates.whatsNew,
      ]),
      builder: (context, _) {
        final info = updates.available.value;
        final whatsNew = updates.whatsNew.value;
        final showUpdate =
            info != null && (info.forced || !updates.postponed.value);

        return Stack(
          children: [
            child,
            if (showUpdate && info.forced)
              const ModalBarrier(dismissible: false, color: Colors.black54),
            if (showUpdate)
              _TopCard(
                child: UpdateCard(
                  info: info,
                  onLater: info.forced ? null : updates.later,
                  onUpdate: updates.update,
                ),
              )
            else if (whatsNew != null)
              _TopCard(
                child: WhatsNewCard(
                  info: whatsNew,
                  onClose: () => updates.whatsNew.value = null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The notice itself. [onLater] is null when the update is forced, and the
/// button is then not shown at all.
class UpdateCard extends StatelessWidget {
  const UpdateCard({
    super.key,
    required this.info,
    required this.onUpdate,
    this.onLater,
  });

  final UpdateInfo info;
  final VoidCallback onUpdate;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final notes = info.notesFor(l10n.locale.languageCode);

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.updateAvailableTitle(info.version),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            if (info.forced) ...[
              const SizedBox(height: 8),
              Text(
                l10n.updateForced,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onLater != null)
                  TextButton(onPressed: onLater, child: Text(l10n.updateLater)),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onUpdate,
                  child: Text(
                    // Only a build from GitHub Releases is downloaded; a
                    // store or the site updates in place.
                    info.route == UpdateRoute.download
                        ? l10n.updateDownload
                        : l10n.updateReload,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once, on the first run after an update.
class WhatsNewCard extends StatelessWidget {
  const WhatsNewCard({super.key, required this.info, required this.onClose});

  final UpdateInfo info;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.whatsNewIn(info.version),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              info.notesFor(l10n.locale.languageCode),
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.8)),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onClose, child: Text(l10n.gotIt)),
            ),
          ],
        ),
      ),
    );
  }
}
