/// The frame's states: the column solve at desktop widths, the auto-collapse
/// of the left column below 1024 and its narrow override, the handles, the
/// main panel selection, and the per-platform chrome seats.
library;

import 'package:dsh_feature_layout/dsh_feature_layout.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settles frames and the frame's own 600ms easing timer.
Future<void> settle(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.pump(const Duration(milliseconds: 700));
}

void main() {
  late SlotRegistry slots;
  late LayoutFeature layout;
  late void Function() dropPlugins;
  late void Function() dropConversation;

  setUp(() {
    slots = SlotRegistry();
    for (final s in DshShellSlots.all) {
      slots.declare(s);
    }
    slots.register<SidebarOwner, Widget>(
      DshShellSlots.sidebar.typed<SidebarOwner, Widget>(),
      (o) => Text(
        'sidebar ${o.collapsed ? 'rail' : 'open'} ${o.width.round()}',
        key: const ValueKey('sidebar-body'),
      ),
    );
    dropConversation = slots.register<Object?, Widget>(
      DshShellSlots.main.typed<Object?, Widget>(),
      (_) => const Text('conversation', key: ValueKey('main-conversation')),
      key: conversationPanelKey,
    );
    dropPlugins = slots.register<Object?, Widget>(
      DshShellSlots.main.typed<Object?, Widget>(),
      (_) => const Text('plugins', key: ValueKey('main-plugins')),
      key: 'plugins',
    );
  });

  Future<void> pump(
    WidgetTester t, {
    required Size size,
    ShellChrome chrome = const ShellChrome(),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    layout = registerLayoutFeature(
      slots,
      shortcuts: null,
      i18n: () => const DshI18n(DshLocale.en),
      viewportWidth: size.width,
    );
    addTearDown(layout.dispose);
    final themed = dshTestApp(const SizedBox()) as MaterialApp;
    await t.pumpWidget(
      MaterialApp(
        theme: themed.theme,
        home: Scaffold(
          body: AppFrame(
            layout: layout,
            slots: slots,
            chrome: chrome,
            disableAnimations: true,
          ),
        ),
      ),
    );
    await settle(t);
  }

  double sidebarWidth(WidgetTester t) =>
      t.getSize(find.byKey(const ValueKey('sidebar-body'))).width;

  testWidgets('a wide window shows the open sidebar at its default width', (
    t,
  ) async {
    await pump(t, size: const Size(1280, 800));
    expect(find.text('sidebar open 280'), findsOneWidget);
    expect(find.byKey(const ValueKey('main-conversation')), findsOneWidget);
    expect(find.byKey(const ValueKey('frame-handle-sidebar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('frame-handle-rightbar')),
      findsNothing,
      reason: 'no occupant has opened the right column',
    );
  });

  testWidgets('a window under 1024 collapses the sidebar to the rail', (
    t,
  ) async {
    await pump(t, size: const Size(900, 700));
    expect(find.text('sidebar rail 56'), findsOneWidget);
    expect(find.byKey(const ValueKey('frame-handle-sidebar')), findsNothing);
  });

  testWidgets('expanding on a narrow window overrides the collapse', (t) async {
    await pump(t, size: const Size(900, 700));
    layout.controller.toggleSidebar();
    await settle(t);
    expect(find.textContaining('sidebar open'), findsOneWidget);
    layout.controller.toggleSidebar();
    await settle(t);
    expect(find.text('sidebar rail 56'), findsOneWidget);
  });

  testWidgets('the toggle collapses and restores the preference', (t) async {
    await pump(t, size: const Size(1280, 800));
    layout.controller.toggleSidebar();
    await settle(t);
    expect(find.text('sidebar rail 56'), findsOneWidget);
    layout.controller.toggleSidebar();
    await settle(t);
    expect(find.text('sidebar open 280'), findsOneWidget);
  });

  testWidgets('dragging the sidebar handle resizes within 264 and 420', (
    t,
  ) async {
    await pump(t, size: const Size(1600, 1000));
    final handle = find.byKey(const ValueKey('frame-handle-sidebar'));
    await t.drag(handle, const Offset(60, 0));
    await settle(t);
    expect(sidebarWidth(t), 340);
    await t.drag(handle, const Offset(400, 0));
    await settle(t);
    expect(sidebarWidth(t), 420);
    await t.drag(handle, const Offset(-600, 0));
    await settle(t);
    expect(sidebarWidth(t), 264);
    expect(layout.store.layoutInfo.sidebar, 264);
  });

  testWidgets('selecting a global panel swaps the centre, and back', (t) async {
    await pump(t, size: const Size(1280, 800));
    layout.controller.selectPanel('plugins');
    await settle(t);
    expect(find.byKey(const ValueKey('main-plugins')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-conversation')), findsNothing);
    layout.controller.selectPanel(null);
    await settle(t);
    expect(find.byKey(const ValueKey('main-conversation')), findsOneWidget);
  });

  testWidgets('a panel that vanishes returns to the conversation', (t) async {
    await pump(t, size: const Size(1280, 800));
    layout.controller.selectPanel('plugins');
    await settle(t);
    dropPlugins();
    await settle(t);
    expect(find.byKey(const ValueKey('main-conversation')), findsOneWidget);
  });

  testWidgets('the right column occupant reports its track and the centre '
      'makes room', (t) async {
    slots.register<RightbarOwner, Widget>(
      DshShellSlots.rightbar.typed<RightbarOwner, Widget>(),
      (o) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          key: const ValueKey('rightbar-body'),
          width: o.width,
          child: Text('right ${o.width.round()} ${o.canShow}'),
        ),
      ),
    );
    await pump(t, size: const Size(1600, 1000));
    // 45% of 1600, clamped to 70%: the normal width the owner is given.
    expect(find.text('right 720 true'), findsOneWidget);
    layout.store.openRightbar(true, false);
    await settle(t);
    expect(find.byKey(const ValueKey('frame-handle-rightbar')), findsOneWidget);
    layout.store.closeRightbar();
    await settle(t);
    expect(find.byKey(const ValueKey('frame-handle-rightbar')), findsNothing);
  });

  testWidgets('macOS hides the collapsed rail and seats the leading controls', (
    t,
  ) async {
    slots.register<Object?, Widget>(
      DshShellSlots.shellLeading.typed<Object?, Widget>(),
      (_) => const Text('leading', key: ValueKey('leading')),
    );
    await pump(
      t,
      size: const Size(1280, 800),
      chrome: const ShellChrome(platform: ShellPlatform.darwin),
    );
    expect(find.byKey(const ValueKey('leading')), findsNothing);
    layout.controller.toggleSidebar();
    await settle(t);
    expect(find.byKey(const ValueKey('leading')), findsOneWidget);
    expect(
      t.getTopLeft(find.byKey(const ValueKey('leading'))),
      const Offset(88, 11),
    );
    expect(sidebarWidth(t), 0);
  });

  testWidgets('Windows draws the caption row and keeps the leading seat', (
    t,
  ) async {
    slots.register<Object?, Widget>(
      DshShellSlots.shellLeading.typed<Object?, Widget>(),
      (_) => const Text('leading', key: ValueKey('leading')),
    );
    await pump(
      t,
      size: const Size(1280, 800),
      chrome: const ShellChrome(
        platform: ShellPlatform.windows,
        captionControls: SizedBox(key: ValueKey('caption'), width: 138),
      ),
    );
    expect(find.byKey(const ValueKey('caption')), findsOneWidget);
    expect(find.byKey(const ValueKey('leading')), findsOneWidget);
    expect(
      t.getTopLeft(find.byKey(const ValueKey('sidebar-body'))).dy,
      windowsTitlebarHeight,
    );
  });

  testWidgets(
    'the overlay and bottom seats render over and under the columns',
    (t) async {
      slots.register<Object?, Widget>(
        DshShellSlots.shellBottom.typed<Object?, Widget>(),
        (_) => const SizedBox(key: ValueKey('bottom'), height: 24),
      );
      slots.register<Object?, Widget>(
        DshShellSlots.shellOverlay.typed<Object?, Widget>(),
        (_) => const Text('overlay', key: ValueKey('overlay')),
        id: 'a',
      );
      await pump(t, size: const Size(1280, 800));
      expect(find.byKey(const ValueKey('overlay')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('bottom'))).height, 24);
      expect(t.getBottomLeft(find.byKey(const ValueKey('bottom'))).dy, 800);
    },
  );

  group('below 600 the sidebar is a drawer', () {
    Finder drawer() => find.byKey(const ValueKey('phone-drawer'));

    Future<void> phone(WidgetTester t) async {
      dropConversation();
      slots.register<Object?, Widget>(
        DshShellSlots.main.typed<Object?, Widget>(),
        (_) => Builder(
          builder: (context) => PhoneTopBar(
            title: 'Session',
            chrome: PhoneChrome.maybeOf(context)!,
          ),
        ),
        key: conversationPanelKey,
      );
      await pump(t, size: const Size(412, 915));
    }

    testWidgets('the page shows the top bar and no drawer or rail', (t) async {
      await phone(t);
      expect(find.byKey(const ValueKey('phone-top-bar')), findsOneWidget);
      expect(drawer(), findsNothing);
      expect(find.byKey(const ValueKey('phone-edge')), findsOneWidget);
    });

    testWidgets('the menu button opens it at 85% of the width, max 320', (
      t,
    ) async {
      await phone(t);
      await t.tap(find.byKey(const ValueKey('phone-menu')));
      await settle(t);
      expect(drawer(), findsOneWidget);
      expect(t.getSize(drawer()).width, phoneDrawerMaxWidth);
      expect(t.getTopLeft(drawer()).dx, 0);
      expect(find.text('sidebar open 320'), findsOneWidget);
    });

    testWidgets('a phone narrower than 376 takes 85% of its width', (t) async {
      await pump(t, size: const Size(320, 600));
      layout.controller.toggleSidebar();
      await settle(t);
      expect(t.getSize(drawer()).width, closeTo(272, 0.01));
    });

    testWidgets('the top bar and the drawer sit between the system bars', (
      t,
    ) async {
      t.view.padding = const FakeViewPadding(top: 40, bottom: 30);
      t.view.viewPadding = const FakeViewPadding(top: 40, bottom: 30);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      await phone(t);
      expect(t.getTopLeft(find.byKey(const ValueKey('phone-top-bar'))).dy, 40);
      await t.tap(find.byKey(const ValueKey('phone-menu')));
      await settle(t);
      expect(t.getTopLeft(drawer()).dy, 40);
      expect(t.getBottomLeft(drawer()).dy, 915 - 30);
    });

    testWidgets('the scrim closes it', (t) async {
      await phone(t);
      await t.tap(find.byKey(const ValueKey('phone-menu')));
      await settle(t);
      await t.tapAt(const Offset(400, 400));
      await settle(t);
      expect(drawer(), findsNothing);
    });

    testWidgets('a swipe from the left edge opens it', (t) async {
      await phone(t);
      final g = await t.startGesture(const Offset(4, 400));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(12, 0));
      }
      await g.up();
      await settle(t);
      expect(drawer(), findsOneWidget);
    });

    testWidgets('a swipe toward the edge closes it', (t) async {
      await phone(t);
      await t.tap(find.byKey(const ValueKey('phone-menu')));
      await settle(t);
      await t.dragFrom(const Offset(200, 400), const Offset(-120, 0));
      await settle(t);
      expect(drawer(), findsNothing);
    });

    testWidgets('system back closes it', (t) async {
      await phone(t);
      await t.tap(find.byKey(const ValueKey('phone-menu')));
      await settle(t);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(drawer(), findsNothing);
    });

    testWidgets('the new-session button calls the frame callback', (t) async {
      var started = 0;
      dropConversation();
      slots.register<Object?, Widget>(
        DshShellSlots.main.typed<Object?, Widget>(),
        (_) => Builder(
          builder: (context) => PhoneTopBar(
            title: 'Session',
            chrome: PhoneChrome.maybeOf(context)!,
          ),
        ),
        key: conversationPanelKey,
      );
      t.view.physicalSize = const Size(412, 915);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      layout = registerLayoutFeature(
        slots,
        shortcuts: null,
        i18n: () => const DshI18n(DshLocale.en),
        viewportWidth: 412,
      );
      addTearDown(layout.dispose);
      final themed = dshTestApp(const SizedBox()) as MaterialApp;
      await t.pumpWidget(
        MaterialApp(
          theme: themed.theme,
          home: Scaffold(
            body: AppFrame(
              layout: layout,
              slots: slots,
              disableAnimations: true,
              phoneNewSession: () => started++,
            ),
          ),
        ),
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey('phone-new-session')));
      expect(started, 1);
    });

    testWidgets('600 and wider keep the rail, not a drawer', (t) async {
      await pump(t, size: const Size(700, 900));
      expect(find.byKey(const ValueKey('phone-top-bar')), findsNothing);
      expect(find.byKey(const ValueKey('phone-edge')), findsNothing);
      expect(find.text('sidebar rail 56'), findsOneWidget);
    });
  });
}
