import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Actions implements WorkspaceManagement {
  int pins = 0;
  @override
  Future<void> pinSession(String id) async {
    pins++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadParityFonts(findParityFontsManifest()));
  testWidgets(
    'row slots render lazily, menus suppress hover and contributed actions run once',
    (t) async {
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      const i18n = DshI18n(DshLocale.en);
      registerSessionRowFeatures(slots, i18n: () => i18n);
      var reads = 0, invoked = 0;
      slots.register<SessionRowOwner, Widget>(
        DshSlots.sidebarSessionRowLeading.typed<SessionRowOwner, Widget>(),
        (_) => const Text('Leading fixture'),
      );
      slots.register<SessionRowOwner, Widget>(
        DshSlots.sidebarSessionRowHover.typed<SessionRowOwner, Widget>(),
        (owner) {
          reads++;
          return Text('Extra ${owner.sessionId}');
        },
        id: 'fixture',
      );
      slots.register<SessionRowOwner, DshMenuEntry?>(
        DshSlots.sidebarWorkspacesSessionMenuItem
            .typed<SessionRowOwner, DshMenuEntry?>(),
        (_) => DshMenuItem(
          'fixture',
          'External action',
          onSelect: () {
            invoked++;
          },
        ),
        id: 'fixture',
        order: 1100,
      );
      final actions = Actions();
      final view = WorkspaceViewState();
      addTearDown(view.dispose);
      await t.pumpWidget(
        dshTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              height: 600,
              child: WorkspaceBrowser(
                snapshot: const SessionListSnapshot(
                  phase: ListPhase.ready,
                  items: [
                    SessionListEntry(
                      SessionSummary(
                        sessionId: 's',
                        updatedAt: 1000,
                        running: false,
                        blank: false,
                        agentAvailable: true,
                      ),
                      'Synthetic row',
                    ),
                  ],
                ),
                workspaces: const [],
                view: view,
                i18n: i18n,
                currentId: 's',
                onOpen: (_) {},
                management: actions,
                slots: slots,
                now: () => DateTime.fromMillisecondsSinceEpoch(1000),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Leading fixture'), findsOneWidget);
      expect(reads, 0);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(
        t.getCenter(find.byKey(const ValueKey('session-row-s'))),
      );
      await t.pump(const Duration(milliseconds: 850));
      await t.pump();
      expect(find.text('Extra s'), findsOneWidget);
      expect(reads, 1);
      await t.tap(find.byKey(const ValueKey('session-row-menu-s')));
      // The source portal stays unplaced until the composited anchor is measured.
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-hover-card')), findsNothing);
      await t.tap(find.byKey(const ValueKey('dsh-menu-fixture')));
      await t.pump();
      expect(invoked, 1);
      await mouse.removePointer();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
