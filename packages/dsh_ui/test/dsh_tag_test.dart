import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'source outline and neutral tags use their content-box geometry',
    (t) async {
      await t.pumpWidget(
        dshTestApp(
          MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 1),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DshTag.text('Built-in', key: const ValueKey('outline')),
                  DshTag.text(
                    'Built-in',
                    key: const ValueKey('neutral'),
                    tone: DshTagTone.neutral,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final outline = t.getSize(find.byKey(const ValueKey('outline')));
      final neutral = t.getSize(find.byKey(const ValueKey('neutral')));
      expect(neutral.height, 19);
      expect(
        outline.height,
        21,
      ); // The half-pixel CSS border snaps to one pixel at DPR 1.
      expect(outline.width, neutral.width + 2);
      expect(find.byType(FocusableActionDetector), findsNothing);
      final semantics = t.ensureSemantics();
      final node = t.getSemantics(find.text('Built-in').first);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'status tones use the published tint and keep their text visible',
    (t) async {
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DshTag.text('Success', tone: DshTagTone.success),
                DshTag.text('Warning', tone: DshTagTone.warning),
                DshTag.text('Quiet', tone: DshTagTone.quiet),
              ],
            ),
          ),
        ),
      );
      BoxDecoration decoration(String text) =>
          t
                  .widget<DshContainer>(
                    find
                        .descendant(
                          of: find.ancestor(
                            of: find.text(text),
                            matching: find.byType(DshTag),
                          ),
                          matching: find.byType(DshContainer),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration('Success').color!.a, closeTo(26 / 255, .00001));
      expect(decoration('Warning').color!.a, closeTo(31 / 255, .00001));
      expect(decoration('Quiet').color, isNull);
      expect(find.text('Success'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
    },
  );
}
