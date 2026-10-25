import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_feature_secret_mask/dsh_feature_secret_mask.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => loadParityFonts(findParityFontsManifest()));
  testWidgets(
    'sent masking retains the original clipboard and confirmed session reference labels',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final controller = makeController(backend);
      addTearDown(controller.dispose);
      final key = 'sk-${List.filled(20, 'Q7').join()}';
      final raw = 'Read @src/a.dart and @Confirmed with $key';
      backend.transport.onList = () async => {
        'items': [listRow('s1', title: 'Synthetic session')],
      };
      final writes = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            writes.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await t.pumpWidget(WhaleeApp(controller: controller));
      await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(
        1,
        snapshot([
          userMessage(1, raw),
          rec(
            2,
            'user/message',
            data: {
              'id': 'recall',
              'role': 'user',
              'source': {
                'kind': 'session-reference',
                'references': [
                  {'label': 'Confirmed'},
                ],
              },
              'content': <Object?>[],
            },
            surfaceOp: 'append',
          ),
        ]),
      );
      await settle(t);
      expect(find.byType(SecretText), findsOneWidget);
      expect(find.text(key), findsNothing);
      final refs = t
          .widgetList<DshReferenceChip>(find.byType(DshReferenceChip))
          .toList();
      expect(
        refs.any((r) => r.appearance == 'session' && r.label == 'Confirmed'),
        isTrue,
      );
      final copy = find.byKey(const ValueKey('message-copy'));
      await t.tap(copy);
      await settle(t);
      expect(writes.last, raw);
      await t.tap(find.byKey(const ValueKey('secret-toggle')));
      await settle(t);
      expect(find.text(key), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'a sent file reference opens under its retained originating session',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final controller = makeController(backend);
      addTearDown(controller.dispose);
      backend.transport.onList = () async => {
        'items': [
          listRow('s1', title: 'First'),
          listRow('s2', title: 'Second'),
        ],
      };
      await t.pumpWidget(WhaleeApp(controller: controller));
      await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(1, snapshot([]));
      await settle(t);
      final first = controller.openSession!.owner;
      await openRow(t, 's2');
      await settle(t);
      final text = controller.slots.renderSingle(
        DshSlots.conversationUserText.typed<UserTextOwner, Widget>(),
        UserTextOwner(text: '@src/a.dart', session: first, interactive: true),
      )!;
      await t.pumpWidget(dshTestApp(text));
      await t.pumpAndSettle();
      await t.tap(find.byType(DshReferenceChip));
      await t.pump();
      expect(controller.openSessionId, 's2');
      expect(
        controller.sidebar
            .stateFor('s1')
            .tabs
            .any((t) => t.contentId.contains('/session/s1/')),
        isTrue,
      );
      expect(
        controller.sidebar
            .stateFor('s2')
            .tabs
            .where((t) => t.contentId.contains('/session/s1/')),
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
