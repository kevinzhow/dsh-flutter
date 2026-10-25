import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_reference/dsh_feature_reference.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a file navigation refusal remains local and retries the same reference',
    (t) async {
      var calls = 0;
      final owner = UserTextNodeOwner(
        node: UserTextNode('file', 0, 7, {'path': 'a.dart', 'label': 'a.dart'}),
        raw: '@a.dart',
        interactive: true,
      );
      await t.pumpWidget(
        dshTestApp(
          SentPathReference(
            owner: owner,
            i18n: const DshI18n(DshLocale.en),
            open: () {
              if (++calls == 1) throw StateError('Synthetic refusal');
            },
          ),
        ),
      );
      await t.tap(find.byType(DshReferenceChip));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(
        t.widget<DshReferenceChip>(find.byType(DshReferenceChip)).label,
        'a.dart',
      );
      expect(find.textContaining('a.dart'), findsWidgets);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(DshReferenceChip), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('noninteractive references preserve labels without activation', (
    t,
  ) async {
    var calls = 0;
    final owner = UserTextNodeOwner(
      node: UserTextNode('file', 0, 7, {'path': 'a.dart', 'label': 'a.dart'}),
      raw: '@a.dart',
      interactive: false,
    );
    await t.pumpWidget(
      dshTestApp(
        SentPathReference(
          owner: owner,
          i18n: const DshI18n(DshLocale.en),
          open: () => calls++,
        ),
      ),
    );
    await t.tap(find.byType(DshReferenceChip));
    await t.pump();
    expect(calls, 0);
  });
}
