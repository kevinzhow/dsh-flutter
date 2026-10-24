import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The composer's `/` and `@` pipeline over the whole app: the real features
/// registered by the composition root, a scripted host behind them.
void main() {
  late FakeBackend backend;
  late AppController controller;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
  }

  const catalog = [
    {
      'name': 'compact',
      'description': 'Compact older conversation history',
      'definitionId': '@deepseek-ai/dsh-command-compact',
    },
    {
      'name': 'goal',
      'description': 'Set a goal',
      'definitionId': '@deepseek-ai/dsh-command-goal',
      'input': {'hint': '[<objective>]', 'attachments': true},
    },
    {
      'name': 'plan',
      'description': 'Enter or leave plan mode',
      'definitionId': '@deepseek-ai/dsh-plan-mode',
      'input': {'hint': '[off|message]', 'attachments': true},
    },
  ];

  Future<void> start(
    WidgetTester t, {
    DshLocale locale = DshLocale.en,
    Size size = const Size(400, 800),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    backend = FakeBackend();
    backend.host.handlers['commands/list'] = (_) => catalog;
    backend.host.handlers['commands/execute'] = (_) => {
      'commandId': 'c1',
      'result': {'kind': 'success'},
    };
    backend.host.handlers['fileReferences/list'] = (args) {
      final q = args['query']! as String;
      return [
        for (final f in const [
          {'path': 'src', 'kind': 'directory'},
          {'path': 'README.md', 'kind': 'file'},
          {'path': 'my docs/read me.md', 'kind': 'file'},
        ])
          if (q.isEmpty || (f['path']!).toLowerCase().contains(q.toLowerCase()))
            f,
      ];
    };
    backend.host.handlers['sessionReferenceResolver/candidates'] = (args) => [
      {
        'sessionId': 's9',
        'label': 'Planning',
        'sameWorkspace': true,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'mention': '@[Planning](dsh-session:s9)',
      },
    ];
    controller = makeController(backend, locale: locale);
    addTearDown(() async {
      controller.dispose();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    });
    await t.pumpWidget(WhaleeApp(controller: controller));
    backend.transport.onList = () async => {
      'items': [listRow('s1', title: 'Task one', running: false)],
    };
    await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('session-row-s1')));
    await settle(t);
    backend.transport.open(
      1,
      snapshot([userMessage(1, 'Earlier')], projections: {'title': 'Task one'}),
    );
    await settle(t);
  }

  Future<void> type(WidgetTester t, String text) async {
    final field = find.byType(EditableText).last;
    final controllerOf = t.widget<EditableText>(field).controller;
    // One character at a time, like a keyboard: the caret rides the end.
    for (final ch in text.split('')) {
      final v = controllerOf.value;
      final next = v.text + ch;
      await t.enterText(field, next);
      await settle(t);
    }
  }

  testWidgets(
    'typing / lists the commands above the composer; Escape closes it',
    (t) async {
      await start(t);
      await t.tap(find.byType(EditableText).last);
      await type(t, '/');
      expect(find.byKey(const ValueKey('trigger-menu')), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Commands'), findsOneWidget);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('Compact'), findsOneWidget);
      // The menu sits above the composer, inside the window.
      final menu = t.getRect(
        find.byKey(const ValueKey('trigger-menu-surface')),
      );
      final field = t.getRect(find.byType(EditableText).last);
      expect(menu.bottom, lessThanOrEqualTo(field.top));
      expect(menu.left, greaterThanOrEqualTo(0));
      expect(menu.right, lessThanOrEqualTo(400));
      // It stops below the session header: the title row stays whole.
      expect(
        menu.top,
        greaterThanOrEqualTo(
          t.getRect(find.byKey(const ValueKey('session-title'))).bottom,
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(find.byKey(const ValueKey('trigger-menu')), findsNothing);
    },
  );

  testWidgets(
    'a command with input becomes a chip; the line goes to the host as /plan text',
    (t) async {
      await start(t);
      await t.tap(find.byType(EditableText).last);
      await type(t, '/');
      await t.tap(find.byKey(const ValueKey('trigger-row-plan')));
      await settle(t);
      expect(
        find.byKey(const ValueKey('composer-command-chip')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('trigger-menu')), findsNothing);
      await type(t, 'ship it');
      await t.tap(find.byKey(const ValueKey('composer-send')));
      await settle(t);
      expect(
        backend.host.callsTo('commands/execute').single.args['line'],
        '/plan ship it',
      );
      // It never reached the model as a message.
      expect(backend.transport.prompts, isEmpty);
      expect(
        t.widget<EditableText>(find.byType(EditableText).last).controller.text,
        isEmpty,
      );
    },
  );

  testWidgets('a bare host command runs from the menu and consumes its token', (
    t,
  ) async {
    await start(t);
    await t.tap(find.byType(EditableText).last);
    await type(t, '/co');
    await t.tap(find.byKey(const ValueKey('trigger-row-compact')));
    await settle(t);
    expect(
      backend.host.callsTo('commands/execute').single.args['line'],
      '/compact',
    );
    expect(
      t.widget<EditableText>(find.byType(EditableText).last).controller.text,
      isEmpty,
    );
  });

  testWidgets(
    'typing @ lists files and sessions; a pick becomes a chip and sends the exact @path text',
    (t) async {
      await start(t);
      await t.tap(find.byType(EditableText).last);
      await type(t, 'read @');
      expect(find.text('Files & folders'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('Planning'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('trigger-row-README.md')));
      await settle(t);
      expect(
        find.byKey(const ValueKey('composer-chip-reference-1')),
        findsOneWidget,
      );
      await type(t, 'now');
      await t.tap(find.byKey(const ValueKey('composer-send')));
      await settle(t);
      final content = backend.transport.prompts.single['content']! as List;
      expect((content.single as Map)['text'], 'read @README.md now');
    },
  );

  testWidgets(
    'a path with spaces is sent quoted, and a session reference as its canonical mention',
    (t) async {
      await start(t);
      await t.tap(find.byType(EditableText).last);
      await type(t, '@my');
      await t.tap(find.byKey(const ValueKey('trigger-row-read me.md')));
      await settle(t);
      await type(t, '@Pl');
      await t.tap(find.byKey(const ValueKey('trigger-row-Planning')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('composer-send')));
      await settle(t);
      final text =
          ((backend.transport.prompts.single['content']! as List).single
              as Map)['text'];
      expect(text, '@"my docs/read me.md" @[Planning](dsh-session:s9)');
    },
  );

  testWidgets(
    'a directory drills: its chevron keeps the text editable and shows the way back',
    (t) async {
      await start(t);
      await t.tap(find.byType(EditableText).last);
      await type(t, '@');
      await t.tap(find.byKey(const ValueKey('trigger-drill-src/')));
      await settle(t);
      expect(
        t.widget<EditableText>(find.byType(EditableText).last).controller.text,
        '@src/',
      );
      expect(
        find.byKey(const ValueKey('trigger-crumbs-reference')),
        findsOneWidget,
      );
      expect(find.text('Workspace'), findsOneWidget);
    },
  );

  testWidgets('the zh locale shows the zh menu', (t) async {
    await start(t, locale: DshLocale.zh);
    await t.tap(find.byType(EditableText).last);
    await type(t, '/');
    expect(find.text('添加'), findsOneWidget);
    expect(find.text('目标'), findsOneWidget);
  });

  testWidgets('a wide window keeps the 34px rows of dsh', (t) async {
    await start(t, size: const Size(1200, 800));
    await t.tap(find.byType(EditableText).last);
    await type(t, '/');
    final row = t.getRect(find.byKey(const ValueKey('trigger-row-goal')));
    expect(row.height, closeTo(34, 1));
  });

  testWidgets('a phone keeps a 44px touch row', (t) async {
    await start(t);
    await t.tap(find.byType(EditableText).last);
    await type(t, '/');
    final row = t.getRect(find.byKey(const ValueKey('trigger-row-goal')));
    expect(row.height, greaterThanOrEqualTo(44));
  });
}
