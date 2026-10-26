import 'dart:async';

import 'package:dsh_feature_workspace/dsh_feature_workspace.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart' show WorkspacePhase;
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshDialogFrame;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late FakeServices services;
  late SlotRegistry slots;
  late List<String> log;
  final hostKey = GlobalKey<ChipHostState>();

  void tw(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        services = FakeServices(
          items: [
            view('a', title: 'alpha'),
            view('b', title: 'beta'),
          ],
        );
        slots = newSlots();
        log = [];
        registerWorkspaceFeature(
          slots,
          services: services,
          i18n: () => i18n(currentLocale),
        );
        await body(t);
        await t.pump(const Duration(seconds: 1));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });

  Future<void> pump(
    WidgetTester t, {
    Size size = const Size(1000, 760),
    String? selected,
    bool open = false,
  }) async {
    await useSize(t, size);
    await t.pumpWidget(
      app(
        ChipHost(
          key: hostKey,
          services: services,
          slots: slots,
          i18n: i18n(currentLocale),
          log: log,
          selectedId: selected,
          initiallyOpen: open,
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  group('wide window: the anchored menu', () {
    tw(
      'lists the workspaces, the add action pinned below, and marks the one in use',
      (t) async {
        await pump(t, selected: 'b');
        await t.tap(key('chip'));
        await t.pumpAndSettle();
        expect(key('workspace-menu'), findsOneWidget);
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('beta'), findsOneWidget);
        expect(find.text('Add workspace…'), findsOneWidget);
        // The check trails the selected row only.
        expect(
          find.descendant(
            of: key('dsh-menu-b'),
            matching: find.byType(CustomPaint),
          ),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: key('dsh-menu-a'),
            matching: find.byType(CustomPaint),
          ),
          findsNWidgets(1),
        );
      },
    );

    tw('hangs 4px below its anchor, left edges aligned', (t) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      final chip = t.getRect(key('chip'));
      final menu = t.getRect(key('workspace-menu'));
      expect(menu.left, chip.left);
      expect(menu.top, chip.bottom + 4);
      expect(menu.width, inInclusiveRange(144, 360));
    });

    tw('picking a workspace reports it and closes the menu', (t) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tap(key('dsh-menu-a'));
      await t.pumpAndSettle();
      expect(log, ['pick:a']);
      expect(key('workspace-menu'), findsNothing);
    });

    tw('the chip toggles the menu; an outside press and Escape close it', (
      t,
    ) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(key('workspace-menu'), findsOneWidget);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(key('workspace-menu'), findsNothing);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(900, 600));
      await t.pumpAndSettle();
      expect(key('workspace-menu'), findsNothing);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(key('workspace-menu'), findsNothing);
    });

    tw('arrows walk the rows and Enter settles the focused one', (t) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(log, ['pick:b']);
    });

    tw('arrows wrap past the pinned add action', (t) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(key('flow-state'), findsOneWidget);
    });

    tw('while the list loads the menu says so', (t) async {
      services.set(const [], phase: WorkspacePhase.pending);
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(key('workspace-menu-status'), findsOneWidget);
      expect(find.text('Loading workspaces…'), findsOneWidget);
      // The baseline arrives while it is open.
      services.set([view('a', title: 'alpha')]);
      await t.pumpAndSettle();
      expect(key('workspace-menu-status'), findsNothing);
      expect(find.text('alpha'), findsOneWidget);
    });

    tw('the first-use workspace reads as the localized default', (t) async {
      services.set([view('d', title: 'default-workspace')]);
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(find.text('Default workspace'), findsOneWidget);
    });
  });

  group('adding a workspace', () {
    tw('Add workspace raises the flow; a picked path is adopted and picked', (
      t,
    ) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tap(key('dsh-menu-::add-workspace'));
      await t.pumpAndSettle();
      expect(key('workspace-menu'), findsNothing);
      expect(find.text('flow open'), findsOneWidget);
      await t.tap(key('flow-pick'));
      await t.pumpAndSettle();
      expect(services.created, ['/work/picked']);
      expect(log, contains('pick:new-1'));
      expect(find.text('flow open'), findsNothing);
    });

    tw('while a pick is adopted the flow is busy and the menu actions wait', (
      t,
    ) async {
      services.createGate = Completer<void>();
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tap(key('dsh-menu-::add-workspace'));
      await t.pumpAndSettle();
      await t.tap(key('flow-pick'));
      await t.pump();
      expect(find.text('flow busy'), findsOneWidget);
      services.createGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('flow busy'), findsNothing);
    });

    tw('cancelling the flow just closes it', (t) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tap(key('dsh-menu-::add-workspace'));
      await t.pumpAndSettle();
      await t.tap(key('flow-cancel'));
      await t.pump();
      expect(find.text('flow open'), findsNothing);
      expect(services.created, isEmpty);
      expect(log.where((e) => e.startsWith('pick')), isEmpty);
    });

    tw(
      'a refused directory opens the error dialog with the Host message; Choose again reopens the flow',
      (t) async {
        services.createError = refusal('Not a directory');
        await pump(t);
        await t.tap(key('chip'));
        await t.pumpAndSettle();
        await t.tap(key('dsh-menu-::add-workspace'));
        await t.pumpAndSettle();
        await t.tap(key('flow-pick'));
        await t.pumpAndSettle();
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('Couldn’t open folder'), findsOneWidget);
        expect(find.text('Not a directory'), findsOneWidget);
        expect(find.text('flow open'), findsNothing);
        expect(log.where((e) => e.startsWith('pick')), isEmpty);
        await t.tap(key('folder-error-retry'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        await t.pump();
        expect(find.text('Couldn’t open folder'), findsNothing);
        expect(find.text('flow open'), findsOneWidget);
      },
    );

    tw('Cancel on the error dialog leaves nothing open', (t) async {
      services.createError = refusal('Not a directory');
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tap(key('dsh-menu-::add-workspace'));
      await t.pumpAndSettle();
      await t.tap(key('flow-pick'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(key('folder-error-cancel'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Couldn’t open folder'), findsNothing);
      expect(find.text('flow open'), findsNothing);
    });

    tw('a failure the flow itself reports reaches the same dialog', (t) async {
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tap(key('dsh-menu-::add-workspace'));
      await t.pumpAndSettle();
      await t.tap(key('flow-fail'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('denied by the host'), findsOneWidget);
    });

    tw('with no workspaces the chip IS the add action', (t) async {
      services.set(const []);
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(key('workspace-menu'), findsNothing);
      expect(find.text('flow open'), findsOneWidget);
    });

    tw('with no workspaces and a list still loading the menu waits', (t) async {
      services.set(const [], phase: WorkspacePhase.pending);
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(find.text('flow open'), findsNothing);
      services.set(const []);
      await t.pumpAndSettle();
      await t.pump();
      expect(find.text('flow open'), findsOneWidget);
    });

    tw('with no directory picker composed an empty list shows nothing', (
      t,
    ) async {
      slots = newSlots(heroFlow: false);
      registerWorkspaceFeature(slots, services: services, i18n: () => i18n());
      services.set(const []);
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(key('workspace-menu'), findsNothing);
    });

    tw(
      'without a directory picker the list still shows but offers no add action',
      (t) async {
        slots = newSlots(heroFlow: false);
        registerWorkspaceFeature(slots, services: services, i18n: () => i18n());
        await pump(t);
        await t.tap(key('chip'));
        await t.pumpAndSettle();
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('Add workspace…'), findsNothing);
      },
    );
  });

  group('a phone gets the same popover as web', () {
    tw('the menu hangs under the chip at 390px, 34px rows', (t) async {
      await pump(t, size: const Size(390, 844));
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      final chip = t.getRect(key('chip'));
      final menu = t.getRect(key('workspace-menu'));
      expect(menu.left, chip.left);
      expect(menu.top, chip.bottom + 4);
      expect(t.getSize(key('dsh-menu-a')).height, 34);
      await t.tap(key('dsh-menu-b'));
      await t.pump();
      expect(log, contains('pick:b'));
    });

    tw('Add workspace raises the flow; the error dialog is the centered card', (
      t,
    ) async {
      services.createError = refusal('Not a directory');
      await pump(t, size: const Size(390, 844));
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      await t.tap(key('dsh-menu-::add-workspace'));
      await t.pumpAndSettle();
      expect(find.text('flow open'), findsOneWidget);
      await t.tap(key('flow-pick'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Not a directory'), findsOneWidget);
      final form = t.getRect(find.byType(DshDialogFrame));
      expect(form.width, 342);
      expect(form.center.dx, closeTo(195, 1));
      expect(form.center.dy, closeTo(422, 60));
    });
  });

  group('zh', () {
    tw('the menu and the error dialog speak Chinese', (t) async {
      currentLocale = DshLocale.zh;
      addTearDown(() => currentLocale = DshLocale.en);
      slots = newSlots();
      registerWorkspaceFeature(
        slots,
        services: services,
        i18n: () => i18n(DshLocale.zh),
      );
      services.createError = refusal('不是目录');
      await pump(t);
      await t.tap(key('chip'));
      await t.pumpAndSettle();
      expect(find.text('添加工作区…'), findsOneWidget);
      await t.tap(key('dsh-menu-::add-workspace'));
      await t.pumpAndSettle();
      await t.tap(key('flow-pick'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('无法打开文件夹'), findsOneWidget);
      expect(find.text('重新选择'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });
  });
}

DshLocale currentLocale = DshLocale.en;
