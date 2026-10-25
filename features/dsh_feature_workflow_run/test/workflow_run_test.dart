import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_workflow_run/dsh_feature_workflow_run.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const i18n = DshI18n(DshLocale.en);
WorkflowRunData data(WorkflowRunStatus status, {int count = 1}) =>
    WorkflowRunData(
      name: 'Synthetic review',
      status: status,
      phases: [
        WorkflowRunPhase('Read', [
          for (var i = 0; i < count; i++)
            WorkflowRunMember(
              seq: i,
              label: 'Reader $i',
              childId: 'child-$i',
              status: status,
            ),
        ]),
      ],
    );
void main() {
  testWidgets('accessible member bounds exclude the following settled row', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    var opens = 0;
    const d = WorkflowRunData(
      name: 'Synthetic review',
      status: WorkflowRunStatus.running,
      phases: [
        WorkflowRunPhase('Read', [
          WorkflowRunMember(
            seq: 1,
            label: 'Active reader',
            childId: 'child-a',
            status: WorkflowRunStatus.running,
          ),
          WorkflowRunMember(
            seq: 2,
            label: 'Finished reader',
            childId: 'child-b',
            status: WorkflowRunStatus.completed,
          ),
        ]),
      ],
    );
    await tester.pumpWidget(
      dshTestApp(
        WorkflowRunPanel(
          data: d,
          i18n: i18n,
          canOpen: (m) => m.status == WorkflowRunStatus.running,
          onOpen: (_) => opens++,
        ),
      ),
    );
    final member = find.bySemanticsLabel('Open Active reader');
    expect(member, findsOneWidget);
    expect(tester.getSize(member).height, 24);
    await tester.tap(member);
    await tester.pump();
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'clean run starts closed; abnormal transitions open it; keyboard toggles',
    (tester) async {
      await tester.pumpWidget(
        dshTestApp(
          WorkflowRunPanel(data: data(WorkflowRunStatus.completed), i18n: i18n),
        ),
      );
      expect(find.text('Reader 0'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Reader 0'), findsNothing);
      await tester.pumpWidget(
        dshTestApp(
          WorkflowRunPanel(data: data(WorkflowRunStatus.failed), i18n: i18n),
        ),
      );
      expect(find.text('Reader 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'manual running collapse survives updates and a new clean cycle reopens',
    (tester) async {
      await tester.pumpWidget(
        dshTestApp(
          WorkflowRunPanel(data: data(WorkflowRunStatus.running), i18n: i18n),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('workflow-run-header')));
      await tester.pump();
      expect(find.text('Reader 0'), findsNothing);
      await tester.pumpWidget(
        dshTestApp(
          WorkflowRunPanel(
            data: data(WorkflowRunStatus.running, count: 2),
            i18n: i18n,
          ),
        ),
      );
      expect(find.text('Reader 0'), findsNothing);
      await tester.pumpWidget(
        dshTestApp(
          WorkflowRunPanel(
            data: data(WorkflowRunStatus.completed, count: 2),
            i18n: i18n,
          ),
        ),
      );
      await tester.pumpWidget(
        dshTestApp(
          WorkflowRunPanel(
            data: data(WorkflowRunStatus.running, count: 2),
            i18n: i18n,
          ),
        ),
      );
      expect(find.text('Reader 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'settlement preserves a focused member until focus leaves; stale navigation is disabled',
    (tester) async {
      final outside = FocusNode();
      addTearDown(outside.dispose);
      var opens = 0, allowed = true;
      Widget app(WorkflowRunStatus status) => dshTestApp(
        Column(
          children: [
            WorkflowRunPanel(
              data: data(status),
              i18n: i18n,
              canOpen: (_) => allowed,
              onOpen: (_) => opens++,
            ),
            Focus(
              focusNode: outside,
              child: GestureDetector(
                onTap: outside.requestFocus,
                child: const Text('Outside'),
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(app(WorkflowRunStatus.running));
      await tester.tap(find.text('Reader 0'));
      await tester.pump();
      expect(opens, 1);
      allowed = false;
      await tester.pumpWidget(app(WorkflowRunStatus.completed));
      expect(find.text('Reader 0'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opens, 1);
      await tester.tap(find.text('Outside'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Reader 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('phone overflow and missing/empty phase labels remain readable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final d = WorkflowRunData(
      name: 'Synthetic long workflow name',
      status: WorkflowRunStatus.interrupted,
      phases: [
        WorkflowRunPhase(null, const [
          WorkflowRunMember(
            seq: 1,
            label: '',
            childId: 'none',
            status: WorkflowRunStatus.interrupted,
          ),
        ]),
        const WorkflowRunPhase('', []),
      ],
    );
    await tester.pumpWidget(
      dshTestApp(
        SizedBox(
          width: 240,
          child: WorkflowRunPanel(data: d, i18n: i18n),
        ),
      ),
    );
    expect(find.text('Unphased'), findsOneWidget);
    expect(find.text('Empty phase name'), findsOneWidget);
    expect(find.text('Empty member name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
