// Synthetic native fixture over the real Session, ChatView and settings seats.
// No host, connection store or model calls.
import 'dart:io' show Platform;

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
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
  final prefs = ChatPreferences(desktop: true);
  final slots = SlotRegistry();
  for (final slot in DshSlots.all) {
    slots.declare(slot);
  }
  registerChatFeature(slots, i18n: () => i18n, preferences: prefs);
  final owner = testSessionOwner('work-details-fixture');
  EventEntry ev(
    int seq,
    String type,
    Map<String, Object?> data, {
    bool surface = false,
  }) => EventEntry({
    'seq': seq,
    'time': 1000 + seq * 1000,
    'type': type,
    'data': data,
    if (surface) 'surfaceOp': 'append',
  });
  owner.session.eventSource.replace([
    ev(1, 'turn/start', {'turn': 1}),
    ev(2, 'step/start', {'turn': 1, 'step': 1}),
    ev(3, 'user/message', {
      'turn': 1,
      'step': 1,
      'id': 'input',
      'source': {'kind': 'user'},
      'content': [
        {'type': 'text', 'text': 'Synthetic task'},
      ],
    }, surface: true),
    ev(4, 'assistant/message', {
      'turn': 1,
      'step': 1,
      'message': {
        'id': 'progress',
        'content': [
          {
            'type': 'reasoning',
            'text': 'Compare the synthetic choices.\n\nKeep the complete reasoning available.',
          },
          {
            'type': 'text',
            'text': List.generate(
              20,
              (i) => 'Progress $i: retain this synthetic detail.',
            ).join('\n\n'),
          },
        ],
      },
    }, surface: true),
    ev(5, 'step/end', {'turn': 1, 'step': 1}),
    ev(6, 'step/start', {'turn': 1, 'step': 2}),
    ev(7, 'assistant/message', {
      'turn': 1,
      'step': 2,
      'message': {
        'id': 'final',
        'content': [
          {'type': 'text', 'text': 'Final synthetic answer remains visible.'},
        ],
      },
    }, surface: true),
    ev(8, 'step/end', {'turn': 1, 'step': 2}),
    ev(9, 'turn/end', {
      'turn': 1,
      'reason': {'kind': 'completed'},
    }),
  ], false);
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
          child: Column(
            children: [
              SizedBox(
                height: 210,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: WorkDetailsSettings(preferences: prefs, i18n: i18n),
                ),
              ),
              Expanded(child: slots.renderList(viewSlot, owner).first),
            ],
          ),
        ),
      ),
    ),
  );
}
