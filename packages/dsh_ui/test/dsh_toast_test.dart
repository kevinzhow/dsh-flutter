import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, SemanticsRole;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(
  Widget child, {
  bool reduced = false,
  Brightness brightness = Brightness.light,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  theme: ThemeData(
    brightness: brightness,
    extensions: [resolveTheme(officialPack, ThemeSettings(), brightness)],
  ),
  builder: (context, body) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: DshToastHost(child: body!),
  ),
  home: Scaffold(body: child),
);

Future<void> present(
  WidgetTester t,
  Widget child, {
  bool reduced = true,
}) async {
  await t.pumpWidget(app(child, reduced: reduced));
  await t.pump();
  await t.pump();
}

List<SemanticsNode> platformAlerts(WidgetTester t) {
  final result = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().role == SemanticsRole.alert) result.add(node);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
  return result;
}

void main() {
  testWidgets('owner-mounted icon retains arbitrary live inherited context', (
    t,
  ) async {
    final value = ValueNotifier('owner');
    var done = 0;
    await present(
      t,
      ValueListenableBuilder(
        valueListenable: value,
        builder: (context, label, _) => _ToastContext(
          value: label,
          child: DshToast(
            text: 'Context',
            icon: const _ContextIcon(),
            onDone: () => done++,
          ),
        ),
      ),
    );
    expect(find.text('icon:owner'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    value.value = 'updated';
    await t.pump();
    expect(find.text('icon:owner'), findsNothing);
    expect(find.text('icon:updated'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1999));
    expect(done, 0);
    await t.pump(const Duration(milliseconds: 1));
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
    value.dispose();
  });

  testWidgets('owner context disposal cancels its completion and portal', (
    t,
  ) async {
    var done = 0;
    await present(
      t,
      _ToastContext(
        value: 'owner',
        child: DshToast(
          text: 'Remove owner',
          icon: const _ContextIcon(),
          onDone: () => done++,
        ),
      ),
    );
    expect(find.text('icon:owner'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpWidget(app(const SizedBox(), reduced: true));
    expect(find.text('Remove owner'), findsNothing);
    expect(find.text('icon:owner'), findsNothing);
    await t.pump(const Duration(seconds: 3));
    expect(done, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('covered owner route keeps portal animation and lifetime', (
    t,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    var done = 0;
    await t.pumpWidget(
      app(
        _ToastContext(
          value: 'covered',
          child: DshToast(
            text: 'Covered owner',
            icon: const _ContextIcon(),
            onDone: () => done++,
          ),
        ),
        navigatorKey: nav,
      ),
    );
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
    Opacity opacity() => t.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Covered owner'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacity().opacity, closeTo(Curves.easeOut.transform(.5), 1e-6));
    nav.currentState!.push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const Scaffold(body: Text('Covering route')),
        transitionDuration: Duration.zero,
      ),
    );
    await t.pump();
    await t.pump();
    final owner = t.element(find.byType(DshToast, skipOffstage: false));
    expect(TickerMode.valuesOf(owner).enabled, isFalse);
    await t.pump(const Duration(milliseconds: 3420));
    expect(find.text('icon:covered', skipOffstage: false), findsOneWidget);
    final ownerOpacity = find
        .ancestor(
          of: find.text('Covered owner', skipOffstage: false),
          matching: find.byType(Opacity, skipOffstage: false),
        )
        .first;
    expect(
      t.widget<Opacity>(ownerOpacity).opacity,
      closeTo(1 - Curves.ease.transform(.5), 1e-6),
    );
    await t.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    expect(find.text('Covered owner', skipOffstage: false), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('success overrides icon; custom artwork is not forced to16', (
    t,
  ) async {
    await present(
      t,
      DshToast(
        text: 'Saved',
        icon: const SizedBox(key: ValueKey('custom'), width: 23, height: 19),
        tone: DshToastTone.success,
        onDone: () {},
      ),
    );
    expect(find.byKey(const ValueKey('custom')), findsNothing);
    expect(t.widget<DshIcon>(find.byType(DshIcon)).icon, DshIcons.checkCircle);
    await t.pumpWidget(const SizedBox());
    await present(
      t,
      DshToast(
        text: 'Warn',
        icon: const SizedBox(key: ValueKey('custom'), width: 23, height: 19),
        onDone: () {},
      ),
    );
    expect(t.getSize(find.byKey(const ValueKey('custom'))), const Size(23, 19));
    expect(DshIcons.checkCircle.shapes, hasLength(2));
    expect(DshIcons.checkCircle.shapes.every((shape) => shape.fill), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'entry ease-out and delayed ease fade keep independent timelines',
    (t) async {
      await present(t, DshToast(text: 'Timing', onDone: () {}), reduced: false);
      await t.pump(const Duration(milliseconds: 80));
      final opacity = find
          .descendant(
            of: find.byType(DshToastHost),
            matching: find.byType(Opacity),
          )
          .last;
      expect(
        t.widget<Opacity>(opacity).opacity,
        closeTo(Curves.easeOut.transform(.5), 1e-6),
      );
      await t.pump(const Duration(milliseconds: 3420));
      expect(
        t.widget<Opacity>(opacity).opacity,
        closeTo(1 - Curves.ease.transform(.5), 1e-6),
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reduced entry stays still and opaque; the delayed fade remains',
    (t) async {
      await present(t, DshToast(text: 'Reduced', onDone: () {}));
      final opacity = find
          .descendant(
            of: find.byType(DshToastHost),
            matching: find.byType(Opacity),
          )
          .last;
      expect(t.widget<Opacity>(opacity).opacity, 1);
      final transform = find
          .ancestor(
            of: find.byType(DshShadowBox),
            matching: find.byType(Transform),
          )
          .first;
      expect(t.widget<Transform>(transform).transform.getTranslation().y, 0);
      await t.pump(const Duration(milliseconds: 3500));
      expect(
        t.widget<Opacity>(opacity).opacity,
        closeTo(1 - Curves.ease.transform(.5), 1e-6),
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'zero hold keeps simultaneous source entry and fade composition',
    (t) async {
      var done = 0;
      await present(
        t,
        DshToast(text: 'Zero hold', hold: Duration.zero, onDone: () => done++),
        reduced: false,
      );
      await t.pump(const Duration(milliseconds: 80));
      final opacity = find
          .descendant(
            of: find.byType(DshToastHost),
            matching: find.byType(Opacity),
          )
          .last;
      expect(
        t.widget<Opacity>(opacity).opacity,
        closeTo(
          Curves.easeOut.transform(.5) * (1 - Curves.ease.transform(.08)),
          1e-6,
        ),
      );
      await t.pump(const Duration(milliseconds: 920));
      expect(done, 1);
      expect(find.text('Zero hold'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same hold rerender keeps deadline and uses latest completion once',
    (t) async {
      var oldDone = 0, newDone = 0;
      await present(
        t,
        DshToast(
          key: const ValueKey('same'),
          text: 'One',
          onDone: () => oldDone++,
        ),
      );
      await t.pump(const Duration(seconds: 2));
      await t.pumpWidget(
        app(
          DshToast(
            key: const ValueKey('same'),
            text: 'Two',
            onDone: () => newDone++,
          ),
          reduced: true,
        ),
      );
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 1999));
      expect(newDone, 0);
      await t.pump(const Duration(milliseconds: 1));
      expect((oldDone, newDone), (0, 1));
      await t.pump(const Duration(seconds: 2));
      expect(newDone, 1);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'changed hold restarts only completion timer and unmount cancels',
    (t) async {
      var done = 0;
      await present(
        t,
        DshToast(
          key: const ValueKey('same'),
          text: 'One',
          onDone: () => done++,
        ),
      );
      await t.pump(const Duration(seconds: 2));
      await t.pumpWidget(
        app(
          DshToast(
            key: const ValueKey('same'),
            text: 'Two',
            hold: const Duration(milliseconds: 500),
            onDone: () => done++,
          ),
          reduced: true,
        ),
      );
      await t.pump();
      await t.pump();
      expect(
        find.text('Two'),
        findsNothing,
        reason: 'CSS delay uses the original mount timeline while the completion timer restarts',
      );
      await t.pump(const Duration(milliseconds: 1499));
      expect(done, 0);
      await t.pump(const Duration(milliseconds: 1));
      expect(done, 1);
      await t.pumpWidget(const SizedBox());
      await present(t, DshToast(text: 'Unmount', onDone: () => done++));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
      expect(done, 1);
    },
  );

  testWidgets('hold change cancels expiry before deferred root-paint rebuild', (
    t,
  ) async {
    var done = 0;
    await present(
      t,
      DshToast(
        key: const ValueKey('deadline'),
        text: 'First',
        onDone: () => done++,
      ),
    );
    await t.pump(const Duration(milliseconds: 3999));
    await t.pumpWidget(
      app(
        DshToast(
          key: const ValueKey('deadline'),
          text: 'Changed',
          hold: const Duration(seconds: 5),
          onDone: () => done++,
        ),
        reduced: true,
      ),
    );
    // The root presentation has only been queued for update at this point.
    await t.pump(const Duration(milliseconds: 1));
    expect(done, 0);
    await t.pump(const Duration(milliseconds: 5999));
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'portal escapes transforms, preserves focus and passes pointer input',
    (t) async {
      final semantics = t.ensureSemantics();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final visible = ValueNotifier(false);
      addTearDown(visible.dispose);
      var taps = 0;
      await present(
        t,
        Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => taps++,
                behavior: HitTestBehavior.opaque,
                child: Focus(focusNode: focus, child: const SizedBox.expand()),
              ),
            ),
            Transform.translate(
              offset: const Offset(140, 170),
              child: SizedBox(
                width: 100,
                height: 100,
                child: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, show, _) => show
                      ? DshToast(text: 'Portal', onDone: () {})
                      : const SizedBox(),
                ),
              ),
            ),
          ],
        ),
      );
      focus.requestFocus();
      await t.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      visible.value = true;
      await t.pump();
      await t.pump();
      await t.pump();
      expect(
        focus.hasPrimaryFocus,
        isTrue,
        reason: 'showing the alert does not take the existing focus',
      );
      final rect = t.getRect(find.byType(DshShadowBox));
      expect(rect.top, 40);
      expect(
        rect.center.dx,
        t.view.physicalSize.width / t.view.devicePixelRatio / 2,
      );
      await t.tapAt(rect.center);
      expect(taps, 1);
      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        platformAlerts(t).single.getSemanticsData().role,
        SemanticsRole.alert,
      );
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'per-show identity survives rebuild; stale completion keeps replacement',
    (t) async {
      final toasts = DshToasts();
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(const SizedBox(), navigatorKey: nav));
      toasts.showOn(nav.currentState!.overlay!, 'Same');
      await t.pump();
      await t.pump();
      await t.pump();
      final old = t.widget<DshToast>(find.byType(DshToast));
      await t.pump(const Duration(seconds: 2));
      await t.pumpWidget(
        app(const SizedBox(), navigatorKey: nav, brightness: Brightness.dark),
      );
      await t.pump();
      await t.pump();
      expect(t.widget<DshToast>(find.byType(DshToast)).key, old.key);
      toasts.showOn(nav.currentState!.overlay!, 'Same');
      await t.pump();
      await t.pump();
      await t.pump();
      final replacement = t.widget<DshToast>(find.byType(DshToast));
      expect(replacement.key, isNot(old.key));
      old.onDone();
      await t.pump();
      expect(find.text('Same'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await t.pump();
      await t.pump();
      expect(find.text('Same'), findsNothing);
      toasts.dismiss();
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final toastFirst in [true, false]) {
    testWidgets('Toast is above actual lightbox in show order $toastFirst', (
      t,
    ) async {
      final nav = GlobalKey<NavigatorState>(), toasts = DshToasts();
      final raster = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: raster,
          child: app(const SizedBox(), navigatorKey: nav, reduced: true),
        ),
      );
      void showToast() =>
          toasts.showOn(nav.currentState!.overlay!, 'Above preview');
      void showLightbox() {
        showDshLightbox(
          nav.currentContext!,
          images: [DshLightboxImage(label: 'Synthetic', bytes: Uint8List(0))],
          labels: const DshLightboxLabels(
            dialog: 'Preview',
            close: 'Close',
            loadFailed: 'Failed',
            position: _position,
          ),
        );
      }

      showToast();
      await t.pump();
      await t.pump();
      await t.pump();
      final baseline = await _toastCorePixels(t, raster);
      if (toastFirst) {
        showLightbox();
      } else {
        toasts.dismiss();
        await t.pump();
        showLightbox();
        await t.pump();
        showToast();
      }
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Above preview'), findsOneWidget);
      expect(find.byType(DshLightbox), findsOneWidget);
      // Compare actual painted text/material pixels, not logical element order:
      // an owner-side portal remains logically below the lightbox's route.
      expect(await _toastCorePixels(t, raster), orderedEquals(baseline));
      toasts.dismiss();
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'independent owners replace and dismiss only their own occurrence',
    (t) async {
      final nav = GlobalKey<NavigatorState>();
      final first = DshToasts(), second = DshToasts();
      await t.pumpWidget(app(const SizedBox(), navigatorKey: nav));
      first.showOn(nav.currentState!.overlay!, 'First owner');
      second.showOn(nav.currentState!.overlay!, 'Second owner');
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.text('First owner'), findsOneWidget);
      expect(find.text('Second owner'), findsOneWidget);
      first.showOn(nav.currentState!.overlay!, 'First replacement');
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.text('First owner'), findsNothing);
      expect(find.text('Second owner'), findsOneWidget);
      first.dismiss();
      await t.pump();
      await t.pump();
      expect(find.text('First replacement'), findsNothing);
      expect(find.text('Second owner'), findsOneWidget);
      second.dismiss();
      await t.pumpWidget(const SizedBox());
    },
  );
}

String _position(int index, int total) => '$index / $total';

class _ToastContext extends InheritedWidget {
  const _ToastContext({required this.value, required super.child});
  final String value;
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ToastContext>()?.value ??
      'missing';
  @override
  bool updateShouldNotify(_ToastContext oldWidget) => value != oldWidget.value;
}

class _ContextIcon extends StatelessWidget {
  const _ContextIcon();
  @override
  Widget build(BuildContext context) =>
      Text('icon:${_ToastContext.of(context)}');
}

Future<List<int>> _toastCorePixels(WidgetTester t, GlobalKey raster) async {
  final bounds = t.getRect(find.byType(DshShadowBox));
  // The center rectangle is inside the superellipse, so changing the surface
  // behind its transparent outer corners cannot falsify the paint-order proof.
  final core = Rect.fromCenter(
    center: bounds.center,
    width: bounds.width - bounds.height,
    height: bounds.height / 2,
  );
  final boundary =
      raster.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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
