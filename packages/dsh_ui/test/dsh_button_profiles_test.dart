import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsh_button_test.dart' show host, official, surface, textColor;

void main() {
  testWidgets('published add profile owns each half and each disabled group', (
    t,
  ) async {
    final theme = official(Brightness.light);
    await t.pumpWidget(
      host(
        theme,
        const DshSplitButton(
          more: Text('More'),
          moreLabel: 'Choose method',
          child: Text('Add'),
        ),
      ),
    );
    final surfaces = find.byKey(DshButton.surfaceKey);
    expect(surfaces, findsNWidgets(2));
    expect(find.byType(ClipRRect), findsNothing);
    for (var i = 0; i < 2; i++) {
      expect(t.getSize(surfaces.at(i)).height, 32);
      final box = t.widget<DshDecoratedBox>(surfaces.at(i));
      final border =
          (box.decoration as ShapeDecoration).shape as DshCornerBorder;
      final corners = border.corners!;
      expect(corners.topLeft.x, i == 0 ? theme.radiusMd : 0);
      expect(corners.bottomLeft.x, i == 0 ? theme.radiusMd : 0);
      expect(corners.topRight.x, i == 1 ? theme.radiusMd : 0);
      expect(corners.bottomRight.x, i == 1 ? theme.radiusMd : 0);
      final opacity = find.ancestor(
        of: surfaces.at(i),
        matching: find.byType(Opacity),
      );
      expect(t.widget<Opacity>(opacity).opacity, .4);
    }
    expect(t.getSize(surfaces.last).width, 32);
    final style = DefaultTextStyle.of(t.element(find.text('Add'))).style;
    expect(style.fontSize, 13);
    expect(style.height, 20 / 13);
  });

  testWidgets(
    'split actions stay independent and a single action has all corners',
    (t) async {
      final theme = official(Brightness.light);
      var primary = 0, more = 0;
      await t.pumpWidget(
        host(
          theme,
          DshSplitButton(
            more: const Text('More'),
            moreLabel: 'Choose method',
            onPressed: () => primary++,
            onMore: () => more++,
            child: const Text('Add'),
          ),
        ),
      );
      await t.tap(find.text('Add'));
      await t.tap(find.text('More'));
      expect(primary, 1);
      expect(more, 1);
      await t.pumpWidget(
        host(
          theme,
          DshSplitButton(
            showMore: false,
            more: const Text('More'),
            moreLabel: 'Choose method',
            onPressed: () => primary++,
            child: const Text('Add'),
          ),
        ),
      );
      expect(find.text('More'), findsNothing);
      final border = surface(t).shape as DshCornerBorder;
      expect(border.corners, isNull);
      expect(border.radius, theme.radiusMd);
    },
  );

  for (final profile in [
    DshButtonProfile.iconAction,
    DshButtonProfile.infoAction,
  ]) {
    testWidgets('$profile uses its own published hover and disabled rules', (
      t,
    ) async {
      final theme = official(Brightness.light);
      await t.pumpWidget(
        host(
          theme,
          DshButton(
            profile: profile,
            onPressed: () {},
            child: const Text('Go'),
          ),
        ),
      );
      final rawIcon = profile == DshButtonProfile.iconAction;
      expect(
        t.getSize(find.byKey(DshButton.surfaceKey)),
        Size.square(rawIcon ? 28 : 20),
      );
      expect(
        t.getCenter(find.text('Go')).dy,
        t.getCenter(find.byKey(DshButton.surfaceKey)).dy,
      );
      expect((surface(t).shape as DshCornerBorder).radius, theme.radiusSm);
      expect(textColor(t), theme.color('--dsw-alias-label-caption'));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(find.byType(DshButton)));
      await t.pump();
      expect(
        textColor(t),
        theme.color(
          rawIcon ? '--dsw-alias-label-secondary' : '--dsw-alias-label-caption',
        ),
      );
      expect(surface(t).color, isNotNull);
      await t.pumpWidget(
        host(theme, DshButton(profile: profile, child: const Text('Go'))),
      );
      final opacity = find.ancestor(
        of: find.byKey(DshButton.surfaceKey),
        matching: find.byType(Opacity),
      );
      expect(t.widget<Opacity>(opacity).opacity, rawIcon ? .5 : .4);
      expect(surface(t).color, isNull);
      await mouse.removePointer();
    });
  }
}
