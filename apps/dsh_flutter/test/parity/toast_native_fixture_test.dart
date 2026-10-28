import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show ImageByteFormat;

import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/toast_fixture.dart';
import 'toast_main.dart';

Future<void> flush(WidgetTester t, [Duration elapsed = Duration.zero]) async {
  await t.pump();
  await t.pump();
  await t.pump(elapsed);
  await t.pump();
}

Finder surface() => find.byType(DshShadowBox);
Finder control(String name) => find.byKey(ValueKey('toast-control-$name'));
Finder alert() => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.role == SemanticsRole.alert,
);

void main() {
  setUpAll(loadPinnedFontsFromEnvironment);
  final viewports = [
    (size: const Size(1280, 720), dpr: 1.0),
    (size: const Size(1280, 720), dpr: 2.625),
    (size: const Size(390, 844), dpr: 1.0),
    (size: const Size(390, 844), dpr: 2.625),
  ];
  for (final viewport in viewports) {
    for (final brightness in Brightness.values) {
      testWidgets('Toast native source geometry/input $viewport ${brightness.name}', (
        t,
      ) async {
        t.view.physicalSize = viewport.size * viewport.dpr;
        t.view.devicePixelRatio = viewport.dpr;
        addTearDown(t.view.reset);
        final key = GlobalKey<ToastNativeState>();
        await t.pumpWidget(ToastNativeApp(key: key, brightness: brightness));
        await flush(t);
        final state = key.currentState!;
        final measured = <String, Rect>{};
        measured['underlying'] = t.getRect(
          find.byKey(const ValueKey('toast-underlying')),
        );
        measured['status'] = t.getRect(
          find.byKey(const ValueKey('toast-status')),
        );
        measured['callbackCounter'] = t.getRect(
          find.byKey(const ValueKey('toast-callback-counter')),
        );
        measured['owners'] = t.getRect(
          find.byKey(const ValueKey('toast-owners')),
        );
        measured['noIconControl'] = t.getRect(control('No icon'));
        measured['successControl'] = t.getRect(control('Success'));
        measured['warningControl'] = t.getRect(control('Warning'));
        measured['longControl'] = t.getRect(control('Long'));
        measured['clearControl'] = t.getRect(control('Clear'));
        for (final label in [
          'Lifetime',
          'Same hold',
          'Changed hold',
          'Upload saved',
          'Upload failed',
          'Reduced motion',
          'Toast then preview',
          'Preview then toast',
          'Focus background',
          'Remove file owner',
        ]) {
          measured[label] = t.getRect(control(label));
        }
        measured['workspace'] = t.getRect(
          find.byKey(const ValueKey('open-in-app')),
        );
        measured['file'] = t.getRect(
          find.bySemanticsLabel('Show file location'),
        );
        state.focus.requestFocus();
        await flush(t);
        state.show('no-icon');
        await flush(t, const Duration(milliseconds: 200));
        expect(find.byType(DshToastHost), findsOneWidget);
        expect(find.text(toastFixtureText('no-icon', 'en')), findsOneWidget);
        expect(
          find.byType(DshIcon),
          findsWidgets,
        ); // Real owner icons still exist.
        expect(
          find.descendant(of: surface(), matching: find.byType(DshIcon)),
          findsNothing,
        );
        expect(state.focus.hasPrimaryFocus, isTrue);
        final semantics = t.ensureSemantics();
        expect(
          t.getSemantics(alert()).getSemanticsData().role,
          SemanticsRole.alert,
        );
        expect(
          t
              .getSemantics(alert())
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
        );
        expect(
          t.getSemantics(alert()).getSemanticsData().label,
          toastFixtureText('no-icon', 'en'),
        );
        expect(t.getSemantics(alert()).rect.size, t.getSize(surface()));
        measured['noIcon'] = t.getRect(surface());
        expect(measured['noIcon']!.top, DshToastRecipe.top);
        expect(measured['noIcon']!.center.dx, viewport.size.width / 2);
        final overlap = measured['noIcon']!.intersect(measured['underlying']!);
        expect(overlap.contains(measured['underlying']!.center), isTrue);
        await t.tapAt(measured['underlying']!.center);
        await flush(t);
        expect(state.clicks, 1);
        expect(find.text(toastFixtureText('no-icon', 'en')), findsOneWidget);
        state.show('success');
        await flush(t, const Duration(milliseconds: 200));
        expect(
          t
              .widget<DshIcon>(
                find.descendant(of: surface(), matching: find.byType(DshIcon)),
              )
              .icon,
          DshIcons.checkCircle,
        );
        measured['success'] = t.getRect(surface());
        state.show('warning');
        await flush(t, const Duration(milliseconds: 200));
        expect(
          t
              .widget<DshIcon>(
                find.descendant(of: surface(), matching: find.byType(DshIcon)),
              )
              .icon,
          DshIcons.warning,
        );
        measured['warning'] = t.getRect(surface());
        expect(
          measured['warning']!.width - measured['noIcon']!.width,
          DshIcons.warning.size + DshToastRecipe.gap,
        );
        state.show('long-warning');
        await flush(t, const Duration(milliseconds: 200));
        measured['long'] = t.getRect(surface());
        expect(
          measured['long']!.width,
          (viewport.size.width - DshToastRecipe.viewportInset).clamp(
                0,
                DshToastRecipe.maxContentWidth,
              ) +
              DshToastRecipe.horizontalPadding * 2,
        );
        expect(
          measured['long']!.height,
          greaterThan(measured['warning']!.height),
        );
        expect(measured['long']!.top, DshToastRecipe.top);
        final shadowBottom = sourceShadowBottom(t);
        final shadowLayers = t.widget<DshShadowBox>(surface()).shadows;
        expect(measured['callbackCounter']!.top, greaterThan(shadowBottom));
        expect(
          measured['callbackCounter']!.bottom,
          lessThanOrEqualTo(viewport.size.height),
        );
        expect(
          find.bySemanticsLabel('Lifecycle callback count: 0'),
          findsOneWidget,
        );
        expect(
          find.text(toastFixtureText('long-warning', 'en')),
          findsOneWidget,
        );
        state.clear();
        await flush(t);
        expect(surface(), findsNothing);
        semantics.dispose();
        // Preparation measurement only; root will bind this to the final manifest.
        if (Platform.environment['WHALEE_TOAST_NATIVE_GEOMETRY'] == '1') {
          debugPrint(
            'TOAST_NATIVE_GEOMETRY ${jsonEncode({
              'viewport': [viewport.size.width, viewport.size.height],
              'dpr': viewport.dpr,
              'theme': brightness.name,
              'pinnedFonts': Platform.environment['WHALEE_PIN_FONTS']?.isNotEmpty == true,
              'callbackProbe': {
                'semanticsLabel': 'Lifecycle callback count: 0',
                'sourceLongShadowBandBottom': shadowBottom,
                'shadowBandRule': 'offsetY + spread + 3 * (CSS blurRadius / 2)',
                'shadowLayers': [
                  for (final shadow in shadowLayers) {'dx': shadow.offset.dx, 'dy': shadow.offset.dy, 'blurRadius': shadow.blurRadius, 'spreadRadius': shadow.spreadRadius},
                ],
              },
              'rects': {
                for (final e in measured.entries) e.key: [e.value.left, e.value.top, e.value.right, e.value.bottom],
              },
            })}',
          );
        }
        await t.pumpWidget(const SizedBox());
        await flush(t);
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final viewport in viewports) {
    for (final brightness in Brightness.values) {
      testWidgets('Toast callback probe $viewport ${brightness.name}', (
        t,
      ) async {
        t.view.physicalSize = viewport.size * viewport.dpr;
        t.view.devicePixelRatio = viewport.dpr;
        addTearDown(t.view.reset);
        final key = GlobalKey<ToastNativeState>();
        final raster = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: raster,
            child: ToastNativeApp(key: key, brightness: brightness),
          ),
        );
        await flush(t);
        final state = key.currentState!;
        final counter = find.byKey(const ValueKey('toast-callback-counter'));
        expect(counter, findsOneWidget);
        state.show('long-warning');
        await flush(t, const Duration(milliseconds: 200));
        final bounds = t.getRect(counter);
        expect(bounds.top, greaterThan(sourceShadowBottom(t)));
        state.lifecycle();
        await flush(t, const Duration(milliseconds: 300));
        state.changedHold();
        await flush(t);
        final unchanged = await callbackCounterPixels(
          t,
          raster,
          bounds,
          viewport.dpr,
        );
        // Cross the original4s completion boundary while source CSS is fading
        // on its original mount timeline. The changed callback is due later.
        await t.pump(const Duration(milliseconds: 4100));
        await flush(t);
        expect(state.done, 0);
        expect(t.widget<Text>(counter).data, 'Lifecycle callback count: 0');
        expect(
          await callbackCounterPixels(t, raster, bounds, viewport.dpr),
          orderedEquals(unchanged),
        );
        await t.pump(const Duration(milliseconds: 1200));
        await flush(t);
        expect(state.done, 1);
        expect(t.widget<Text>(counter).data, 'Lifecycle callback count: 1');
        expect(
          await callbackCounterPixels(t, raster, bounds, viewport.dpr),
          isNot(orderedEquals(unchanged)),
        );
        expect(surface(), findsNothing);
        await t.pumpWidget(const SizedBox());
        await flush(t);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'default lifetime and same-hold text update keep original deadline',
    (t) async {
      final key = GlobalKey<ToastNativeState>();
      await t.pumpWidget(
        ToastNativeApp(key: key, brightness: Brightness.light),
      );
      await flush(t);
      final state = key.currentState!;
      state.lifecycle();
      await flush(t);
      await t.pump(const Duration(milliseconds: 1000));
      state.sameHold();
      await flush(t);
      expect(find.text('Lifecycle updated'), findsOneWidget);
      await t.pump(
        dshToastHold + dshToastFade - const Duration(milliseconds: 1100),
      );
      await flush(t);
      expect(state.done, 0);
      expect(find.text('Lifecycle updated'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 200));
      await flush(t);
      expect(state.done, 1);
      expect(surface(), findsNothing);
      await t.pumpWidget(const SizedBox());
      await flush(t);
    },
  );

  testWidgets('reduced motion reaches root Toast without cancelling lifetime', (
    t,
  ) async {
    final key = GlobalKey<ToastNativeState>();
    await t.pumpWidget(ToastNativeApp(key: key, brightness: Brightness.light));
    await flush(t);
    final state = key.currentState!;
    state.show('no-icon');
    await flush(t);
    Finder opacity() =>
        find.ancestor(of: surface(), matching: find.byType(Opacity)).first;
    expect(t.widget<Opacity>(opacity()).opacity, 1);
    state.reduced = false;
    state.show('warning');
    await flush(t);
    expect(t.widget<Opacity>(opacity()).opacity, 0);
    await t.pump(
      Duration(microseconds: (DshToastRecipe.enterMs * 500).round()),
    );
    expect(t.widget<Opacity>(opacity()).opacity, greaterThan(0));
    expect(t.widget<Opacity>(opacity()).opacity, lessThan(1));
    state.reduced = true;
    state.lifecycle();
    await flush(t);
    expect(t.widget<Opacity>(opacity()).opacity, 1);
    await t.pump(dshToastHold + dshToastFade);
    await flush(t);
    expect(state.done, 1);
    expect(surface(), findsNothing);
    await t.pumpWidget(const SizedBox());
    await flush(t);
  });

  testWidgets(
    'changed hold restarts completion while occurrence identity stays',
    (t) async {
      final key = GlobalKey<ToastNativeState>();
      await t.pumpWidget(
        ToastNativeApp(key: key, brightness: Brightness.light),
      );
      await flush(t);
      final state = key.currentState!;
      state.lifecycle();
      await flush(t);
      final original = t.widget<DshToast>(find.byType(DshToast)).key;
      await t.pump(const Duration(milliseconds: 1000));
      state.changedHold();
      await flush(t);
      expect(t.widget<DshToast>(find.byType(DshToast)).key, original);
      await t.pump(dshToastHold + dshToastFade);
      await flush(t);
      expect(
        state.done,
        0,
      ); // Original deadline has passed; changed one has not.
      await t.pump(dshToastFade);
      await flush(t);
      expect(state.done, 1);
      expect(surface(), findsNothing);
      await t.pumpWidget(const SizedBox());
      await flush(t);
    },
  );

  testWidgets(
    'replacement cancels old lifecycle; clear cancels pending completion',
    (t) async {
      final key = GlobalKey<ToastNativeState>();
      await t.pumpWidget(
        ToastNativeApp(key: key, brightness: Brightness.light),
      );
      await flush(t);
      final state = key.currentState!;
      state.lifecycle();
      await flush(t);
      await t.pump(const Duration(seconds: 1));
      state.show('warning');
      await flush(t, const Duration(milliseconds: 200));
      await t.pump(dshToastHold + dshToastFade);
      await flush(t);
      expect(state.done, 0);
      expect(find.text(toastFixtureText('warning', 'en')), findsOneWidget);
      state.clear();
      await flush(t);
      await t.pump(const Duration(seconds: 61));
      await flush(t);
      expect(state.done, 0);
      expect(surface(), findsNothing);
      await t.pumpWidget(const SizedBox());
      await flush(t);
    },
  );

  testWidgets(
    'three actual owners preserve mapping and independent replacement',
    (t) async {
      final key = GlobalKey<ToastNativeState>();
      await t.pumpWidget(
        ToastNativeApp(key: key, brightness: Brightness.light),
      );
      await flush(t);
      final state = key.currentState!;
      await t.tap(find.byKey(const ValueKey('open-in-app')));
      await flush(t, const Duration(milliseconds: 200));
      expect(state.openClient.attempts, 1);
      expect(find.byType(DshToast), findsOneWidget);
      expect(t.widget<DshToast>(find.byType(DshToast)).icon, isA<DshIcon>());
      final first = t.widget<DshToast>(find.byType(DshToast));
      await t.tap(find.byKey(const ValueKey('open-in-app')));
      await flush(t, const Duration(milliseconds: 200));
      expect(state.openClient.attempts, 2);
      expect(find.byType(DshToast), findsOneWidget);
      expect(t.widget<DshToast>(find.byType(DshToast)).key, isNot(first.key));
      first.onDone();
      await flush(t);
      expect(find.byType(DshToast), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Show file location'));
      await flush(t, const Duration(milliseconds: 200));
      expect(state.fileRequests, 1);
      expect(find.byType(DshToast), findsNWidgets(2));
      await state.saveUpload(true);
      await flush(t, const Duration(milliseconds: 200));
      expect(find.byType(DshToast), findsNWidgets(3));
      expect(
        t
            .widgetList<DshToast>(find.byType(DshToast))
            .where((w) => w.tone == DshToastTone.success),
        hasLength(1),
      );
      await state.saveUpload(false);
      await flush(t, const Duration(milliseconds: 200));
      expect(find.byType(DshToast), findsNWidgets(3));
      final failed = t
          .widgetList<DshToast>(find.byType(DshToast))
          .where((w) => w.key is ValueKey)
          .single;
      expect(failed.tone, isNull);
      expect(failed.icon, isNull);
      state.removeFileOwner();
      await flush(t);
      expect(
        find.byType(DshToast),
        findsNWidgets(2),
      ); // File owner only removed.
      state.clear();
      await flush(t);
      expect(surface(), findsNothing);
      await t.pumpWidget(const SizedBox());
      await flush(t);
      expect(t.takeException(), isNull);
    },
  );

  for (final toastFirst in [true, false]) {
    testWidgets(
      'actual root Toast remains above actual lightbox, toast first $toastFirst',
      (t) async {
        final key = GlobalKey<ToastNativeState>();
        final raster = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: raster,
            child: ToastNativeApp(key: key, brightness: Brightness.light),
          ),
        );
        await flush(t);
        key.currentState!.show('warning');
        await flush(t, const Duration(milliseconds: 220));
        final baseline = await toastCorePixels(t, raster);
        key.currentState!.lightbox(toastFirst);
        await flush(t, const Duration(milliseconds: 220));
        expect(find.byType(DshLightbox), findsOneWidget);
        expect(surface(), findsOneWidget);
        // Portal logical ancestry is unrelated to paint priority. Compare
        // actual opaque Toast-core text/material pixels to the same Toast
        // alone; transparent corners intentionally retain their backing.
        expect(await toastCorePixels(t, raster), orderedEquals(baseline));
        key.currentState!.clear();
        await flush(t, const Duration(milliseconds: 220));
        await t.pumpWidget(const SizedBox());
        await flush(t);
        expect(t.takeException(), isNull);
      },
    );
  }
}

Future<List<int>> toastCorePixels(WidgetTester t, GlobalKey key) async {
  final bounds = t.getRect(surface());
  final core = Rect.fromCenter(
    center: bounds.center,
    width: bounds.width - bounds.height,
    height: bounds.height / 2,
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final pixels = (await t.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
    final result = <int>[];
    for (var y = core.top.ceil(); y < core.bottom.floor(); y++) {
      final start = (y * image.width + core.left.ceil()) * 4;
      final end = (y * image.width + core.right.floor()) * 4;
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

// Source CSS radius/2 is sigma; use a conservative3sigma paint band for all
// source-generated shadow layers. This is a fixture collision guard, never a
// production shadow alteration or image-comparison tolerance.
double sourceShadowBottom(WidgetTester t) {
  final shadows = t.widget<DshShadowBox>(surface()).shadows;
  final outset = shadows
      .map((s) => s.offset.dy + s.spreadRadius + 3 * s.blurRadius / 2)
      .reduce((a, b) => a > b ? a : b);
  return t.getRect(surface()).bottom + outset;
}

Future<List<int>> callbackCounterPixels(
  WidgetTester t,
  GlobalKey key,
  Rect bounds,
  double density,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: density);
    final data = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
    final result = <int>[];
    for (
      var y = (bounds.top * density).floor();
      y < (bounds.bottom * density).ceil();
      y++
    ) {
      final start = (y * image.width + (bounds.left * density).floor()) * 4;
      final end = (y * image.width + (bounds.right * density).ceil()) * 4;
      result.addAll(
        data.buffer.asUint8List(data.offsetInBytes + start, end - start),
      );
    }
    image.dispose();
    return result;
  }))!;
}
