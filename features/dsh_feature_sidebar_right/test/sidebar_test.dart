import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Services implements SidebarServices {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

void main() {
  late SlotRegistry slots;
  late _Services services;
  late SidebarRightFeature feature;
  late SessionOwner owner;
  var i18n = const DshI18n(DshLocale.en);

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    services = _Services();
    feature = registerSidebarRightFeature(
      slots,
      i18n: () => i18n,
      services: services,
    );
    owner = SessionOwner(
      session: testSessionOwner('s1').session,
      conversation: testSessionOwner('s1').conversation,
      actions: FakeActions(),
      cwdReader: () => '/w',
    );
    slots.register<SidebarTabOwner, Widget>(
      DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
      (o) => Text('files body'),
      key: 'files',
    );
    slots.register<SidebarTabOwner, Widget>(
      DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
      (o) => Text('preview ${o.contentId} line ${o.line} rev ${o.revision}'),
      key: 'text',
    );
  });

  Widget app(Widget child) {
    final themed = dshTestApp(child) as MaterialApp;
    return MaterialApp(
      navigatorKey: services.navigatorKey,
      theme: themed.theme,
      home: Scaffold(body: child),
    );
  }

  Widget header() => app(
    Row(
      children: slots.renderList(
        DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
        owner,
      ),
    ),
  );

  testWidgets('the header button opens the sheet on a phone-sized window', (
    t,
  ) async {
    await t.pumpWidget(header());
    await t.tap(find.byKey(const ValueKey('sidebar-open')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sidebar-sheet')), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('files body'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sidebar-collapse')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sidebar-sheet')), findsNothing);
  });

  testWidgets('opening a file adds a tab, selects it and shows the sheet', (
    t,
  ) async {
    await t.pumpWidget(header());
    feature.openFile(owner, '/w/src/a.dart', line: 12);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sidebar-sheet')), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    expect(
      find.text(
        'preview ${fileAddressFor('s1', '/w', '/w/src/a.dart')} line 12 rev 1',
      ),
      findsOneWidget,
    );
    // The same file again re-uses the tab and bumps the navigation revision.
    feature.openFile(owner, 'src/a.dart', line: 30);
    await t.pumpAndSettle();
    expect(feature.stateFor('s1').tabs, hasLength(2));
    expect(find.textContaining('line 30 rev 2'), findsOneWidget);
  });

  testWidgets('tabs switch and close; the file tree stays', (t) async {
    await t.pumpWidget(header());
    feature.openFile(owner, 'a.md');
    feature.openFile(owner, 'b.md');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chip-files')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('chip-files')));
    await t.pumpAndSettle();
    expect(feature.stateFor('s1').active.kind, 'files');
    await t.tap(find.byKey(const ValueKey('close-a.md')));
    await t.pumpAndSettle();
    expect(feature.stateFor('s1').tabs.map((x) => x.kind), ['files', 'text']);
    // The tree has no close control.
    expect(find.byKey(const ValueKey('close-Files')), findsNothing);
  });

  testWidgets('a wide window shows the sidebar as a column instead', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget shell() => app(
      Row(
        children: [
          const Expanded(child: SizedBox()),
          slots.renderSingle(
            DshSlots.rightbarSession.typed<SessionOwner, Widget>(),
            owner,
          )!,
        ],
      ),
    );
    await t.pumpWidget(shell());
    expect(find.byKey(const ValueKey('sidebar-inline')), findsNothing);
    final state = feature.stateFor('s1');
    state.setInlineOpen(true);
    await t.pump();
    expect(find.byKey(const ValueKey('sidebar-inline')), findsOneWidget);
    expect(
      t.getSize(find.byKey(const ValueKey('sidebar-inline'))).width,
      sidebarInlineWidth,
    );
    feature.openFile(owner, 'x.txt');
    await t.pump();
    expect(find.byKey(const ValueKey('sidebar-sheet')), findsNothing);
    expect(find.textContaining('preview'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sidebar-collapse')));
    await t.pump();
    expect(find.byKey(const ValueKey('sidebar-inline')), findsNothing);
  });

  testWidgets('an unknown tab kind says so', (t) async {
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    feature = registerSidebarRightFeature(
      slots,
      i18n: () => i18n,
      services: services,
    );
    await t.pumpWidget(header());
    feature.openFile(owner, 'x.txt');
    await t.pumpAndSettle();
    expect(
      find.text('Nothing here can view this kind of content yet.'),
      findsWidgets,
    );
  });

  test('state ignores addresses that are not file addresses', () {
    final state = SidebarState('s1');
    state.openResource('http://x/y');
    expect(state.tabs, hasLength(1));
    state.close('files');
    expect(state.tabs, hasLength(1));
  });
}
