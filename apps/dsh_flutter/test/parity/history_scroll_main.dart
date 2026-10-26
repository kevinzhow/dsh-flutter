import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

List<Map<String, Object?>> records(int from, int to) => [
  for (var turn = from; turn < to; turn++) ...[
    rec(turn * 6 + 1, 'turn/start', data: {'turn': turn + 1}),
    rec(turn * 6 + 2, 'step/start', data: {'turn': turn + 1, 'step': 1}),
    rec(
      turn * 6 + 3,
      'user/message',
      data: {
        'id': 'user-$turn',
        'role': 'user',
        'source': {'kind': 'user', 'rpcId': 'synthetic-$turn'},
        'content': [
          {'type': 'text', 'text': 'Synthetic question $turn'},
        ],
      },
      surfaceOp: 'append',
    ),
    rec(
      turn * 6 + 4,
      'assistant/message',
      data: {
        'turn': turn + 1,
        'step': 1,
        'message': {
          'id': 'assistant-$turn',
          'role': 'assistant',
          'source': {
            'kind': 'model',
            'provider': 'synthetic',
            'model': 'fixture',
          },
          'content': [
            {
              'type': 'text',
              'text':
                  'Synthetic answer $turn. Reading history must stay in place.\n\nA second paragraph for the recorded turn.',
            },
          ],
        },
        'stream': <Object?>[],
      },
      surfaceOp: 'append',
    ),
    rec(turn * 6 + 5, 'step/end', data: {'turn': turn + 1, 'step': 1}),
    rec(
      turn * 6 + 6,
      'turn/end',
      data: {
        'turn': turn + 1,
        'reason': {'kind': 'completed'},
      },
    ),
  ],
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final transport = FakeTransport();
  transport.onPage = (request) async {
    final end = ((request['beforeSeq']! as num).toInt() - 1) ~/ 6;
    final start = (end - 20).clamp(0, end);
    return {'records': records(start, end), 'hasMore': start > 0};
  };
  final session = Session('synthetic-history', transport);
  final owner = testSessionOwner('synthetic-history', session: session);
  unawaited(session.open());
  await Future<void>.delayed(Duration.zero);
  transport.open(1, snapshot(records(180, 300), hasMore: true));
  await Future<void>.delayed(Duration.zero);
  await session.prompt('Synthetic pending admission');
  final slots = SlotRegistry();
  for (final slot in DshSlots.all) {
    slots.declare(slot);
  }
  const i18n = DshI18n(DshLocale.en);
  registerChatFeature(slots, i18n: () => i18n);
  final theme = resolveTheme(
    officialPack,
    ThemeSettings(),
    Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark'
        ? Brightness.dark
        : Brightness.light,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: theme.brightness, extensions: [theme]),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                children: [
                  DshButton(
                    onPressed: () => session.handleRunning(true),
                    child: const Text('Run update'),
                  ),
                  DshButton(
                    onPressed: () => session.projections.apply('inbox', {
                      'next-turn': <Object?>[],
                      'next-step': [
                        {
                          'id': 'remote-item',
                          'source': {'kind': 'user', 'rpcId': 'remote-request'},
                          'content': [
                            {
                              'type': 'text',
                              'text': 'Synthetic remote steering',
                            },
                          ],
                        },
                      ],
                    }, 2),
                    child: const Text('Remote update'),
                  ),
                  DshButton(
                    onPressed: () => unawaited(session.loadOlder()),
                    child: const Text('Older page'),
                  ),
                  DshButton(
                    onPressed: () => unawaited(
                      session.prompt('Synthetic new local send', mode: 'steer'),
                    ),
                    child: const Text('Local send'),
                  ),
                ],
              ),
              Expanded(child: slots.renderList(viewSlot, owner).first),
            ],
          ),
        ),
      ),
    ),
  );
}
