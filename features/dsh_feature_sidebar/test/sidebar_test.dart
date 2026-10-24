/// The sidebar column in its states: wide, rail, macOS and Windows chrome, the
/// panel entries, the browsing seat, and the window-chrome controls.
library;

import 'package:dsh_feature_sidebar/dsh_feature_sidebar.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Services implements SidebarServices {
  _Services(this.layout);

  @override
  final LayoutController layout;

  @override
  DshI18n get i18n => const DshI18n(DshLocale.en);

  var started = 0;

  Widget Function(SidebarSectionOwner owner)? region;

  @override
  Widget browsingRegion(BuildContext context, SidebarSectionOwner owner) =>
      region?.call(owner) ?? const SizedBox.shrink();

  @override
  void startSession() => started++;

  @override
  String get brandName => 'Whalee';

  @override
  ShortcutService? get shortcuts => null;
}

void main() {
  late SlotRegistry slots;
  late LayoutStore store;
  late LayoutController layout;
  late _Services services;

  setUp(() {
    slots = SlotRegistry();
    for (final s in DshShellSlots.all) {
      slots.declare(s);
    }
    store = LayoutStore(viewportWidth: 1280);
    layout = LayoutController(store, (id) => id == 'plugins');
    services = _Services(layout);
    registerSidebarFeature(slots, services: services);
  });

  Future<void> pump(
    WidgetTester t, {
    bool collapsed = false,
    ShellChrome chrome = const ShellChrome(),
  }) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final themed = dshTestApp(const SizedBox()) as MaterialApp;
    await t.pumpWidget(
      MaterialApp(
        theme: themed.theme,
        home: Scaffold(
          body: ShellScope(
            chrome: chrome,
            child: Row(
              children: [
                SizedBox(
                  width: collapsed && !chrome.hidesCollapsedRail ? 56 : 280,
                  child:
                      slots.renderSingle(
                        DshShellSlots.sidebar.typed<SidebarOwner, Widget>(),
                        SidebarOwner(
                          collapsed: collapsed,
                          width: collapsed ? 56 : 280,
                        ),
                      ) ??
                      const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('the wide column shows the brand, New Session and the browsing '
      'seat', (t) async {
    services.region = (o) => Text('sessions wide=${o.wide}');
    await pump(t);
    expect(find.text('Whalee'), findsOneWidget);
    expect(find.text('New Session'), findsOneWidget);
    expect(find.text('sessions wide=true'), findsOneWidget);
  });

  testWidgets('New Session and the brand row start a session', (t) async {
    await pump(t);
    await t.tap(find.byKey(const ValueKey('sidebar-new-session')));
    expect(services.started, 1);
    await t.tap(find.byKey(const ValueKey('sidebar-brand')));
    expect(services.started, 2);
  });

  testWidgets('the toggle collapses through ctx.layout', (t) async {
    await pump(t);
    await t.tap(find.byKey(const ValueKey('sidebar-toggle')));
    expect(store.layoutInfo.sidebar, 0);
  });

  testWidgets('the rail drops the wide content and keeps the actions', (
    t,
  ) async {
    services.region = (o) => Text('sessions wide=${o.wide}');
    await pump(t, collapsed: true);
    expect(find.text('Whalee'), findsNothing);
    expect(find.text('New Session'), findsNothing);
    expect(find.text('sessions wide=false'), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-new-session')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-toggle')), findsOneWidget);
  });

  testWidgets('a panel entry selects its main panel and reports it active', (
    t,
  ) async {
    slots.register<SidebarPanelIconOwner, Widget>(
      DshShellSlots.sidebarPanellist.typed<SidebarPanelIconOwner, Widget>(),
      (o) => Text('active=${o.active}'),
      id: 'plugins',
    );
    await pump(t);
    expect(find.text('active=false'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sidebar-panel-plugins')));
    await t.pumpAndSettle();
    expect(store.panelInfo.activePanelId, 'plugins');
    expect(find.text('active=true'), findsOneWidget);
    // dsh's PanelRow only selects; the Conversation returns by other means.
    layout.selectPanel(null);
    await t.pumpAndSettle();
    expect(find.text('active=false'), findsOneWidget);
  });

  testWidgets('macOS puts the toggle in a 52px strip and drops the rail', (
    t,
  ) async {
    await pump(t, chrome: const ShellChrome(platform: ShellPlatform.darwin));
    expect(find.byKey(const ValueKey('sidebar-toggle')), findsOneWidget);
    expect(
      t.getTopLeft(find.byKey(const ValueKey('sidebar-toggle'))).dy,
      lessThan(52),
    );
    expect(find.text('Whalee'), findsOneWidget);
  });

  testWidgets('Windows keeps the full content in the caption row layout', (
    t,
  ) async {
    await pump(
      t,
      collapsed: true,
      chrome: const ShellChrome(platform: ShellPlatform.windows),
    );
    // The column has no rail on Windows: nothing but chrome seats remain.
    expect(find.byKey(const ValueKey('sidebar-new-session')), findsNothing);
  });

  testWidgets('the leading seat offers the toggle and New Session', (t) async {
    final themed = dshTestApp(const SizedBox()) as MaterialApp;
    await t.pumpWidget(
      MaterialApp(
        theme: themed.theme,
        home: Scaffold(
          body: ShellScope(
            chrome: const ShellChrome(platform: ShellPlatform.darwin),
            child:
                slots.renderSingle(
                  DshShellSlots.shellLeading.typed<Object?, Widget>(),
                  null,
                ) ??
                const SizedBox(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('leading-new-session')));
    expect(services.started, 1);
    await t.tap(find.byKey(const ValueKey('leading-toggle')));
    expect(
      store.layoutInfo.narrowExpanded || store.layoutInfo.sidebar == 0,
      isTrue,
    );
  });
}
