// Widget behaviour of the docking surface (dsh `components.client.spec.tsx`,
// the cases that apply to this renderer): strips, selection, close, add, split,
// drag between strips and onto a body, dividers, menus and states.
import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const labels = DockLabels(
  emptyPane: 'empty pane',
  splitPane: 'split right',
  splitPaneDisabled: 'pane budget spent',
  splitPaneNarrow: 'too narrow to split',
  closeTab: 'close',
  addTab: 'new tab',
  dropZone: {
    DockZone.center: 'move here',
    DockZone.left: 'split left',
    DockZone.right: 'split right',
    DockZone.top: 'split top',
    DockZone.bottom: 'split bottom',
  },
);

/// Sizes the test window to [size] (the surface fills it).
void useWindow(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(
  DockController controller, {
  Size size = const Size(900, 600),
  bool Function(TabId)? canClose,
  bool Function(PaneId)? canAdd,
  Widget? chrome,
}) {
  final themed = dshTestApp(const SizedBox()) as MaterialApp;
  return MaterialApp(
    theme: themed.theme,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: DockLayout(
            controller: controller,
            labels: labels,
            canCloseTab: canClose,
            canAddTab: canAdd,
            chrome: chrome,
            renderTab: (context, tab) =>
                Center(child: Text('body ${tab.title}')),
          ),
        ),
      ),
    ),
  );
}

DockController controller() {
  final c = seededController();
  c.setExpanded(true);
  return c;
}

void main() {
  testWidgets(
    'draws the active tab body and one chip per tab, with the active one filled',
    (t) async {
      final c = controller();
      c.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      await t.pumpWidget(host(c));
      expect(find.text('body a.txt'), findsOneWidget);
      expect(find.text('body Start'), findsNothing);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('a.txt'), findsOneWidget);
    },
  );

  testWidgets('selects a tab with a tap and records one focus entry', (
    t,
  ) async {
    final c = controller();
    c.openContent(
      const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
    );
    await t.pumpWidget(host(c));
    final before = c.ops.length;
    final state = c.snapshot.state;
    final startId = state.tabs.values
        .firstWhere((tab) => tab.title == 'Start')
        .id;
    await t.tap(find.byKey(ValueKey('dock-chip-$startId')));
    await t.pump();
    expect(find.text('body Start'), findsOneWidget);
    expect(c.ops.length, before + 1);
    // A click on the already selected chip changes nothing.
    await t.tap(find.byKey(ValueKey('dock-chip-$startId')));
    await t.pump();
    expect(c.ops.length, before + 1);
  });

  testWidgets(
    'closes a tab from its close control, shown while the chip is active',
    (t) async {
      final c = controller();
      final id = c.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      await t.pumpWidget(host(c));
      await t.tap(find.byKey(ValueKey('dock-close-$id')));
      await t.pump();
      expect(c.snapshot.state.tabs[id], isNull);
      expect(find.text('a.txt'), findsNothing);
    },
  );

  testWidgets(
    'withholds the close control and draws a lone unclosable chip quiet',
    (t) async {
      final c = controller();
      await t.pumpWidget(host(c, canClose: (_) => false));
      expect(find.byKey(const ValueKey('dock-close-tab1')), findsNothing);
      final id = c.snapshot.state.tabs.keys.first;
      expect(find.byKey(ValueKey('dock-close-$id')), findsNothing);
      expect(find.text('Start'), findsOneWidget);
    },
  );

  testWidgets(
    'the add control seats the seeded tab at the end of the strip, and canAddTab omits it',
    (t) async {
      final c = controller();
      await t.pumpWidget(host(c));
      final pane = c.activeDockPaneId();
      await t.tap(find.byKey(ValueKey('dock-add-$pane')));
      await t.pump();
      expect(getPane(c.snapshot.state, pane).tabs, hasLength(2));
      await t.pumpWidget(host(c, canAdd: (_) => false));
      expect(find.byKey(ValueKey('dock-add-$pane')), findsNothing);
    },
  );

  testWidgets(
    'the split control splits the pane and seeds the new one; at four panes it is disabled',
    (t) async {
      useWindow(t, const Size(1600, 600));
      final c = controller();
      await t.pumpWidget(host(c, size: const Size(1600, 600)));
      final first = c.activeDockPaneId();
      await t.tap(find.byKey(ValueKey('dock-split-$first')));
      await t.pump();
      expect(dockPaneCount(c.snapshot.state), 2);
      expect(find.text('body Start'), findsNWidgets(2));
      c.splitPane();
      c.splitPane();
      await t.pump();
      expect(dockPaneCount(c.snapshot.state), 4);
      final before = c.ops.length;
      await t.tap(
        find.byKey(
          ValueKey('dock-split-${dockPaneIds(c.snapshot.state).first}'),
        ),
      );
      await t.pump();
      expect(
        c.ops.length,
        before,
        reason: 'a spent budget records nothing, not even a focus',
      );
    },
  );

  testWidgets('a narrow pane keeps its split control but disables it', (
    t,
  ) async {
    useWindow(t, const Size(220, 400));
    final c = controller();
    await t.pumpWidget(host(c, size: const Size(220, 400)));
    final pane = c.activeDockPaneId();
    await t.tap(find.byKey(ValueKey('dock-split-$pane')));
    await t.pump();
    expect(dockPaneCount(c.snapshot.state), 1);
  });

  testWidgets('hideSplitWhenBlocked drops a blocked split control', (t) async {
    useWindow(t, const Size(220, 400));
    final c = controller();
    final themed = dshTestApp(const SizedBox()) as MaterialApp;
    await t.pumpWidget(
      MaterialApp(
        theme: themed.theme,
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 400,
            child: DockLayout(
              controller: c,
              labels: labels,
              hideSplitWhenBlocked: true,
              renderTab: (context, tab) => Text(tab.title),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(ValueKey('dock-split-${c.activeDockPaneId()}')),
      findsNothing,
    );
  });

  testWidgets('draws the embedder chrome in the top-right pane only', (
    t,
  ) async {
    useWindow(t, const Size(1200, 400));
    final c = controller();
    c.splitPane();
    await t.pumpWidget(
      host(
        c,
        size: const Size(1200, 400),
        chrome: const Text('chrome-controls'),
      ),
    );
    expect(find.text('chrome-controls'), findsOneWidget);
    final right = topRightPaneId(c.snapshot.state);
    final rect = t.getRect(find.text('chrome-controls'));
    final strip = t.getRect(find.byKey(ValueKey('dock-strip-target-$right')));
    expect(strip.overlaps(rect), isTrue);
  });

  testWidgets('shows the empty-pane text for a pane without tabs', (t) async {
    final c = DockController();
    c.setExpanded(true);
    await t.pumpWidget(host(c));
    expect(find.text('empty pane'), findsOneWidget);
  });

  testWidgets(
    'a chip drag onto another strip moves the tab into the dropped slot',
    (t) async {
      final c = controller();
      final a = c.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      c.splitPane();
      await t.pumpWidget(host(c));
      final state = c.snapshot.state;
      final [left, right] = dockPaneIds(state);
      expect(getPane(state, left).tabs, contains(a));
      final from = t.getCenter(find.byKey(ValueKey('dock-chip-$a')));
      final to = t.getCenter(find.byKey(ValueKey('dock-strip-target-$right')));
      final gesture = await t.startGesture(from);
      await t.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(30, 0));
      await t.pump();
      await gesture.moveTo(Offset(to.dx + 100, to.dy));
      await t.pump();
      expect(find.byKey(const ValueKey('dock-caret')), findsOneWidget);
      await gesture.up();
      await t.pump();
      final after = c.snapshot.state;
      expect(getPane(after, right).tabs, contains(a));
      expect(getPane(after, left).tabs, isNot(contains(a)));
    },
  );

  testWidgets(
    'a chip drag onto a body edge splits the pane and lands the tab in the new half',
    (t) async {
      useWindow(t, const Size(800, 600));
      final c = controller();
      final a = c.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      await t.pumpWidget(host(c, size: const Size(800, 600)));
      final from = t.getCenter(find.byKey(ValueKey('dock-chip-$a')));
      final gesture = await t.startGesture(from);
      await t.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(30, 30));
      await t.pump();
      // The right edge band of the body.
      await gesture.moveTo(const Offset(790, 300));
      await t.pump();
      expect(find.text('split right'), findsWidgets);
      await gesture.up();
      await t.pump();
      final state = c.snapshot.state;
      expect(dockPaneCount(state), 2);
      final root = getSplit(state, state.rootId);
      expect(root.axis, SplitAxis.row);
      expect(getPane(state, root.children[1]).tabs, [a]);
    },
  );

  testWidgets(
    'a divider drag previews and commits one clamped resize on release',
    (t) async {
      useWindow(t, const Size(1000, 400));
      final c = controller();
      c.splitPane();
      await t.pumpWidget(host(c, size: const Size(1000, 400)));
      final split = getSplit(c.snapshot.state, c.snapshot.state.rootId);
      final before = c.ops.length;
      final divider = find.byKey(ValueKey('dock-divider-${split.splitId}-0'));
      final start = t.getCenter(divider);
      final gesture = await t.startGesture(start);
      await gesture.moveBy(const Offset(100, 0));
      await t.pump();
      await gesture.moveBy(const Offset(100, 0));
      await t.pump();
      expect(c.ops.length, before, reason: 'a drag frame records nothing');
      await gesture.up();
      await t.pump();
      expect(c.ops.length, before + 1);
      final sizes = getSplit(c.snapshot.state, split.id).sizes;
      expect(sizes[0], closeTo(0.7, 0.01));
      // A drag that would starve a pane is clamped.
      final again = await t.startGesture(t.getCenter(divider));
      await again.moveBy(const Offset(400, 0));
      await again.up();
      await t.pump();
      expect(
        getSplit(c.snapshot.state, split.id).sizes[1],
        greaterThanOrEqualTo(0.2 - 1e-9),
      );
    },
  );

  testWidgets(
    'a secondary press opens the chip menu whose close item closes the tab',
    (t) async {
      final c = controller();
      final a = c.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      await t.pumpWidget(host(c));
      await t.tap(
        find.byKey(ValueKey('dock-chip-$a')),
        buttons: kSecondaryButton,
      );
      await t.pump();
      expect(find.byKey(ValueKey('dock-menu-close-$a')), findsOneWidget);
      await t.tap(find.byKey(ValueKey('dock-menu-close-$a')));
      await t.pump();
      expect(c.snapshot.state.tabs[a], isNull);
    },
  );

  testWidgets(
    'touch long press opens the same tab menu and selection closes it',
    (t) async {
      final c = controller();
      final id = c.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      await t.pumpWidget(host(c));
      await t.longPress(find.byKey(ValueKey('dock-chip-$id')));
      await t.pump();
      expect(find.byKey(ValueKey('dock-menu-close-$id')), findsOneWidget);
      await t.tap(find.byKey(ValueKey('dock-menu-close-$id')));
      await t.pump();
      expect(c.snapshot.state.tabs[id], isNull);
    },
  );

  testWidgets(
    'keeps a keepMounted tab body alive while another tab is in front',
    (t) async {
      final c = controller();
      final a = c.openContent(
        const OpenContentInput(
          contentId: fileA,
          title: 'a.txt',
          kind: 'terminal',
        ),
      );
      c.focusTab(
        c.snapshot.state.tabs.values
            .firstWhere((tab) => tab.title == 'Start')
            .id,
      );
      final themed = dshTestApp(const SizedBox()) as MaterialApp;
      final inits = <String>[];
      await t.pumpWidget(
        MaterialApp(
          theme: themed.theme,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: DockLayout(
                controller: c,
                labels: labels,
                keepMounted: (tab) => tab.kind == 'terminal',
                renderTab: (context, tab) => _Counter(
                  onInit: () => inits.add(tab.title),
                  label: tab.title,
                ),
              ),
            ),
          ),
        ),
      );
      expect(inits, [
        'Start',
        'a.txt',
      ], reason: 'the seed tab and the kept terminal are mounted');
      expect(find.text('a.txt', skipOffstage: false), findsWidgets);
      c.focusTab(a);
      await t.pump();
      c.focusTab(
        c.snapshot.state.tabs.values
            .firstWhere((tab) => tab.title == 'Start')
            .id,
      );
      await t.pump();
      // The seed tab unmounted while hidden and mounts again; the kept body never rebuilt.
      expect(inits, ['Start', 'a.txt', 'Start']);
    },
  );
}

class _Counter extends StatefulWidget {
  const _Counter({required this.onInit, required this.label});

  final VoidCallback onInit;
  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Text('body ${widget.label}');
}
