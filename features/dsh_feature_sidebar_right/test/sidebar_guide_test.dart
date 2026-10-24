import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Services implements SidebarServices {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  LayoutController? get layout => null;

  @override
  ShortcutService? get shortcuts => null;
}

void main() {
  late SlotRegistry slots;
  late _Services services;
  late SidebarRightFeature feature;
  late SessionOwner owner;
  late List<String> closed;
  const i18n = DshI18n(DshLocale.en);

  setUp(() {
    closed = [];
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
    final base = testSessionOwner('s1');
    owner = SessionOwner(
      session: base.session,
      conversation: base.conversation,
      actions: FakeActions(),
      cwdReader: () => '/w',
    );
    slots.register<SidebarTabOwner, Widget>(
      DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
      (o) => Text('files body'),
      key: 'files',
    );
    slots.sidebarTabs.register(
      const SidebarTabType(kind: 'files', guideOrder: 10),
    );
    slots.register<SidebarGuideOwner, Widget>(
      DshSlots.sidebarRightTabGuideEntry.typed<SidebarGuideOwner, Widget>(),
      (o) => DshGuideCard(
        icon: const SizedBox(),
        title: 'Workspace files',
        description: 'Browse files',
        onTap: () => o.actions.openTab('files', replaceTabId: o.tabId),
      ),
      key: 'files',
    );
    slots.sidebarTabs.register(
      SidebarTabType(
        kind: 'shell',
        multiple: true,
        guideOrder: 20,
        keepMounted: true,
        onClose: (session, tab, content) =>
            closed.add('$session/$tab/$content'),
      ),
    );
    slots.register<SidebarTabOwner, Widget>(
      DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
      (o) => Text('shell ${o.params} visible=${o.visible}'),
      key: 'shell',
    );
    slots.register<SidebarTabOwner, Widget>(
      DshSlots.sidebarRightPaneTabTitle.typed<SidebarTabOwner, Widget>(),
      (o) => Text('title of ${o.contentId}'),
      key: 'shell',
    );
    slots.register<SidebarGuideOwner, Widget>(
      DshSlots.sidebarRightTabGuideEntry.typed<SidebarGuideOwner, Widget>(),
      (o) => DshGuideCard(
        icon: const SizedBox(),
        title: 'New shell',
        onTap: () => o.actions.openTab('shell', replaceTabId: o.tabId),
        titleTrailing: GestureDetector(
          key: const ValueKey('shell-menu'),
          behavior: HitTestBehavior.opaque,
          onTap: () => o.actions.openTab(
            'shell',
            replaceTabId: o.tabId,
            params: {'shellPath': '/bin/zsh'},
          ),
          child: const SizedBox(width: 28, height: 28),
        ),
      ),
      key: 'shell',
    );
  });

  Widget header() {
    final themed = dshTestApp(const SizedBox()) as MaterialApp;
    return MaterialApp(
      navigatorKey: services.navigatorKey,
      theme: themed.theme,
      home: Scaffold(
        body: Row(
          children: [
            ?slots.renderSingle(
              DshSlots.conversationSessionHeaderCorner
                  .typed<SessionOwner, Widget>(),
              owner,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(header());
    await t.tap(find.byKey(const ValueKey('sidebar-open')));
    await t.pumpAndSettle();
  }

  testWidgets('the phone sheet is full screen', (t) async {
    await openSheet(t);
    final sheet = t.getRect(find.byKey(const ValueKey('sidebar-sheet')));
    expect(sheet.height, greaterThan(740));
    expect(sheet.bottom, 800);
  });

  testWidgets(
    'the guide lists each type in order and stands alone without add or close controls',
    (t) async {
      await openSheet(t);
      final pane = feature.stateFor('s1').dock.activeDockPaneId();
      expect(find.byKey(const ValueKey('sidebar-guide')), findsOneWidget);
      expect(find.text('Start'), findsOneWidget, reason: 'the guide chip');
      final files = t.getTopLeft(find.text('Workspace files')).dy;
      final shell = t.getTopLeft(find.text('New shell')).dy;
      expect(files, lessThan(shell));
      // A guide is open: no add control, and no close control for a lone guide.
      expect(find.byKey(ValueKey('dock-add-$pane')), findsNothing);
      expect(
        find.byKey(
          ValueKey('dock-close-${feature.stateFor('s1').tabs.single.id}'),
        ),
        findsNothing,
      );
      // The guide stays one tab however often it is opened.
      feature.stateFor('s1').openTab('guide');
      expect(
        feature.stateFor('s1').tabs.where((x) => x.kind == 'guide'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'a card opens its page in the guide place; the add control returns once the guide is gone',
    (t) async {
      await openSheet(t);
      final state = feature.stateFor('s1');
      final pane = state.dock.activeDockPaneId();
      await t.tap(find.text('New shell'));
      await t.pumpAndSettle();
      expect(state.tabs.map((x) => x.kind), ['shell']);
      expect(find.byKey(const ValueKey('sidebar-guide')), findsNothing);
      expect(find.textContaining('shell {} visible=true'), findsOneWidget);
      // The type's own title replaces the chip text.
      expect(find.textContaining('title of sidebar://shell/'), findsOneWidget);
      expect(find.byKey(ValueKey('dock-add-$pane')), findsOneWidget);
      // The add control opens the guide again.
      await t.tap(find.byKey(ValueKey('dock-add-$pane')));
      await t.pumpAndSettle();
      expect(state.tabs.map((x) => x.kind), ['shell', 'guide']);
      expect(find.byKey(ValueKey('dock-add-$pane')), findsNothing);
    },
  );

  testWidgets('a card with a choice passes its parameters', (t) async {
    await openSheet(t);
    await t.tap(find.byKey(const ValueKey('shell-menu')));
    await t.pumpAndSettle();
    expect(feature.stateFor('s1').tabs.last.params, {'shellPath': '/bin/zsh'});
    expect(find.textContaining('{shellPath: /bin/zsh}'), findsOneWidget);
  });

  testWidgets('the files card opens the tree in the guide place', (t) async {
    await openSheet(t);
    await t.tap(find.text('Workspace files'));
    await t.pumpAndSettle();
    final state = feature.stateFor('s1');
    expect(state.tabs.map((x) => x.kind), ['files']);
    expect(state.active.kind, 'files');
    expect(find.text('files body'), findsOneWidget);
  });

  test(
    'a multiple type opens independent instances; closing runs its handler',
    () {
      final state = feature.stateFor('s1');
      state.setExpanded(true);
      state.openTab('shell');
      state.openTab('shell', params: {'shellPath': '/bin/sh'});
      final shells = state.tabs.where((t) => t.kind == 'shell').toList();
      expect(shells, hasLength(2));
      expect(shells[0].contentId, isNot(shells[1].contentId));
      state.close(shells[0].id);
      expect(closed, ['s1/${shells[0].id}/${shells[0].contentId}']);
      expect(state.tabs.where((t) => t.kind == 'shell').map((t) => t.id), [
        shells[1].id,
      ]);
    },
  );

  test(
    'replacing a page ends the one it replaces without the close handler',
    () {
      final state = feature.stateFor('s1');
      state.setExpanded(true);
      state.openTab('shell');
      final first = state.tabs.firstWhere((t) => t.kind == 'shell');
      state.openTab('shell', replaceTabId: first.id);
      expect(
        closed,
        isEmpty,
        reason: "replacement of a live page is the opener's call",
      );
      expect(
        state.tabs.where((t) => t.kind == 'shell').map((t) => t.id),
        isNot(contains(first.id)),
      );
    },
  );

  test('a page type opens once; its second open focuses it', () {
    slots.sidebarTabs.register(const SidebarTabType(kind: 'once'));
    final state = feature.stateFor('s1');
    state.setExpanded(true);
    state.openTab('once');
    state.openTab('files');
    state.openTab('once');
    expect(state.tabs.where((t) => t.kind == 'once'), hasLength(1));
    expect(state.active.kind, 'once');
  });

  test('an unregistered kind is a wiring mistake', () {
    expect(() => feature.stateFor('s1').openTab('nope'), throwsStateError);
  });

  test('tab types are declared once and can be withdrawn', () {
    expect(
      () => slots.sidebarTabs.register(const SidebarTabType(kind: 'shell')),
      throwsStateError,
    );
    final off = slots.sidebarTabs.register(
      const SidebarTabType(kind: 'x', guideOrder: 5),
    );
    expect(slots.sidebarTabs.guideTypes.first.kind, 'x');
    off();
    expect(slots.sidebarTabs.typeOf('x'), isNull);
    expect(slots.sidebarTabs.guideTypes.map((t) => t.kind), ['files', 'shell']);
  });

  testWidgets('forgetting the host drops every sidebar', (t) async {
    feature.stateFor('s1').setExpanded(true);
    feature.reset();
    expect(feature.stateFor('s1').tabs, isEmpty);
  });
}
