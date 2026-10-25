import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Actions implements WorkspaceManagement {
  final List<bool> archives = [];
  @override
  Future<void> archiveSession(String id, {bool stopActivity = false}) async {
    archives.add(stopActivity);
    if (!stopActivity) {
      throw RemoteException('workspace/session-active', 'Synthetic work', {
        'activity': [
          {'kind': 'turn'},
          {
            'kind': 'job',
            'items': [
              {'id': 'job', 'label': 'Synthetic check'},
            ],
          },
        ],
      });
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadParityFonts(findParityFontsManifest()));
  const i18n = DshI18n(DshLocale.en);
  testWidgets('refused rename retains draft; retry settles the same dialog', (
    t,
  ) async {
    var fail = true;
    final calls = <String?>[];
    await t.pumpWidget(
      dshTestApp(
        Builder(
          builder: (context) => GestureDetector(
            onTap: () => showDshDialog<void>(
              context,
              builder: (_) => WorkspaceActionForm(
                title: 'Rename session',
                confirmLabel: 'Rename',
                initial: 'Before',
                fieldLabel: 'Session name',
                i18n: i18n,
                submit: (name) async {
                  calls.add(name);
                  if (fail) {
                    throw RemoteException(
                      'rename/refused',
                      'Synthetic refusal',
                    );
                  }
                },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('workspace-action-name')),
      '  After  ',
    );
    await t.tap(find.byKey(const ValueKey('workspace-action-confirm')));
    await t.pumpAndSettle();
    expect(find.text('Synthetic refusal'), findsOneWidget);
    expect(find.text('  After  '), findsOneWidget);
    expect(calls, ['After']);
    fail = false;
    await t.tap(find.byKey(const ValueKey('workspace-action-confirm')));
    await t.pumpAndSettle();
    expect(calls, ['After', 'After']);
    expect(find.byKey(const ValueKey('workspace-action-form')), findsNothing);
  });
  testWidgets('in-flight confirmation cannot dismiss or submit twice', (
    t,
  ) async {
    final gate = Completer<void>();
    var calls = 0;
    await t.pumpWidget(
      dshTestApp(
        WorkspaceActionForm(
          title: 'Rename',
          confirmLabel: 'Save',
          initial: 'Before',
          i18n: i18n,
          submit: (_) {
            calls++;
            return gate.future;
          },
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('workspace-action-confirm')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('workspace-action-confirm')));
    await t.pump();
    expect(calls, 1);
    final pop = t.widget<PopScope>(find.byType(PopScope).last);
    expect(pop.canPop, false);
    await t.pumpWidget(const SizedBox());
    gate.complete();
    await t.pump();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'active archive requires explicit stop confirmation and names work',
    (t) async {
      final actions = Actions();
      await t.pumpWidget(
        dshTestApp(
          Builder(
            builder: (context) => GestureDetector(
              onTap: () => unawaited(
                archiveSessionAction(context, actions, i18n, 's', 'Fixture'),
              ),
              child: const Text('Archive'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Archive'));
      await t.pumpAndSettle();
      expect(actions.archives, [false]);
      expect(find.textContaining('Synthetic check'), findsOneWidget);
      expect(find.text('Stop and archive'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(actions.archives, [false]);
      await t.tap(find.text('Archive'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('workspace-action-confirm')));
      await t.pumpAndSettle();
      expect(actions.archives, [false, false, true]);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(find.byKey(const ValueKey('workspace-action-form')), findsNothing);
    },
  );
}
