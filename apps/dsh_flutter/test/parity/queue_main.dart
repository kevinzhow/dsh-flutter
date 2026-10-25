// Synthetic native replay; all queue operations are in-memory fixture actions.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
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
  final brightness = dark ? Brightness.dark : Brightness.light;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: _Fixture(DshI18n(zh ? DshLocale.zh : DshLocale.en)),
        ),
      ),
    ),
  );
}

class _Fixture extends StatefulWidget {
  const _Fixture(this.i18n);
  final DshI18n i18n;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  final preferences = ConversationPreferences();
  final session = Session('native-queue', FakeTransport());
  final actions = FakeActions();
  int tab = 0;
  bool running = true, fail = false;
  String result = '';
  List<InboxItem> rows = [];
  @override
  void initState() {
    super.initState();
    reset();
    session.handleRunning(true);
  }

  void reset() {
    rows = [
      for (final id in ['a', 'b'])
        InboxItem(
          id,
          [
            {'type': 'text', 'text': 'Synthetic queue $id'},
          ],
          const {'kind': 'user'},
        ),
    ];
  }

  Future<void> update(String id, Map<String, Object?> action) async {
    if (fail) throw StateError('Synthetic refusal');
    setState(() {
      result = '${action['kind']}:$id';
      if (action['kind'] == 'edit') {
        rows = [
          for (final row in rows)
            row.id == id
                ? InboxItem(
                    id,
                    (action['content'] as List).cast<Map<String, Object?>>(),
                    row.source,
                  )
                : row,
        ];
      } else {
        rows = rows.where((r) => r.id != id).toList();
      }
    });
  }

  @override
  void dispose() {
    unawaited(session.dispose());
    unawaited(preferences.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = testSessionOwner(
      'native-queue',
      session: session,
      actions: actions,
    );
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              for (final (i, label) in [
                'Queue',
                'Composer',
                'Settings',
              ].indexed)
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => tab = i),
                    child: Text(label),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 748),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (tab == 0) ...[
                        QueuePanel(
                          rows: rows,
                          running: running,
                          i18n: widget.i18n,
                          updateQueue: update,
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () => setState(reset),
                              child: const Text('Reset'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => running = !running),
                              child: Text(running ? 'Stop' : 'Run'),
                            ),
                            TextButton(
                              onPressed: () => setState(() => fail = !fail),
                              child: Text(fail ? 'Allow' : 'Refuse'),
                            ),
                          ],
                        ),
                        Text('Fixture action: $result'),
                      ] else if (tab == 1) ...[
                        DefaultComposer(
                          owner: owner,
                          i18n: widget.i18n,
                          preferences: preferences,
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => result = actions.sentModes.join(','),
                          ),
                          child: const Text('Show delivery'),
                        ),
                        Text('Delivery: $result'),
                      ] else
                        EnterBehaviorSettings(
                          preferences: preferences,
                          i18n: widget.i18n,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
