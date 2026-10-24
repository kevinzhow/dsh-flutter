import 'dart:async';

import 'package:dsh_feature_workspace/dsh_feature_workspace.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late FakeServices services;
  late SlotRegistry slots;
  late int started;

  void tw(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        services = FakeServices(items: [view('a')]);
        slots = newSlots();
        started = 0;
        registerWorkspaceFeature(slots, services: services, i18n: () => i18n());
        await body(t);
        await t.pump(const Duration(seconds: 1));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });

  Future<void> pump(WidgetTester t, {Size size = const Size(390, 844)}) async {
    await useSize(t, size);
    Widget? action;
    await t.pumpWidget(
      app(
        Builder(
          builder: (context) {
            action = slots.renderSingle(
              DshSlots.sidebarWorkspaces
                  .typed<SidebarWorkspacesOwner, Widget>(),
              SidebarWorkspacesOwner(onStarted: () => started++),
            );
            return Align(alignment: Alignment.topRight, child: action);
          },
        ),
      ),
    );
    await t.pump();
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  tw('is a 44px target with its label', (t) async {
    await pump(t);
    expect(t.getSize(key('workspace-add')), const Size(44, 44));
    expect(find.bySemanticsLabel('Add workspace'), findsOneWidget);
  });

  tw(
    'adding goes straight to the directory flow, adopts the pick and opens a session in it',
    (t) async {
      await pump(t);
      await t.tap(key('workspace-add'));
      await t.pump();
      await t.pump();
      expect(find.text('flow open'), findsOneWidget);
      await t.tap(key('flow-pick'));
      await t.pump();
      await t.pump();
      expect(services.created, ['/work/picked']);
      expect(services.opened, [('new-1', null)]);
      expect(started, 1);
    },
  );

  tw('a refused directory shows the error dialog and starts nothing', (
    t,
  ) async {
    services.createError = refusal('Not a directory');
    await pump(t);
    await t.tap(key('workspace-add'));
    await t.pump();
    await t.pump();
    await t.tap(key('flow-pick'));
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Not a directory'), findsOneWidget);
    expect(services.opened, isEmpty);
    expect(started, 0);
  });

  tw('while an adoption is pending the button is inert', (t) async {
    services.createGate = Completer<void>();
    await pump(t);
    await t.tap(key('workspace-add'));
    await t.pump();
    await t.pump();
    await t.tap(key('flow-pick'));
    await t.pump();
    await t.pump();
    expect(find.text('flow busy'), findsOneWidget);
    services.createGate!.complete();
    await t.pump();
    await t.pump();
    await t.pump();
    expect(started, 1);
  });

  tw('cancelling the flow starts nothing', (t) async {
    await pump(t);
    await t.tap(key('workspace-add'));
    await t.pump();
    await t.pump();
    await t.tap(key('flow-cancel'));
    await t.pump();
    await t.pump();
    expect(find.text('flow open'), findsNothing);
    expect(started, 0);
    // And it can be raised again.
    await t.tap(key('workspace-add'));
    await t.pump();
    await t.pump();
    expect(find.text('flow open'), findsOneWidget);
  });

  tw('hides when no directory picker is composed', (t) async {
    slots = newSlots(sidebarFlow: false);
    registerWorkspaceFeature(slots, services: services, i18n: () => i18n());
    await pump(t);
    expect(key('workspace-add'), findsNothing);
  });
}
