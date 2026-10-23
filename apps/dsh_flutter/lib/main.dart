import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/backend.dart';
import 'src/connection_store.dart';
import 'src/platform/platform_services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The launch token is a credential: keep it in the platform keystore on the
  // platforms that have one.
  final secure = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  final controller = AppController(
    backend: LiveBackend(),
    store: secure ? SecureConnectionStore() : MemoryConnectionStore(),
    platform: PlatformServices.current(),
  );
  runApp(WhaleeApp(controller: controller));
  controller.restore();
}
