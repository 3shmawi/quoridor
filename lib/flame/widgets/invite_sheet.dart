import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/app_strings.dart';
import '../services/online/invite/invite_link.dart';

/// Shows how to bring a friend into the game with [code]: a QR code any
/// phone camera can scan, the code itself, and the link to copy.
///
/// Resolves to true when the link was copied.
Future<bool> showInviteSheet(BuildContext context, String code) async {
  final copied = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => InviteSheet(code: code),
  );
  return copied ?? false;
}

class InviteSheet extends StatelessWidget {
  const InviteSheet({super.key, required this.code});

  final String code;

  Future<void> _copyLink(BuildContext context) async {
    final link = InviteLink.forCode(code);
    await Clipboard.setData(
      ClipboardData(text: context.l10n.inviteMessage('$link', code)),
    );
    HapticFeedback.lightImpact();
    if (context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final link = InviteLink.forCode(code);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: media.padding.bottom + 16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              context.l10n.inviteTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.inviteScanHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 20),
            // Springs in, to draw the eye to what is to be scanned.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  // Always dark on white: cameras read that best, and in dark
                  // mode a light square stands out as the thing to scan.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: QrImageView(
                  key: const Key('inviteQr'),
                  data: '$link',
                  size: 210,
                  padding: EdgeInsets.zero,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  semanticsLabel: context.l10n.inviteTitle,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E1B4B),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E1B4B),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // The code, for typing by hand, in two easy halves.
            SelectableText(
              '${code.substring(0, 3)} ${code.substring(3)}',
              key: const Key('inviteCode'),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              link.host,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('copyInvite'),
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.link_rounded),
              label: Text(context.l10n.copyInviteLink),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
