import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> goal({String id = 'g', int revision = 1}) => {
  'id': id,
  'revision': revision,
  'objective': 'Synthetic objective',
  'phase': 'paused',
  'maxGoalRounds': 12,
};
void main() {
  testWidgets(
    'goal edits use latest revision, clear hides accepted identity and replacement discards old draft',
    (tester) async {
      final host = FakeHost(), session = Session('s', FakeTransport());
      session.projections.apply('goal', {'goal': goal()}, 1);
      host.handlers['goals/edit'] = (_) => {
        ...goal(revision: 3),
        'roundsStarted': 1,
        'createdAt': 1000,
        'updatedAt': 1001,
        'activation': 'disarmed',
      };
      host.handlers['goals/clear'] = (_) => {'id': 'new', 'revision': 2};
      final model = GoalModel(
        session: session,
        remotes: host.remotes,
        ensureOpen: () async {},
      );
      const i18n = DshI18n(DshLocale.en);
      String t(String key) => i18n.t('goal', key);
      await tester.pumpWidget(dshTestApp(GoalBar(model: model, i18n: i18n)));
      await tester.tap(find.bySemanticsLabel(t('action.edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Updated objective');
      session.projections.apply('goal', {'goal': goal(revision: 2)}, 2);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(t('action.save')));
      await tester.pumpAndSettle();
      expect(host.callsTo('goals/edit').single.args['ref'], {
        'id': 'g',
        'revision': 2,
      });
      await tester.tap(find.bySemanticsLabel(t('action.edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Abandoned draft');
      session.projections.apply('goal', {'goal': goal(id: 'new')}, 3);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.bySemanticsLabel(t('action.clear')));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic objective'), findsNothing);
      expect(host.callsTo('goals/clear').single.args['ref'], {
        'id': 'new',
        'revision': 1,
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await model.dispose();
        await session.dispose();
        await host.close();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
