import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/app_strings.dart';
import '../services/online/invite/invite_link.dart';

/// Whether this device can scan an invite's QR code itself. On the web a
/// phone's own camera opens the link, which joins just as well; desktops
/// have no camera worth pointing at a phone.
bool get canScanInvites =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Points the camera at a friend's invite and returns the room code it
/// carries, or null when the player backs out.
class ScanInvitePage extends StatefulWidget {
  const ScanInvitePage({super.key});

  @override
  State<ScanInvitePage> createState() => _ScanInvitePageState();
}

class _ScanInvitePageState extends State<ScanInvitePage> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _done = false;
  DateTime? _lastWrongCode;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final code = InviteLink.codeFromScan(raw);
      if (code != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(code);
        return;
      }
    }
    // Something else is in view: say so, but not on every frame.
    final now = DateTime.now();
    final last = _lastWrongCode;
    if (last == null || now.difference(last) > const Duration(seconds: 3)) {
      _lastWrongCode = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.scanNotInvite)));
    }
  }

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(context.l10n.scanQr),
        actions: [
          ValueListenableBuilder(
            valueListenable: _camera,
            builder: (context, state, _) => IconButton(
              tooltip: context.l10n.torch,
              onPressed: state.torchState == TorchState.unavailable
                  ? null
                  : _camera.toggleTorch,
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _CameraUnavailable(message: context.l10n.cameraUnavailable),
          ),
          const IgnorePointer(child: _Viewfinder()),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              context.l10n.scanQrHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A square to aim with: the rest of the picture is dimmed, and its corners
/// are marked.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide * 0.68;
        return CustomPaint(
          painter: _ViewfinderPainter(
            side: side,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.side, required this.color});

  final double side;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: side,
        height: side,
      ),
      const Radius.circular(24),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final corner = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const arm = 32.0;
    final r = window.outerRect;
    for (final (x, y, dx, dy) in [
      (r.left, r.top, 1.0, 1.0),
      (r.right, r.top, -1.0, 1.0),
      (r.left, r.bottom, 1.0, -1.0),
      (r.right, r.bottom, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(Offset(x, y + dy * 12), Offset(x, y + dy * arm), corner)
        ..drawLine(Offset(x + dx * 12, y), Offset(x + dx * arm, y), corner);
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.side != side || old.color != color;
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).backButtonTooltip),
            ),
          ],
        ),
      ),
    );
  }
}
