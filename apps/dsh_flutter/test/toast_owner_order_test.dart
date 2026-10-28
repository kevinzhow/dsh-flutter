import 'dart:ui' show ImageByteFormat;

import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity/toast_main.dart';

Future<void> _flush(WidgetTester t) async {
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
  await t.pump();
}

Finder _successIcon() => find.byWidgetPredicate(
  (widget) => widget is DshIcon && widget.icon == DshIcons.checkCircle,
);

Future<List<int>> _iconPixels(WidgetTester t, GlobalKey boundaryKey) async {
  final bounds = t.getRect(_successIcon());
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final pixels = (await t.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
    final result = <int>[];
    for (var y = bounds.top.ceil(); y < bounds.bottom.floor(); y++) {
      final start = (y * image.width + bounds.left.ceil()) * 4;
      final end = (y * image.width + bounds.right.floor()) * 4;
      result.addAll(
        data.buffer.asUint8List(data.offsetInBytes + start, end - start),
      );
    }
    image.dispose();
    return result;
  }))!;
  expect(pixels, isNotEmpty);
  return pixels;
}

void main() {
  setUpAll(loadPinnedFontsFromEnvironment);

  for (final owner in ['workspace', 'file']) {
    testWidgets('later upload paints above earlier actual $owner failure', (
      t,
    ) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 720);
      addTearDown(t.view.reset);
      final stateKey = GlobalKey<ToastNativeState>();
      final boundary = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ToastNativeApp(key: stateKey, brightness: Brightness.light),
        ),
      );
      await _flush(t);
      final state = stateKey.currentState!;
      await state.saveUpload(true);
      await _flush(t);
      expect(find.byType(DshToast), findsOneWidget);
      final baseline = await _iconPixels(t, boundary);

      state.clear();
      await _flush(t);
      expect(find.byType(DshToast), findsNothing);
      await t.tap(
        owner == 'workspace'
            ? find.byKey(const ValueKey('open-in-app'))
            : find.bySemanticsLabel('Show file location'),
      );
      await _flush(t);
      expect(find.byType(DshToast), findsOneWidget);
      await state.saveUpload(true);
      await _flush(t);
      expect(find.byType(DshToast), findsNWidgets(2));
      expect(_successIcon(), findsOneWidget);
      // The source appends each new equal-z body portal last. The newest
      // actual Settings notice must paint over the older imperative failure,
      // not merely exist below it in the logical widget tree.
      expect(await _iconPixels(t, boundary), orderedEquals(baseline));
      state.clear();
      await _flush(t);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });
  }
}
