import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/backend.dart';
import 'src/connection_store.dart';
import 'src/local_prefs.dart';
import 'src/platform/notifications.dart';
import 'src/platform/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // dsh's syntax highlighter: TypeScript, shell and JSON grammars load at
  // start, every other language the first time a code surface shows it.
  final highlighter = await DshSyntaxHighlighter.assets();
  // The launch token is a credential: keep it in the platform keystore on the
  // platforms that have one.
  final secure = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  final prefs = await SharedLocalPrefs.load();
  late final AppController controller;
  controller = AppController(
    backend: LiveBackend(),
    store: secure ? SecureConnectionStore() : MemoryConnectionStore(),
    platform: PlatformServices.current(),
    highlighter: highlighter,
    prefs: prefs,
    notifications: PlatformNotificationService(
      strings: () {
        String a(String key) => controller.i18n.t(appNamespace, key);
        return NoticeStrings(
          pendingChannel: a('notice.channel.pending'),
          pendingChannelDescription: a('notice.channel.pending.description'),
          watchingChannel: a('notice.channel.watching'),
          watchingChannelDescription: a('notice.channel.watching.description'),
        );
      },
    ),
  );
  runApp(WhaleeApp(controller: controller));
  unawaited(controller.restore());
}
