import 'dart:async';

import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'exit waits for Host projection; duplicate clicks disabled; refusal can retry',
    (t) async {
      final gate = Completer<String?>();
      var calls = 0;
      Future<String?> exit() async {
        calls++;
        return calls == 1 ? gate.future : null;
      }

      Widget view(Object? projection) => dshTestApp(
        Row(
          children: [
            PlanChip(
              projection: projection,
              i18n: const DshI18n(DshLocale.en),
              exitPlanMode: exit,
            ),
          ],
        ),
      );
      await t.pumpWidget(view({'active': true, 'pending': false}));
      final chip = find.byKey(const ValueKey('plan-chip'));
      await t.tap(chip);
      await t.pump();
      await t.tap(chip);
      expect(calls, 1);
      gate.complete('Synthetic refusal');
      await t.pump();
      expect(find.byKey(const ValueKey('plan-exit-error')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(chip);
      await t.pump();
      expect(calls, 2);
      expect(chip, findsOneWidget); // admission is not an optimistic mode flip
      await t.pumpWidget(view({'active': true, 'pending': true}));
      expect(chip, findsNothing);
    },
  );
  testWidgets(
    'locked chip never invokes exit, delayed settlement after disposal is harmless',
    (t) async {
      var calls = 0;
      final gate = Completer<String?>();
      Future<String?> exit() {
        calls++;
        return gate.future;
      }

      Widget view(bool locked) => dshTestApp(
        PlanChip(
          projection: const {'active': true},
          locked: locked,
          i18n: const DshI18n(DshLocale.en),
          exitPlanMode: exit,
        ),
      );
      await t.pumpWidget(view(true));
      await t.tap(find.byKey(const ValueKey('plan-chip')));
      expect(calls, 0);
      await t.pumpWidget(view(false));
      await t.tap(find.byKey(const ValueKey('plan-chip')));
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
      gate.complete(null);
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
