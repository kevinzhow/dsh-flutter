import 'package:dsh_feature_secret_mask/dsh_feature_secret_mask.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw = 'sk-${List.filled(20, 'Q7').join()}';
  final masked = raw.substring(0, 8) + List.filled(raw.length - 8, '*').join();
  Future<void> mount(
    WidgetTester t, {
    String? value,
    String? mask,
    bool interactive = true,
  }) => t.pumpWidget(
    dshTestApp(
      Builder(
        builder: (context) => DefaultTextStyle(
          style: context.dsh.textStyle('--dsw-font-s-14'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              child: SecretText(
                key: const ValueKey('secret-value'),
                raw: value ?? raw,
                masked: mask ?? masked,
                interactive: interactive,
                i18n: const DshI18n(DshLocale.en),
              ),
            ),
          ),
        ),
      ),
      size: const Size(220, 320),
    ),
  );
  testWidgets(
    'hidden semantics contain the mask, reveal keeps the same layout, new raw re-masks',
    (t) async {
      final semantics = t.ensureSemantics();
      await mount(t);
      expect(find.text(raw), findsNothing);
      expect(find.bySemanticsLabel(masked), findsOneWidget);
      expect(find.bySemanticsLabel(raw), findsNothing);
      final before = t.getSize(find.byKey(const ValueKey('secret-value')));
      await t.tap(find.byKey(const ValueKey('secret-toggle')));
      await t.pump();
      expect(find.text(raw), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('secret-value'))), before);
      final changed = 'sk-${List.filled(20, 'Z8').join()}';
      await mount(
        t,
        value: changed,
        mask:
            changed.substring(0, 8) +
            List.filled(changed.length - 8, '*').join(),
      );
      expect(find.text(changed), findsNothing);
      expect(find.bySemanticsLabel(changed), findsNothing);
      expect(t.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'read-only text has no reveal control and keyboard activation works when interactive',
    (t) async {
      await mount(t, interactive: false);
      expect(find.byKey(const ValueKey('secret-toggle')), findsNothing);
      expect(find.text(raw), findsNothing);
      await mount(t);
      Focus.of(t.element(find.byKey(const ValueKey('secret-toggle'))))
          .requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(find.text(raw), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(find.text(raw), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
