import 'dart:async';

import 'package:dsh_feature_subagent/dsh_feature_subagent.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);

class FakeServices implements SubagentServices {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final StreamController<Object?> changed = StreamController.broadcast(
    sync: true,
  );
  final Map<String, SubagentStatus> status = {};
  final List<String> opened = [];
  late SessionOwner child;

  @override
  Stream<Object?> get changes => changed.stream;

  @override
  SubagentStatus statusOf(String childId) =>
      status[childId] ?? const SubagentStatus();

  @override
  SessionOwner childOwner(SessionOwner parent, SubagentEntry entry) {
    opened.add('${parent.sessionId}>${entry.id}:${entry.mode}');
    return child;
  }
}

const catalog = [
  {'id': 'c1', 'mode': 'continuable', 'label': 'Reviewer', 'createdAt': 1},
  {'id': 'c2', 'mode': 'one-shot', 'createdAt': 2},
  {'id': 'c3', 'mode': 'external', 'label': 'CI job', 'createdAt': 3},
  {'bad': true},
];

void main() {
  late FakeServices services;
  late SlotRegistry slots;
  late SessionOwner parent;
  late SubagentFeature feature;

  setUp(() {
    services = FakeServices();
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    // the transcript renders the child through `conversation.view`
    slots.register<SessionOwner, Widget>(
      DshSlots.conversationView.typed<SessionOwner, Widget>(),
      (o) => Text(
        'child view of ${o.sessionId}',
        key: const ValueKey('child-view'),
      ),
      id: 'fake-chat',
    );
    feature = registerSubagentFeature(
      slots,
      i18n: () => en,
      services: services,
    );
    parent = testSessionOwner('parent');
    services.child = testSessionOwner('c1');
  });

  Widget app(Widget child) => MaterialApp(
    navigatorKey: services.navigatorKey,
    theme: ThemeData(
      extensions: [
        resolveTheme(officialPack, ThemeSettings(), Brightness.light),
      ],
    ),
    home: Scaffold(body: Center(child: child)),
  );

  Widget trigger() => slots
      .renderList(
        DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
        parent,
      )
      .single;

  test('the catalog projection is parsed tolerantly', () {
    final entries = catalogOf(catalog);
    expect(entries.map((e) => e.id), ['c1', 'c2', 'c3']);
    expect(entries[0].label, 'Reviewer');
    expect(entries[1].label, isNull);
    expect(entries[2].openable, isFalse);
    expect(catalogOf(null), isEmpty);
    expect(catalogOf('nope'), isEmpty);
  });

  test('tokens and durations are compact', () {
    expect(formatTokens(950, en), '950');
    expect(formatTokens(12345, en), '12.3K');
    expect(formatTokens(2500000, en), '2.5M');
    expect(formatDuration(42000, en), '42s');
    expect(formatDuration(125000, en), '2m 5s');
    expect(formatDuration(3725000, en), '1h 2m 5s');
    expect(modeLabel(en, 'one-shot'), 'one-shot');
    expect(modeLabel(en, 'weird'), 'unknown mode');
  });

  testWidgets(
    'the trigger is hidden until the catalog has children, then counts them',
    (t) async {
      await t.pumpWidget(app(trigger()));
      expect(find.byKey(const ValueKey('subagent-trigger')), findsNothing);
      parent.session.projections.apply('subagentCatalog', catalog, 4);
      await t.pump();
      expect(find.byKey(const ValueKey('subagent-trigger')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets('a running child changes the trigger to the running count', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    parent.session.projections.apply('subagentCatalog', catalog, 4);
    services.status['c1'] = const SubagentStatus(running: true);
    await t.pumpWidget(app(trigger()));
    expect(find.bySemanticsLabel('1 subagent running'), findsOneWidget);
    services.status['c1'] = const SubagentStatus();
    services.changed.add(null);
    await t.pump();
    expect(find.bySemanticsLabel('3 subagents'), findsOneWidget);
    handle.dispose();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the sheet lists children with mode, usage and time; opening one pushes its transcript',
    (t) async {
      parent.session.projections.apply('subagentCatalog', catalog, 4);
      services.status['c1'] = const SubagentStatus(
        completed: true,
        tokens: 12345,
        durationMs: 65000,
      );
      await t.pumpWidget(app(trigger()));
      await t.tap(find.byKey(const ValueKey('subagent-trigger')));
      await t.pumpAndSettle();
      expect(find.text('Reviewer'), findsOneWidget);
      expect(find.text('continuable · 12.3K tok · 1m 5s'), findsOneWidget);
      expect(find.text('c2'), findsOneWidget); // no label: the id
      expect(find.text('CI job'), findsOneWidget);
      await t.tap(
        find.byKey(const ValueKey('subagent-row-c3')),
      ); // external: not openable
      await t.pump();
      expect(services.opened, isEmpty);
      await t.tap(find.byKey(const ValueKey('subagent-row-c1')));
      await t.pumpAndSettle();
      expect(services.opened, ['parent>c1:continuable']);
      expect(find.byKey(const ValueKey('subagent-transcript')), findsOneWidget);
      expect(find.byKey(const ValueKey('child-view')), findsOneWidget);
      expect(find.text('This subagent is read-only for now'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('subagent-close')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('subagent-transcript')), findsNothing);
    },
  );

  testWidgets(
    'a one-shot record says it is a record; an unknown mode says to read it first',
    (t) async {
      await t.pumpWidget(app(const SizedBox()));
      parent.session.projections.apply('subagentCatalog', catalog, 4);
      feature.openById(parent, 'c2');
      await t.pumpAndSettle();
      expect(find.text('One-shot subagent record'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('subagent-close')));
      await t.pumpAndSettle();
      parent.session.projections.apply('subagentCatalog', [
        {'id': 'c9', 'mode': 'unknown', 'createdAt': 1},
      ], 5);
      feature.openById(parent, 'c9');
      await t.pumpAndSettle();
      expect(
        find.text(
          'Read the child session to determine whether it can be continued.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('opening an unknown or external child does nothing', (t) async {
    await t.pumpWidget(app(const SizedBox()));
    parent.session.projections.apply('subagentCatalog', catalog, 4);
    feature.openById(parent, 'missing');
    feature.openById(parent, 'c3');
    await t.pumpAndSettle();
    expect(services.opened, isEmpty);
  });

  testWidgets('the catalog reads in Chinese', (t) async {
    expect(modeLabel(const DshI18n(DshLocale.zh), 'continuable'), '可继续');
  });
}
