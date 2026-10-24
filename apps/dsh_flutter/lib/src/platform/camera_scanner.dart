import 'package:app_settings/app_settings.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../launch_link.dart';
import '../screens/qr_scanner_screen.dart';

/// [QrCamera] over the `mobile_scanner` plugin: QR codes only, the back
/// camera, the permission asked by the plugin when the preview starts.
class MobileScannerCamera implements QrCamera {
  const MobileScannerCamera();

  @override
  Widget preview(
    BuildContext context, {
    required void Function(String raw) onCode,
    required Widget Function(CameraProblem problem) problem,
  }) => _Preview(onCode: onCode, problem: problem);
}

class _Preview extends StatefulWidget {
  const _Preview({required this.onCode, required this.problem});

  final void Function(String raw) onCode;
  final Widget Function(CameraProblem problem) problem;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
    controller: _controller,
    onDetect: (capture) {
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue;
        if (raw != null) widget.onCode(raw);
      }
    },
    errorBuilder: (context, error) => widget.problem(
      error.errorCode == MobileScannerErrorCode.permissionDenied
          ? CameraProblem.denied
          : CameraProblem.unavailable,
    ),
  );
}

/// The phone build's [LaunchScanner]: pushes the scanner screen over the app
/// and returns the launch link it decoded.
class CameraLaunchScanner implements LaunchScanner {
  CameraLaunchScanner({
    required this.navigator,
    required this.i18n,
    this.camera = const MobileScannerCamera(),
  });

  final GlobalKey<NavigatorState> Function() navigator;
  final DshI18n Function() i18n;
  final QrCamera camera;

  @override
  bool get available => true;

  @override
  Future<String?> scan() async {
    final nav = navigator().currentState;
    if (nav == null) return null;
    return nav.push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => QrScannerScreen(
          camera: camera,
          i18n: i18n(),
          openSystemSettings: () => AppSettings.openAppSettings(),
        ),
      ),
    );
  }
}
