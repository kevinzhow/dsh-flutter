import 'package:dsh_dockkit/dsh_dockkit.dart' show getPane;
import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Services implements SidebarServices {
  _Services({this.layout});

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  final LayoutController? layout;

  @override
  ShortcutService? get shortcuts => null;
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
    slots.sidebarTabs.register(
      const SidebarTabType(kind: 'files', guideOrder: 10),
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
    slots.register<SidebarGuideOwner, Widget>(
      DshSlots.sidebarRightTabGuideEntry.typed<SidebarGuideOwner, Widget>(),
      (o) => GestureDetector(
        key: const ValueKey('guide-files'),
        onTap: () => o.actions.openTab('files', replaceTabId: o.tabId),
        child: const Text('Workspace files'),
      ),
      key: 'files',
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
      children: [
        ?slots.renderSingle(
          DshSlots.conversationSessionHeaderCorner
              .typed<SessionOwner, Widget>(),
          owner,
        ),
      ],
    ),
  );

  Future<void> phone(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  testWidgets(
    'the header button opens the full-screen sheet on a phone-sized window, seeded with the guide',
    (t) async {
      await phone(t);
      await t.pumpWidget(header());
      await t.tap(find.byKey(const ValueKey('sidebar-open')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-sheet')), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Workspace files'), findsOneWidget);
      // No presentation switch in a sheet that is fullscreen already.
      expect(find.byKey(const ValueKey('sidebar-fullscreen')), findsNothing);
      await t.tap(find.byKey(const ValueKey('sidebar-collapse')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-sheet')), findsNothing);
    },
  );

  testWidgets('opening a file adds a tab, selects it and shows the sheet', (
    t,
  ) async {
    await phone(t);
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
    expect(
      feature.stateFor('s1').tabs.where((x) => x.kind == 'text'),
      hasLength(1),
    );
    expect(find.textContaining('line 30 rev 2'), findsOneWidget);
  });

  testWidgets('tabs switch and close; the guide alone has no close control', (
    t,
  ) async {
    await phone(t);
    await t.pumpWidget(header());
    feature.openFile(owner, 'a.md');
    feature.openFile(owner, 'b.md');
    await t.pumpAndSettle();
    final state = feature.stateFor('s1');
    final tabs = state.tabs;
    expect(tabs.map((x) => x.kind), ['guide', 'text', 'text']);
    // The guide is not alone: closable, selectable.
    await t.tap(find.byKey(ValueKey('dock-chip-${tabs[0].id}')));
    await t.pumpAndSettle();
    expect(state.active.kind, 'guide');
    await t.tap(find.byKey(ValueKey('dock-chip-${tabs[1].id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('dock-close-${tabs[1].id}')));
    await t.pumpAndSettle();
    expect(state.tabs.map((x) => x.kind), ['guide', 'text']);
    state.close(tabs[2].id);
    // The guide standing alone is not closable; nothing happens to it.
    state.close(tabs[0].id);
    expect(state.tabs.map((x) => x.kind), ['guide']);
    expect(state.canClose(tabs[0].id), isFalse);
    state.close(tabs[0].id);
    expect(state.tabs, hasLength(1));
  });

  testWidgets(
    'a lone page that is not the guide closes together with the column',
    (t) async {
      final state = feature.stateFor('s1');
      state.setExpanded(true);
      state.openTab('files', replaceTabId: state.tabs.single.id);
      expect(state.tabs.map((x) => x.kind), ['files']);
      expect(state.canClose(state.tabs.single.id), isTrue);
      state.close(state.tabs.single.id);
      expect(state.tabs, isEmpty);
      expect(state.expanded, isFalse);
      // Expanding again seeds the default page.
      state.setExpanded(true);
      expect(state.tabs.map((x) => x.kind), ['guide']);
    },
  );

  testWidgets(
    'a wide window without a frame shows the sidebar as a column instead',
    (t) async {
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
      state.setExpanded(true);
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
    },
  );

  group('inside the desktop frame', () {
    late LayoutStore store;
    late LayoutController layout;

    Widget seat({
      required double width,
      required double viewport,
      bool canShow = true,
    }) {
      return app(
        DshRightbarHost(
          child: DshRightbarGeometry(
            width: width,
            viewportWidth: viewport,
            canShow: canShow,
            child: slots.renderSingle(
              DshSlots.rightbarSession.typed<SessionOwner, Widget>(),
              owner,
            )!,
          ),
        ),
      );
    }

    setUp(() {
      store = LayoutStore(viewportWidth: 1280);
      layout = LayoutController(store, (_) => true);
      services = _Services(layout: layout);
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      feature = registerSidebarRightFeature(
        slots,
        i18n: () => i18n,
        services: services,
      );
      slots.sidebarTabs.register(
        const SidebarTabType(kind: 'files', guideOrder: 10),
      );
    });

    testWidgets(
      'draws nothing and reports hidden while collapsed, then the panel at the solved width with a track',
      (t) async {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(seat(width: 420, viewport: 1280));
        expect(find.byKey(const ValueKey('sidebar-inline')), findsNothing);
        expect(store.layoutInfo.rightbarShown, isFalse);
        feature.stateFor('s1').setExpanded(true);
        await t.pump();
        await t.pump();
        expect(
          t.getSize(find.byKey(const ValueKey('sidebar-inline'))).width,
          420,
        );
        expect(
          (
            store.layoutInfo.rightbarShown,
            store.layoutInfo.rightbarTrack,
            store.layoutInfo.rightbarFullscreen,
          ),
          (true, true, false),
        );
        // The presentation switch takes the panel over the frame, keeping the track.
        await t.tap(find.byKey(const ValueKey('sidebar-fullscreen')));
        await t.pump();
        await t.pump();
        expect(
          find.byKey(const ValueKey('sidebar-fullscreen-panel')),
          findsOneWidget,
        );
        expect(
          (
            store.layoutInfo.rightbarShown,
            store.layoutInfo.rightbarTrack,
            store.layoutInfo.rightbarFullscreen,
          ),
          (true, true, true),
        );
        await t.tap(find.byKey(const ValueKey('sidebar-collapse')));
        await t.pump();
        await t.pump();
        expect(store.layoutInfo.rightbarShown, isFalse);
      },
    );

    testWidgets(
      'below 768px the panel is fullscreen on its own and takes no track',
      (t) async {
        t.view.physicalSize = const Size(700, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        feature.stateFor('s1').setExpanded(true);
        await t.pumpWidget(seat(width: 0, viewport: 700, canShow: false));
        await t.pump();
        await t.pump();
        expect(
          find.byKey(const ValueKey('sidebar-fullscreen-panel')),
          findsOneWidget,
        );
        expect(
          (
            store.layoutInfo.rightbarShown,
            store.layoutInfo.rightbarTrack,
            store.layoutInfo.rightbarFullscreen,
          ),
          (true, false, true),
        );
      },
    );

    testWidgets(
      'a panel that no longer fits closes, and does not reopen on widening',
      (t) async {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final state = feature.stateFor('s1');
        state.setExpanded(true);
        await t.pumpWidget(seat(width: 0, viewport: 900, canShow: false));
        await t.pump();
        await t.pump();
        expect(state.expanded, isFalse);
        await t.pumpWidget(seat(width: 420, viewport: 1280));
        await t.pump();
        expect(state.expanded, isFalse);
      },
    );

    testWidgets(
      'the header button toggles the column inside the frame, and is hidden while the panel is shown',
      (t) async {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          app(
            DshRightbarHost(
              child: Row(
                children: [
                  ?slots.renderSingle(
                    DshSlots.conversationSessionHeaderCorner
                        .typed<SessionOwner, Widget>(),
                    owner,
                  ),
                ],
              ),
            ),
          ),
        );
        await t.tap(find.byKey(const ValueKey('sidebar-open')));
        await t.pump();
        expect(feature.stateFor('s1').expanded, isTrue);
        expect(find.byKey(const ValueKey('sidebar-open')), findsNothing);
      },
    );
  });

  testWidgets('an unknown tab kind says so', (t) async {
    await phone(t);
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
    state.setExpanded(true);
    state.openResource('http://x/y');
    expect(state.tabs.map((t) => t.kind), ['guide']);
  });

  test('the panel is limited to two panes, and a split seeds the guide', () {
    final state = feature.stateFor('s1');
    state.setExpanded(true);
    expect(state.dock.splitPane(), isTrue);
    expect(state.dock.snapshot.canSplit, isFalse);
    expect(state.dock.splitPane(), isFalse);
    final layout = state.layout;
    expect(layout.tabs.values.where((t) => t.kind == 'guide'), hasLength(2));
    expect(
      getPane(layout, state.dock.snapshot.state.activePaneId).tabs,
      isNotEmpty,
    );
  });
}
