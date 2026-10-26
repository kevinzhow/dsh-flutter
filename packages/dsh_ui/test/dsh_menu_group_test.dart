import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'group headings stick, receive a fill and yield to the next group',
    (t) async {
      final semantics = t.ensureSemantics();
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        dshTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: 100,
              child: CustomScrollView(
                key: const ValueKey('viewport'),
                controller: controller,
                slivers: [
                  for (var group = 0; group < 2; group++)
                    DshMenuGroup(
                      label: group == 0 ? 'Alpha' : 'Beta',
                      headingKey: ValueKey('heading-$group'),
                      separated: group > 0,
                      children: [
                        for (var row = 0; row < 5; row++)
                          SizedBox(
                            height: 30,
                            child: Semantics(
                              button: true,
                              label: 'row-$group-$row',
                              child: const SizedBox.expand(),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final viewportTop = t
          .getTopLeft(find.byKey(const ValueKey('viewport')))
          .dy;
      Finder heading(int n) => find.byKey(ValueKey('heading-$n'));
      ShapeDecoration decoration(int n) =>
          t
                  .widget<DshContainer>(
                    find
                        .ancestor(
                          of: heading(n),
                          matching: find.byType(DshContainer),
                        )
                        .first,
                  )
                  .decoration
              as ShapeDecoration;
      expect(t.getTopLeft(heading(0)).dy, viewportTop + 4);
      expect(decoration(0).color, isNull);
      expect(find.bySemanticsLabel('Alpha'), findsOneWidget);
      expect(find.bySemanticsLabel('row-0-0'), findsOneWidget);

      controller.jumpTo(10);
      await t.pump();
      expect(t.getTopLeft(heading(0)).dy, viewportTop + 4);
      expect(decoration(0).color, isNotNull);

      controller.jumpTo(160);
      await t.pump();
      expect(t.getTopLeft(heading(0)).dy, lessThan(viewportTop + 4));
      expect(t.getTopLeft(heading(1)).dy, greaterThan(viewportTop + 4));
      expect(decoration(1).color, isNull);

      controller.jumpTo(180);
      await t.pump();
      expect(t.getTopLeft(heading(1)).dy, viewportTop + 4);
      expect(decoration(1).color, isNotNull);
      expect(find.bySemanticsLabel('Beta'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('wrapped headings and platform corners use the available width', (
    t,
  ) async {
    await t.pumpWidget(
      dshTestApp(
        const ShellScope(
          chrome: ShellChrome(platform: ShellPlatform.darwin),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              height: 200,
              child: CustomScrollView(
                slivers: [
                  DshMenuGroup(
                    label: 'A provider with a long translated heading',
                    headingKey: ValueKey('long-heading'),
                    children: [
                      SizedBox(key: ValueKey('first-row'), height: 30),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final heading = find.byKey(const ValueKey('long-heading'));
    final row = find.byKey(const ValueKey('first-row'));
    expect(t.getSize(heading).height, greaterThan(16));
    expect(t.getTopLeft(row).dy, t.getBottomLeft(heading).dy + 2);
    final box = t.widget<DshContainer>(
      find.ancestor(of: heading, matching: find.byType(DshContainer)).first,
    );
    expect(
      ((box.decoration as ShapeDecoration).shape as DshCornerBorder).radius,
      0,
    );
  });

  testWidgets(
    'large text and a narrow viewport expand the heading before the rows',
    (t) async {
      await t.pumpWidget(
        dshTestApp(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 100,
                height: 300,
                child: CustomScrollView(
                  slivers: [
                    DshMenuGroup(
                      label: 'Long translated provider',
                      headingKey: ValueKey('scaled-heading'),
                      children: [
                        SizedBox(key: ValueKey('scaled-row'), height: 30),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final heading = find.byKey(const ValueKey('scaled-heading'));
      expect(t.getSize(heading).height, greaterThan(32));
      expect(
        t.getTopLeft(find.byKey(const ValueKey('scaled-row'))).dy,
        t.getBottomLeft(heading).dy + 2,
      );
      expect(t.takeException(), isNull);
    },
  );
}
