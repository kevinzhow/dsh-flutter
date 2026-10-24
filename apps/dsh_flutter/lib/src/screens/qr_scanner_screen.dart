import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons, Scaffold;
import 'package:flutter/widgets.dart';

import '../launch_link.dart';

/// Why a camera could not give pictures.
enum CameraProblem {
  /// The camera permission was refused.
  denied,

  /// No camera, or it failed to start.
  unavailable,
}

/// The camera and its QR decoder behind the scanner screen. The phone build
/// uses `mobile_scanner` (Android CameraX with the bundled ML Kit decoder, iOS
/// AVFoundation/Vision); tests use a fake that emits decoded strings.
abstract interface class QrCamera {
  /// A live preview that reports every decoded QR text through [onCode] and
  /// draws [problem] instead when the camera cannot run.
  Widget preview(
    BuildContext context, {
    required void Function(String raw) onCode,
    required Widget Function(CameraProblem problem) problem,
  });
}

/// The pairing scanner: the camera full screen, a hint, and a way out. Only a
/// QR code that is a complete launch link ends it (see [LaunchLink.parse]);
/// anything else shows a short notice and scanning goes on. The decoded text
/// holds the launch token, so it is never shown or logged.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.camera,
    required this.i18n,
    required this.openSystemSettings,
    this.noticeFor = const Duration(seconds: 3),
  });

  final QrCamera camera;
  final DshI18n i18n;
  final VoidCallback openSystemSettings;

  /// How long "that is not a launch link" stays on screen.
  final Duration noticeFor;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _notLink = false;
  bool _done = false;
  Timer? _notice;

  String _a(String key) => widget.i18n.t(appNamespace, key);

  @override
  void dispose() {
    _notice?.cancel();
    super.dispose();
  }

  void _onCode(String raw) {
    if (_done) return;
    try {
      LaunchLink.parse(raw);
    } on FormatException {
      setState(() => _notLink = true);
      _notice?.cancel();
      _notice = Timer(widget.noticeFor, () {
        if (mounted) setState(() => _notLink = false);
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop(raw);
  }

  Widget _problem(CameraProblem problem) {
    final theme = context.dsh;
    final denied = problem == CameraProblem.denied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DshSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              denied ? _a('pairing.scan.denied') : _a('pairing.scan.failed'),
              key: const ValueKey('scan-problem'),
              textAlign: TextAlign.center,
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(color: theme.labelPrimary),
            ),
            if (denied) ...[
              const SizedBox(height: DshSpace.lg),
              DshButton(
                key: const ValueKey('scan-open-settings'),
                variant: DshButtonVariant.outline,
                onPressed: widget.openSystemSettings,
                child: Text(_a('pairing.scan.openSettings')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Scaffold(
      backgroundColor: theme.bgBase,
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.camera.preview(
              context,
              onCode: _onCode,
              problem: _problem,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(DshSpace.sm),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.bgBase.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(theme.radiusMd),
                  ),
                  child: Row(
                    children: [
                      DshIconButton(
                        key: const ValueKey('scan-close'),
                        icon: Icons.close,
                        plain: true,
                        semanticLabel: _a('pairing.scan.close'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: DshSpace.sm),
                      Text(
                        _a('pairing.scan.title'),
                        style: theme
                            .textStyle('--dsw-font-m-18')
                            .copyWith(color: theme.labelPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: DshSpace.lg,
            right: DshSpace.lg,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: DshSpace.xl),
                child: Container(
                  padding: const EdgeInsets.all(DshSpace.md),
                  decoration: BoxDecoration(
                    color: theme.bgBase.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(theme.radiusMd),
                  ),
                  child: Text(
                    _notLink
                        ? _a('pairing.scan.notLink')
                        : _a('pairing.scan.hint'),
                    key: ValueKey(_notLink ? 'scan-not-link' : 'scan-hint'),
                    textAlign: TextAlign.center,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelPrimary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
