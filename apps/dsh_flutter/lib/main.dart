import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:dsh_client/dsh_client.dart' show HostTrust;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/backend.dart';
import 'src/connection_store.dart';
import 'src/launch_link.dart';
import 'src/local_prefs.dart';
import 'src/platform/camera_scanner.dart';
import 'src/platform/notifications.dart';
import 'src/platform/pinned_fonts.dart';
import 'src/platform/platform_services.dart';
import 'src/platform/shortcut_storage.dart';
import 'src/platform/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  // dsh's syntax highlighter: TypeScript, shell and JSON grammars load at
  // start, every other language the first time a code surface shows it.
  final highlighter = await DshSyntaxHighlighter.assets();
  // The launch token is a credential: keep it in the platform keystore on the
  // platforms that have one.
  final secure = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  final prefs = await SharedLocalPrefs.load();
  // The desktop window (title bar, caption buttons, size) and its keyboard
  // commands; null on phones and tablets.
  final window = await WindowChrome.init();
  final shortcuts = window == null
      ? null
      : ShortcutService(
          runtime: ShortcutRuntime.desktop,
          platform: currentShortcutPlatform(),
          storage: await FileShortcutStorage.inSupportDirectory(),
        );
  late final AppController controller;
  final camera = Platform.isAndroid || Platform.isIOS;
  controller = AppController(
    backend: LiveBackend(trust: HostTrust(pins: PrefsPinStore(prefs))),
    scanner: camera
        ? CameraLaunchScanner(
            navigator: () => controller.navigatorKey,
            i18n: () => controller.i18n,
          )
        : const NoScanner(),
    store: secure ? SecureConnectionStore() : MemoryConnectionStore(),
    platform: PlatformServices.current(),
    highlighter: highlighter,
    prefs: prefs,
    shortcuts: shortcuts,
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
  runApp(
    WhaleeApp(
      controller: controller,
      chrome: window?.chrome,
      onTitle: window?.setTitle,
    ),
  );
  unawaited(controller.restore());
}
