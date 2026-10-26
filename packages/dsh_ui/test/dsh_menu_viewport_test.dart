import 'dart:ui' show SemanticsAction, Tristate;

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder row(String id) => find.byKey(ValueKey('dsh-menu-$id'));
  Future<List<String>> pump(
    WidgetTester t, {
    double? frameOverlayTop,
    List<DshMenuEntry>? entries,
    List<DshMenuEntry>? footer,
  }) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(800, 800);
    addTearDown(t.view.reset);
    final picked = <String>[];
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.topLeft,
          child: DshMenuCard(
            key: const ValueKey('card'),
            frameOverlayTop: frameOverlayTop,
            autofocus: true,
            entries:
                entries ??
                [
                  for (var i = 0; i < 30; i++)
                    DshMenuItem('$i', 'Workspace $i'),
                ],
            footer: footer ?? const [DshMenuItem('add', 'Add workspace')],
            onSelect: picked.add,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return picked;
  }

  testWidgets('source viewport cap scrolls items while footer stays pinned', (
    t,
  ) async {
    await pump(t);
    // Menu.module.css: 100vh - 12px - max(12px, frame-overlay-top).
    expect(t.getSize(find.byKey(const ValueKey('card'))).height, 376);
    final footer = t.getRect(row('add'));
    expect(footer.height, 34);
    expect(footer.bottom, 372); // Four pixels of surface padding.
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(t.getRect(row('add')), footer);
    expect(t.getRect(row('0')).bottom, lessThan(0));
    final semantics = t.ensureSemantics();
    try {
      expect(t.getSemantics(row('add')).rect.height, 34);
      await t.tap(row('add'));
      await t.pump();
      expect(t.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'keyboard reveals rows in both directions without moving visible ones',
    (t) async {
      final picked = await pump(t);
      final scroll = t.state<ScrollableState>(find.byType(Scrollable)).position;
      final footer = t.getRect(row('add'));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(scroll.pixels, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.end);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(0));
      expect(t.getRect(row('29')).bottom, lessThanOrEqualTo(footer.top - 6.5));
      expect(t.getRect(row('add')), footer);
      await t.sendKeyEvent(LogicalKeyboardKey.home);
      await t.pumpAndSettle();
      expect(scroll.pixels, 0);
      expect(t.getRect(row('0')).top, 4);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(picked, ['0']);
    },
  );

  testWidgets('footer shares keyboard order and disabled entries are skipped', (
    t,
  ) async {
    final picked = await pump(
      t,
      entries: const [
        DshMenuItem('first', 'First'),
        DshMenuItem('off', 'Off', disabled: true),
      ],
      footer: const [
        DshMenuItem('off-footer', 'Off footer', disabled: true),
        DshMenuItem('add', 'Add'),
      ],
    );
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, ['add']);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(picked, ['add', 'first']);
  });

  testWidgets('accessible focus follows keyboard from footer to last row', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    try {
      await pump(t);
      final first = t.getSemantics(row('0'));
      t.binding.pipelineOwner.semanticsOwner!.performAction(
        first.id,
        SemanticsAction.focus,
      );
      await t.pumpAndSettle();
      expect(
        t.getSemantics(row('0')).flagsCollection.isFocused,
        Tristate.isTrue,
      );

      await t.sendKeyEvent(LogicalKeyboardKey.end);
      await t.pumpAndSettle();
      expect(
        t.getSemantics(row('add')).flagsCollection.isFocused,
        Tristate.isTrue,
      );
      expect(
        t.getSemantics(row('0')).flagsCollection.isFocused,
        Tristate.isFalse,
      );

      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(
        t.getSemantics(row('add')).flagsCollection.isFocused,
        Tristate.isFalse,
      );
      expect(
        t.getSemantics(row('29')).flagsCollection.isFocused,
        Tristate.isTrue,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('standalone row accepts accessible focus only while enabled', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final enabled = ValueNotifier(true);
    try {
      await t.pumpWidget(
        dshTestApp(
          ValueListenableBuilder(
            valueListenable: enabled,
            builder: (_, value, _) => DshMenuItemButton(
              key: const ValueKey('standalone'),
              label: 'Standalone',
              disabled: !value,
              onPressed: () {},
            ),
          ),
        ),
      );
      final item = find.byKey(const ValueKey('standalone'));
      t.binding.pipelineOwner.semanticsOwner!.performAction(
        t.getSemantics(item).id,
        SemanticsAction.focus,
      );
      await t.pumpAndSettle();
      expect(t.getSemantics(item).flagsCollection.isFocused, Tristate.isTrue);
      enabled.value = false;
      await t.pumpAndSettle();
      expect(t.getSemantics(item).flagsCollection.isFocused, Tristate.none);
    } finally {
      await t.pumpWidget(const SizedBox());
      enabled.dispose();
      semantics.dispose();
    }
  });

  testWidgets(
    'frame reserve uses source max expression and short menus shrink',
    (t) async {
      await pump(t, frameOverlayTop: 40);
      expect(t.getSize(find.byKey(const ValueKey('card'))).height, 348);
      await pump(t, entries: const [DshMenuItem('one', 'One')]);
      expect(t.getSize(find.byKey(const ValueKey('card'))).height, 82.5);
      await pump(
        t,
        entries: const [],
        footer: const [DshMenuItem('add', 'Add')],
      );
      // The source footer's own separator exists even without main entries.
      expect(t.getSize(find.byKey(const ValueKey('card'))).height, 48.5);
    },
  );
  testWidgets(
    'linked portal keeps a long menu and its actual footer tap in view',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 400);
      addTearDown(t.view.reset);
      final link = LayerLink();
      final picked = <String>[];
      await t.pumpWidget(
        dshTestApp(
          Stack(
            children: [
              Positioned(
                left: 350,
                top: 350,
                child: CompositedTransformTarget(
                  link: link,
                  child: const SizedBox(width: 40, height: 28),
                ),
              ),
              Positioned.fill(
                child: DshMenuFollower(
                  link: link,
                  child: DshMenuCard(
                    key: const ValueKey('card'),
                    entries: [
                      for (var i = 0; i < 30; i++)
                        DshMenuItem('$i', 'Workspace $i'),
                    ],
                    footer: const [DshMenuItem('add', 'Add workspace')],
                    onSelect: picked.add,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      // The initial unplaced card stays absent until composition locates its anchor.
      expect(find.byKey(const ValueKey('card')), findsNothing);
      await t.pumpAndSettle();
      final card = t.getRect(find.byKey(const ValueKey('card')));
      expect(card.top, 12);
      expect(card.right, 388);
      expect(card.bottom, 388);
      await t.tap(row('add'));
      expect(picked, ['add']);
      await t.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
      await t.pumpAndSettle();
      await t.tap(row('add'));
      expect(picked, ['add', 'add']);
    },
  );

  testWidgets(
    'linked portal follows a moving transformed anchor without rebuilding its owner',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(500, 400);
      addTearDown(t.view.reset);
      final link = LayerLink();
      final offset = ValueNotifier(const Offset(150, 40));
      addTearDown(offset.dispose);
      await t.pumpWidget(
        dshTestApp(
          Stack(
            children: [
              ValueListenableBuilder(
                valueListenable: offset,
                builder: (_, position, _) => Positioned(
                  left: position.dx,
                  top: position.dy,
                  child: Transform.scale(
                    scale: 1.25,
                    alignment: Alignment.topLeft,
                    child: CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(width: 40, height: 24),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DshMenuFollower(
                  link: link,
                  alignEnd: true,
                  child: DshMenuCard(
                    key: const ValueKey('card'),
                    entries: const [DshMenuItem('one', 'One')],
                    onSelect: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      var card = t.getRect(find.byKey(const ValueKey('card')));
      expect(card.top, 74); // 40 + scaled 24 + source 4px gap.
      expect(card.right, 200); // 150 + scaled 40.
      offset.value = const Offset(200, 100);
      await t.pumpAndSettle();
      card = t.getRect(find.byKey(const ValueKey('card')));
      expect(card.top, 134);
      expect(card.right, 250);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'OS insets bound menu layout after inherited padding is consumed',
    (t) async {
      t.view.devicePixelRatio = 2;
      t.view.physicalSize = const Size(800, 800);
      t.view.viewPadding = const FakeViewPadding(
        left: 16,
        top: 56,
        right: 12,
        bottom: 40,
      );
      addTearDown(t.view.reset);
      final link = LayerLink();
      final picked = <String>[];
      await t.pumpWidget(
        dshTestApp(
          Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              removeLeft: true,
              removeRight: true,
              child: Stack(
                children: [
                  Positioned(
                    left: 350,
                    top: 350,
                    child: CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(width: 40, height: 28),
                    ),
                  ),
                  Positioned.fill(
                    child: DshMenuFollower(
                      link: link,
                      child: DshMenuCard(
                        key: const ValueKey('card'),
                        entries: [
                          for (var i = 0; i < 30; i++)
                            DshMenuItem('$i', 'Workspace $i'),
                        ],
                        footer: const [DshMenuItem('add', 'Add workspace')],
                        onSelect: picked.add,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final card = t.getRect(find.byKey(const ValueKey('card')));
      // Logical OS insets 8/28/6/20 plus source portal margins of twelve.
      expect(card.top, 40);
      expect(card.bottom, 368);
      expect(card.right, 382);
      expect(card.height, 328);
      t.view.viewPadding = const FakeViewPadding(
        left: 16,
        top: 80,
        right: 12,
        bottom: 40,
      );
      await t.pumpAndSettle();
      final resized = t.getRect(find.byKey(const ValueKey('card')));
      expect(resized.top, 52);
      expect(resized.bottom, 368);
      expect(resized.height, 316);
      await t.tap(row('add'));
      expect(picked, ['add']);
    },
  );
}
