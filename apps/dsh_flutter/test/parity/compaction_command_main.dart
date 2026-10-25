// Synthetic native interaction fixture; no host, model or connection store.
import 'dart:io' show Platform;

import 'package:dsh_conversation/dsh_conversation.dart';
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
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  final zh =
      const String.fromEnvironment('PARITY_LOCALE') == 'zh' ||
      (Platform.environment['LC_ALL'] ?? '').startsWith('zh');
  final i18n = DshI18n(zh ? DshLocale.zh : DshLocale.en);
  final brightness = dark ? Brightness.dark : Brightness.light;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  final long = List.generate(
    50,
    (i) => 'Paragraph $i: preserve this synthetic fact.',
  ).join('\n\n');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 512,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CommandView(
                      data: const CommandData(
                        seq: 1,
                        time: 1,
                        commandId: 'ordinary',
                        name: 'status',
                        outcome: CommandOutcome(
                          kind: 'error',
                          text: 'First line\n<tag> **literal**',
                        ),
                      ),
                      i18n: i18n,
                    ),
                    const SizedBox(height: 16),
                    ManualCompactionView(
                      data: const ManualCompactionData(
                        CommandData(
                          seq: 2,
                          time: 2,
                          commandId: 'manual',
                          name: 'compact',
                          outcome: CommandOutcome(
                            kind: 'success',
                            text: 'Manual settlement',
                          ),
                        ),
                        CompactionData(
                          seq: 4,
                          time: 4,
                          summary:
                              '## Summary\n\nRemember **this** synthetic fact.',
                          shadowedItemCount: 2,
                          shadowedTokenCount: 125,
                        ),
                      ),
                      i18n: i18n,
                    ),
                    const SizedBox(height: 16),
                    CompactionView(
                      data: CompactionData(
                        seq: 6,
                        time: 6,
                        summary: long,
                        shadowedItemCount: 50,
                        shadowedTokenCount: 2500,
                      ),
                      i18n: i18n,
                    ),
                    const SizedBox(height: 16),
                    ManualCompactionView(
                      data: const ManualCompactionData(
                        CommandData(
                          seq: 7,
                          time: 7,
                          commandId: 'running',
                          name: 'compact',
                        ),
                        null,
                      ),
                      i18n: i18n,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
