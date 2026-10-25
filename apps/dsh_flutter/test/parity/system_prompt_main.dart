// Standalone native widget fixture. No connection store, host or model calls.
// flutter build linux -t test/parity/system_prompt_main.dart
import 'dart:io' show Platform;

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart';

import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final brightness =
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark'
      ? Brightness.dark
      : Brightness.light;
  final locale = (Platform.environment['LC_ALL'] ?? '').startsWith('zh')
      ? DshLocale.zh
      : DshLocale.en;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  final long = List.generate(
    100,
    (i) => 'line $i: preserve the original text',
  ).join('\n');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 480,
                child: SelectionArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SystemPromptView(
                        text: 'You are a helpful assistant.\nKeep <tags> literal.',
                        i18n: DshI18n(locale),
                      ),
                      const SizedBox(height: 16),
                      SystemPromptView(
                        text: long,
                        update: true,
                        i18n: DshI18n(locale),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
