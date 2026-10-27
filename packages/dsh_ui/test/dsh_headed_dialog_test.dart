import 'dart:ui' show SemanticsAction;

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const headerKey = ValueKey('headed-header');
const bodyKey = ValueKey('headed-body');
const contentKey = ValueKey('headed-content');
const footerKey = ValueKey('headed-footer');
const closeKey = ValueKey('headed-close');
const probeBodyKey = ValueKey('probe-body');
const cancelKey = ValueKey('cancel');
const confirmKey = ValueKey('confirm');

void main() {
  DshHeadedDialogContent dialog({
    String? description = 'One line',
    Widget? body = const SizedBox(key: probeBodyKey, height: 40),
    bool footer = true,
    bool scrollContent = false,
    bool closeAutofocus = false,
    VoidCallback? onClose,
  }) => DshHeadedDialogContent(
    title: 'Danger',
    closeLabel: 'Close confirmation',
    onClose: onClose ?? () {},
    description: description,
    body: body,
    scrollContent: scrollContent,
    closeAutofocus: closeAutofocus,
    headerKey: headerKey,
    bodyKey: bodyKey,
    contentKey: contentKey,
    footerKey: footerKey,
    closeKey: closeKey,
    footer: footer
        ? [
            const SizedBox(key: cancelKey, width: 72, height: 36),
            const SizedBox(key: confirmKey, width: 136, height: 36),
          ]
        : null,
  );

  Future<void> pumpDialog(
    WidgetTester tester,
    Widget child, {
    double maxHeight = 500,
  }) async {
    await tester.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('headed profile matches the published Modal boxes and type', (
    tester,
  ) async {
    await pumpDialog(tester, dialog());

    // Source: header22/14/12/24 with Close28; description22; body margin20;
    // content/footer gap20, footer36, and root bottom padding24.
    expect(
      tester.getSize(find.byType(DshHeadedDialogContent)),
      const Size(440, 224),
    );
    expect(
      tester.getRect(find.byKey(headerKey)),
      const Rect.fromLTWH(0, 0, 440, 62),
    );
    expect(
      tester.getRect(find.byKey(closeKey)),
      const Rect.fromLTWH(398, 22, 28, 28),
    );
    expect(
      tester.getRect(find.byKey(contentKey)),
      const Rect.fromLTWH(0, 0, 440, 144),
    );
    expect(
      tester.getRect(find.byKey(bodyKey)),
      const Rect.fromLTWH(0, 104, 440, 40),
    );
    expect(
      tester.getRect(find.byKey(probeBodyKey)),
      const Rect.fromLTWH(24, 104, 392, 40),
    );
    expect(
      tester.getRect(find.byKey(footerKey)),
      const Rect.fromLTWH(0, 164, 440, 36),
    );
    expect(
      tester.getRect(find.byKey(cancelKey)),
      const Rect.fromLTWH(200, 164, 72, 36),
    );
    expect(
      tester.getRect(find.byKey(confirmKey)),
      const Rect.fromLTWH(280, 164, 136, 36),
    );
    final title = tester.widget<Text>(find.text('Danger'));
    expect(title.style!.fontSize, 16);
    expect(title.style!.height, 1.5);
    expect(title.style!.fontWeight, FontWeight.w500);
    final description = tester.widget<Text>(find.text('One line'));
    expect(description.style!.fontSize, 14);
    expect(description.style!.height, 22 / 14);
    expect(description.style!.fontWeight, FontWeight.w400);
    expect(tester.widget<DshIcon>(find.byType(DshIcon)).size, 14);
    expect(find.byType(DshDialogFrame), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('absent body footer and empty description leave no extra gap', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      dialog(description: '', body: null, footer: false),
    );
    expect(
      tester.getSize(find.byType(DshHeadedDialogContent)),
      const Size(440, 86),
    );
    expect(tester.getSize(find.byKey(contentKey)), const Size(440, 62));
    expect(find.byKey(bodyKey), findsNothing);
    expect(find.byKey(footerKey), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('short scroll content retains its natural height', (
    tester,
  ) async {
    await pumpDialog(tester, dialog(scrollContent: true));
    expect(
      tester.getSize(find.byType(DshHeadedDialogContent)),
      const Size(440, 224),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.viewportDimension, 144);
    expect(position.maxScrollExtent, 0);
  });

  testWidgets('long content scrolls its header while the footer stays fixed', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      dialog(
        description: null,
        scrollContent: true,
        body: Column(
          children: [
            for (var i = 0; i < 50; i++)
              SizedBox(height: 32, child: Text('Warning row $i')),
          ],
        ),
      ),
      maxHeight: 260,
    );
    final footer = tester.getRect(find.byKey(footerKey));
    final headerTop = tester.getTopLeft(find.byKey(headerKey)).dy;
    expect(footer, const Rect.fromLTWH(0, 200, 440, 36));
    expect(tester.getSize(find.byKey(contentKey)), const Size(440, 180));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(find.byKey(contentKey), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(tester.getTopLeft(find.byKey(headerKey)).dy, lessThan(headerTop));
    expect(tester.getRect(find.byKey(footerKey)), footer);
    expect(tester.takeException(), isNull);
  });

  for (final scrolling in [false, true]) {
    testWidgets('height32 clips safely with scrollContent=$scrolling', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        dialog(scrollContent: scrolling, body: const SizedBox(height: 1200)),
        maxHeight: 32,
      );
      expect(
        tester.getSize(find.byType(DshHeadedDialogContent)),
        const Size(440, 32),
      );
      expect(tester.getSize(find.byKey(contentKey)).height, 0);
      expect(tester.getTopLeft(find.byKey(footerKey)).dy, DshModalRecipe.gap);
      expect(tester.takeException(), isNull);
    });
  }

  for (final density in [1.0, 2.625]) {
    testWidgets(
      'overflow gutter is conditional and clears after resize at$density',
      (tester) async {
        tester.view.devicePixelRatio = density;
        tester.view.physicalSize = Size(800 * density, 600 * density);
        addTearDown(tester.view.reset);
        final content = dialog(
          scrollContent: true,
          body: const SizedBox(height: 300),
        );
        await pumpDialog(tester, content, maxHeight: 260);
        // Actual Chromium paint/scrollport: five physical columns at DPR1,
        // thirteen at DPR2.625. Unlike the reader, this gutter is not stable.
        final gutter = density == 1 ? 5.0 : 13 / density;
        expect(tester.getSize(find.byKey(contentKey)).width, 440);
        expect(
          tester.getSize(find.byKey(headerKey)).width,
          closeTo(440 - gutter, 0.001),
        );
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        expect(position.maxScrollExtent, greaterThan(0));
        await pumpDialog(tester, content, maxHeight: 1000);
        expect(tester.getSize(find.byKey(headerKey)).width, 440);
        expect(position.maxScrollExtent, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Close is named and supports Enter Space and pointer activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var closed = 0;
      await pumpDialog(
        tester,
        dialog(closeAutofocus: true, onClose: () => closed++),
      );
      final close = tester.widget<DshButton>(find.byKey(closeKey));
      expect(close.focusNode!.hasPrimaryFocus, isTrue);
      expect(
        DshFocusPresentation.instance.suppressed(close.focusNode!),
        isTrue,
      );
      final data = tester.getSemantics(find.byKey(closeKey)).getSemanticsData();
      expect(data.label, 'Close confirmation');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(find.byKey(DshButton.focusRingKey), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(closed, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(closed, 2);
      expect(
        DshFocusPresentation.instance.suppressed(close.focusNode!),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        DshFocusPresentation.instance.suppressed(close.focusNode!),
        isFalse,
      );
      expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
      await tester.tap(find.byKey(closeKey));
      await tester.pumpAndSettle();
      expect(closed, 3);
      semantics.dispose();
    },
  );

  testWidgets('default Close leaves an explicit body autofocus target alone', (
    tester,
  ) async {
    final target = FocusNode();
    addTearDown(target.dispose);
    await pumpDialog(
      tester,
      dialog(
        body: DshButton(
          focusNode: target,
          autofocus: true,
          onPressed: () {},
          child: const Text('Preferred target'),
        ),
      ),
    );
    expect(target.hasPrimaryFocus, isTrue);
    expect(
      tester.widget<DshButton>(find.byKey(closeKey)).focusNode!.hasFocus,
      isFalse,
    );
  });
}
