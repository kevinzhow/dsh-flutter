import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/backend.dart';
import 'src/connection_store.dart';
import 'src/platform/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // dsh's syntax highlighter: TypeScript, shell and JSON grammars load at
  // start, every other language the first time a code surface shows it.
  final highlighter = await DshSyntaxHighlighter.assets();
  // The launch token is a credential: keep it in the platform keystore on the
  // platforms that have one.
  final secure = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  final controller = AppController(
    backend: LiveBackend(),
    store: secure ? SecureConnectionStore() : MemoryConnectionStore(),
    platform: PlatformServices.current(),
    highlighter: highlighter,
  );
  runApp(WhaleeApp(controller: controller));
  unawaited(controller.restore());
}
