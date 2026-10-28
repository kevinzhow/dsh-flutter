import 'dart:ui' as ui;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsh_button_test.dart' show host, official;

Widget card({
  required VoidCallback open,
  ValueChanged<bool>? change,
  FocusNode? focus,
  String? description = 'Synthetic description',
  String? metadataError,
  ImageProvider? image,
  List<Widget> tags = const [],
  String title = 'Synthetic title',
}) => SizedBox(
  width: 358,
  child: DshPluginCard(
    title: title,
    semanticLabel: 'Open synthetic',
    description: description,
    metadataError: metadataError,
    focusNode: focus,
    image: image,
    tags: tags,
    onOpen: open,
    actions: [
      DshSwitch(value: true, onChanged: change, label: 'Enable synthetic'),
    ],
  ),
);

void main() {
  for (final density in [1.0, 2.625]) {
    for (final brightness in Brightness.values) {
      testWidgets('source content boxes at $density ${brightness.name}', (
        t,
      ) async {
        t.view.devicePixelRatio = density;
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(host(official(brightness), card(open: () {})));
        final border = density == 1 ? 1 : 1 / density;
        expect(
          t.getSize(find.byKey(DshPluginCard.frameKey)),
          Size.square(48 + border * 2),
        );
        expect(
          t.getSize(find.byType(DshPluginCard)).height,
          closeTo(64 + border * 2, .001),
        );
        expect(
          t.getSize(find.byType(DshPluginDefaultArtwork)),
          const Size(36, 36),
        );

        await t.pumpWidget(
          host(
            official(brightness),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DshTag.text(
                  'Filled',
                  tone: DshTagTone.info,
                  profile: DshTagProfile.pluginStatus,
                ),
                DshTag.text('Outline', profile: DshTagProfile.pluginStatus),
              ],
            ),
          ),
        );
        final tags = find.byType(DshTag);
        expect(t.getSize(tags.first).height, 18);
        expect(t.getSize(tags.last).height, closeTo(18 + border * 2, .001));
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'card outline follows source pointer modality ${brightness.name}',
      (t) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var opens = 0;
        await t.pumpWidget(
          host(official(brightness), card(open: () => opens++, focus: focus)),
        );
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: t.getCenter(find.text('Synthetic title')),
        );
        try {
          await mouse.down(t.getCenter(find.text('Synthetic title')));
          await t.pump(const Duration(milliseconds: 200));
          expect(focus.hasPrimaryFocus, isTrue);
          expect(opens, 0);
          expect(find.byKey(DshButton.focusRingKey), findsNothing);
          await mouse.up();
          await t.pump();
          expect(opens, 1);
          await t.sendKeyEvent(LogicalKeyboardKey.home);
          await t.pump();
          expect(focus.hasPrimaryFocus, isTrue);
          expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
        } finally {
          await mouse.removePointer();
        }
      },
    );
  }

  testWidgets('the contour rejects a corner but title, tag and metadata open', (
    t,
  ) async {
    var opens = 0;
    await t.pumpWidget(
      host(
        official(Brightness.light),
        card(
          open: () => opens++,
          metadataError: 'Metadata diagnostic',
          tags: [DshTag.text('Problem', profile: DshTagProfile.pluginStatus)],
        ),
      ),
    );
    final bounds = t.getRect(find.byType(DshPluginCard));
    await t.tapAt(bounds.topLeft + const Offset(2, 2));
    expect(opens, 0);
    await t.tapAt(Offset(bounds.left + 2, bounds.center.dy));
    expect(opens, 1);
    await t.tap(find.text('Synthetic title'));
    await t.tap(find.text('Problem'));
    await t.tap(find.text('Metadata diagnostic'));
    expect(opens, 4);
    expect(t.takeException(), isNull);
  });

  testWidgets('disabled trailing control absorbs input above the card target', (
    t,
  ) async {
    var opens = 0;
    await t.pumpWidget(
      host(official(Brightness.dark), card(open: () => opens++)),
    );
    await t.tap(find.byType(DshSwitch));
    expect(opens, 0);
    expect(
      t
          .getSemantics(find.byType(DshSwitch))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
  });

  testWidgets('title and switch keep independent keyboard and native actions', (
    t,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var opens = 0, changes = 0;
    await t.pumpWidget(
      host(
        official(Brightness.light),
        card(open: () => opens++, change: (_) => changes++, focus: focus),
      ),
    );
    final action = find.byKey(DshPluginCard.actionKey);
    final semantics = t.getSemantics(action);
    expect(semantics.getSemanticsData().hint, 'Synthetic description');
    semantics.owner!.performAction(semantics.id, SemanticsAction.tap);
    expect(opens, 1);
    expect(changes, 0);
    final toggle = t.getSemantics(find.byType(DshSwitch));
    toggle.owner!.performAction(toggle.id, SemanticsAction.tap);
    expect(opens, 1);
    expect(changes, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(opens, 3);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(focus.hasPrimaryFocus, isFalse);
    expect(find.byKey(DshButton.focusRingKey), findsNothing);
    expect(find.byKey(const ValueKey('dsh-switch-focus-ring')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(opens, 3);
    expect(changes, 2);
  });

  testWidgets(
    'hover over a trailing switch paints the card; touch-down does not',
    (t) async {
      await t.pumpWidget(
        host(official(Brightness.dark), card(open: () {}, change: (_) {})),
      );
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final surface = find.descendant(
        of: find.byKey(DshPluginCard.actionKey),
        matching: find.byKey(DshButton.surfaceKey),
      );
      Color? fill() =>
          (t.widget<DshDecoratedBox>(surface).decoration as ShapeDecoration)
              .color;
      expect(fill(), isNull);
      await mouse.moveTo(t.getCenter(find.byType(DshSwitch)));
      await t.pump();
      expect(fill(), isNotNull);
      await mouse.removePointer();
      await t.pump();
      expect(fill(), isNull);
      final touch = await t.startGesture(
        t.getCenter(find.text('Synthetic title')),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(fill(), isNull);
      await touch.up();
    },
  );

  testWidgets('long title and status tags increase natural height', (t) async {
    await t.pumpWidget(
      host(
        official(Brightness.light),
        card(
          open: () {},
          title: 'A very long synthetic plugin title used to inspect title ellipsis and wrapping',
          tags: [
            DshTag.text(
              'Experimental',
              tone: DshTagTone.info,
              profile: DshTagProfile.pluginStatus,
            ),
            DshTag.text(
              'Problem',
              tone: DshTagTone.danger,
              profile: DshTagProfile.pluginStatus,
            ),
            DshTag.text(
              'Package unavailable',
              profile: DshTagProfile.pluginStatus,
            ),
            DshTag.text(
              'Update available',
              tone: DshTagTone.info,
              profile: DshTagProfile.pluginStatus,
            ),
          ],
        ),
      ),
    );
    expect(t.getSize(find.byType(DshPluginCard)).height, greaterThan(66));
    final description = t.widget<Text>(find.text('Synthetic description'));
    expect(description.maxLines, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('hover never declares a translucent unknown backdrop opaque', (
    t,
  ) async {
    final theme = official(Brightness.light);
    await t.pumpWidget(host(theme, card(open: () {})));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.text('Synthetic title')));
    await t.pump();
    final frame = t.widget<DshContainer>(find.byKey(DshPluginCard.frameKey));
    final decoration = frame.decoration as ShapeDecoration;
    expect(
      (decoration.shape as DshCornerBorder).side.color,
      DshSurface.quantizeAlpha(
        theme.color(DshPluginCardRecipe.iconBorderToken),
      ),
    );
    await mouse.removePointer();
  });

  testWidgets(
    'image decode failure keeps artwork size and a new image recovers',
    (t) async {
      final valid = await t.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawColor(const Color(0xff336699), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(1, 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return bytes!.buffer.asUint8List();
      });
      final failed = MemoryImage(Uint8List.fromList([0, 1, 2]));
      Future<void> show(ImageProvider provider) async {
        await t.pumpWidget(
          host(official(Brightness.light), card(open: () {}, image: provider)),
        );
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }

      await show(failed);
      expect(find.byType(DshPluginDefaultArtwork), findsOneWidget);
      expect(
        t.getSize(find.byType(DshPluginDefaultArtwork)),
        const Size(36, 36),
      );
      await show(failed);
      expect(find.byType(DshPluginDefaultArtwork), findsOneWidget);
      await show(MemoryImage(valid!));
      expect(find.byType(DshPluginDefaultArtwork), findsNothing);
      expect(t.getSize(find.byType(Image)), const Size(36, 36));
      expect(t.takeException(), isNull);
    },
  );
}
