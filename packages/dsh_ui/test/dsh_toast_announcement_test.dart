import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

List<SemanticsNode> platformAlerts(
  WidgetTester t,
  DebugSemanticsDumpOrder order,
) {
  final result = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    if (node.getSemanticsData().role == SemanticsRole.alert) result.add(node);
    for (final child in node.debugListChildrenInOrder(order)) {
      walk(child);
    }
  }

  walk(t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
  return result;
}

void expectAlert(WidgetTester t, String? label) {
  for (final order in DebugSemanticsDumpOrder.values) {
    final nodes = platformAlerts(t, order);
    expect(nodes, hasLength(label == null ? 0 : 1));
    if (label != null) {
      expect(nodes.single.getSemanticsData().label, label);
      expect(
        nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
        false,
      );
      expect(nodes.single.rect.size, t.getSize(find.byType(DshShadowBox)));
      Rect? globalRect;
      void locate(SemanticsNode node, Matrix4 parent) {
        final transform = parent.clone();
        if (node.transform case final matrix?) transform.multiply(matrix);
        if (node.id == nodes.single.id) {
          globalRect = MatrixUtils.transformRect(transform, node.rect);
        }
        for (final child in node.debugListChildrenInOrder(order)) {
          locate(child, transform);
        }
      }

      locate(
        t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
        Matrix4.identity(),
      );
      // RenderView's root semantics transform includes physical DPR. The
      // painter finder reports logical pixels, so compare in that basis.
      final dpr = t.view.devicePixelRatio;
      expect(
        Rect.fromLTRB(
          globalRect!.left / dpr,
          globalRect!.top / dpr,
          globalRect!.right / dpr,
          globalRect!.bottom / dpr,
        ),
        t.getRect(find.byType(DshShadowBox)),
      );
    }
  }
}

Future<void> flush(WidgetTester t, [Duration elapsed = Duration.zero]) async {
  await t.pump();
  await t.pump();
  await t.pump(elapsed);
  await t.pump();
}

class _OwnerValue extends InheritedWidget {
  const _OwnerValue({required this.value, required super.child});
  final String value;
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OwnerValue>()!.value;
  @override
  bool updateShouldNotify(_OwnerValue oldWidget) => value != oldWidget.value;
}

class _OwnerIcon extends StatelessWidget {
  const _OwnerIcon();
  @override
  Widget build(BuildContext context) => Text('icon:${_OwnerValue.of(context)}');
}

void main() {
  for (final lightboxFirst in [false, true]) {
    testWidgets(
      'actual lightbox exports one alert, lightboxFirst=$lightboxFirst',
      (t) async {
        final semantics = t.ensureSemantics();
        final navigator = GlobalKey<NavigatorState>();
        final show = ValueNotifier(!lightboxFirst);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: ThemeData(
              extensions: [
                resolveTheme(officialPack, ThemeSettings(), Brightness.light),
              ],
            ),
            builder: (_, child) => DshToastHost(child: child!),
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: show,
                builder: (_, visible, _) => visible
                    ? DshToast(text: 'Above actual preview', onDone: () {})
                    : const SizedBox(),
              ),
            ),
          ),
        );
        await flush(t, const Duration(milliseconds: 200));
        unawaited(
          showDshLightbox(
            navigator.currentContext!,
            images: [DshLightboxImage(label: 'Synthetic', bytes: Uint8List(0))],
            labels: DshLightboxLabels(
              dialog: 'Preview',
              close: 'Close preview',
              loadFailed: 'Cannot load image',
              position: (index, total) => '$index / $total',
            ),
          ),
        );
        await flush(t, const Duration(milliseconds: 200));
        if (lightboxFirst) {
          show.value = true;
          await flush(t, const Duration(milliseconds: 200));
        }
        expect(find.byType(DshLightbox), findsOneWidget);
        expectAlert(t, 'Above actual preview');
        show.value = false;
        await flush(t);
        expectAlert(t, null);
        expect(find.byType(DshLightbox), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        show.dispose();
        semantics.dispose();
      },
    );
  }

  testWidgets('source opacity-zero entry still exports its actual alert', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      dshTestApp(
        DshToastHost(
          child: DshToast(text: 'Initial', onDone: () {}),
        ),
      ),
    );
    await flush(t);
    expect(
      t
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byType(DshShadowBox),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      0,
    );
    expectAlert(t, 'Initial');
    await t.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('changed hold removes faded AX before its later completion', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final hold = ValueNotifier<Duration?>(null);
    var done = 0;
    await t.pumpWidget(
      dshTestApp(
        DshToastHost(
          child: ValueListenableBuilder(
            valueListenable: hold,
            builder: (_, value, _) => DshToast(
              text: 'Changed hold',
              hold: value,
              onDone: () => done++,
            ),
          ),
        ),
      ),
    );
    await flush(t, const Duration(milliseconds: 1160));
    expectAlert(t, 'Changed hold');
    hold.value = Duration.zero;
    await flush(t);
    expectAlert(t, null);
    expect(done, 0);
    await flush(t, const Duration(milliseconds: 999));
    expectAlert(t, null);
    expect(done, 0);
    await flush(t, const Duration(milliseconds: 1));
    expect(done, 1);
    expectAlert(t, null);
    await t.pumpWidget(const SizedBox());
    hold.dispose();
    semantics.dispose();
  });

  testWidgets(
    'equal text stays independently owned; replacement and clear fence stale reports',
    (t) async {
      final semantics = t.ensureSemantics();
      final owners = ValueNotifier(2);
      final generation = ValueNotifier(0);
      await t.pumpWidget(
        dshTestApp(
          DshToastHost(
            child: ValueListenableBuilder(
              valueListenable: owners,
              builder: (_, count, _) => Column(
                children: [
                  if (count > 0)
                    ValueListenableBuilder(
                      valueListenable: generation,
                      builder: (_, value, _) => DshToast(
                        key: ValueKey(value),
                        text: 'Same',
                        onDone: () {},
                      ),
                    ),
                  if (count > 1) DshToast(text: 'Same', onDone: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await flush(t);
      final initial = platformAlerts(t, DebugSemanticsDumpOrder.traversalOrder);
      expect(initial, hasLength(2));
      expect(initial.map((node) => node.label), everyElement('Same'));
      final originalIds = initial.map((node) => node.id).toSet();
      generation.value++;
      await flush(t);
      final replacements = platformAlerts(
        t,
        DebugSemanticsDumpOrder.traversalOrder,
      );
      expect(replacements, hasLength(2));
      expect(
        replacements.map((node) => node.id).toSet().intersection(originalIds),
        hasLength(1),
      );
      owners.value = 1;
      await flush(t);
      expectAlert(t, 'Same');
      owners.value = 0;
      await flush(t);
      expectAlert(t, null);
      await flush(t, const Duration(seconds: 5));
      expectAlert(t, null);
      await t.pumpWidget(const SizedBox());
      owners.dispose();
      generation.dispose();
      semantics.dispose();
    },
  );

  testWidgets(
    'clipped logical owner has exactly one root alert with raw text and live provider',
    (t) async {
      final semantics = t.ensureSemantics();
      final value = ValueNotifier('original');
      var done = 0;
      await t.pumpWidget(
        dshTestApp(
          DshToastHost(
            child: Stack(
              children: [
                Positioned(
                  top: 200,
                  left: 0,
                  right: 0,
                  height: 80,
                  child: SingleChildScrollView(
                    child: ValueListenableBuilder(
                      valueListenable: value,
                      builder: (_, label, _) => Directionality(
                        textDirection: label == 'updated'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: _OwnerValue(
                          value: label,
                          child: DshToast(
                            text: '  $label\tfull text\nkept  ',
                            icon: const _OwnerIcon(),
                            onDone: () => done++,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await flush(t, const Duration(milliseconds: 200));
      expectAlert(t, '  original\tfull text\nkept  ');
      expect(find.text('icon:original'), findsOneWidget);
      final first = platformAlerts(
        t,
        DebugSemanticsDumpOrder.traversalOrder,
      ).single.id;
      await t.pump(const Duration(milliseconds: 1800));
      value.value = 'updated';
      await flush(t);
      expectAlert(t, '  updated\tfull text\nkept  ');
      expect(
        platformAlerts(t, DebugSemanticsDumpOrder.traversalOrder).single.id,
        first,
      );
      expect(find.text('icon:updated'), findsOneWidget);
      expect(
        platformAlerts(
          t,
          DebugSemanticsDumpOrder.traversalOrder,
        ).single.getSemanticsData().textDirection,
        TextDirection.rtl,
      );
      await flush(t, const Duration(milliseconds: 1999));
      expect(done, 0);
      await flush(t, const Duration(milliseconds: 1));
      expect(done, 1);
      expectAlert(t, null);
      await t.pumpWidget(const SizedBox());
      value.dispose();
      semantics.dispose();
    },
  );

  testWidgets(
    'unmount before portal reporting creates no phantom announcement',
    (t) async {
      final semantics = t.ensureSemantics();
      var done = 0;
      final visible = ValueNotifier(true);
      await t.pumpWidget(
        dshTestApp(
          DshToastHost(
            child: ValueListenableBuilder(
              valueListenable: visible,
              builder: (_, show, _) => show
                  ? DshToast(text: 'Owned', onDone: () => done++)
                  : const SizedBox(),
            ),
          ),
        ),
      );
      visible.value = false;
      await flush(t);
      expectAlert(t, null);
      await flush(t, const Duration(seconds: 5));
      expect(done, 0);
      expectAlert(t, null);
      await t.pumpWidget(const SizedBox());
      visible.dispose();
      semantics.dispose();
    },
  );

  testWidgets(
    'root announcement survives a modal route with the actual painter bounds',
    (t) async {
      final semantics = t.ensureSemantics();
      final navigator = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(
            extensions: [
              resolveTheme(officialPack, ThemeSettings(), Brightness.light),
            ],
          ),
          builder: (_, child) => DshToastHost(child: child!),
          home: Scaffold(
            body: DshToast(text: 'Above modal', onDone: () {}),
          ),
        ),
      );
      await flush(t, const Duration(milliseconds: 200));
      expectAlert(t, 'Above modal');
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: 'Modal',
            child: SizedBox.expand(),
          ),
        ),
      );
      await flush(t);
      expectAlert(t, 'Above modal');
      await flush(t, const Duration(milliseconds: 3800));
      expectAlert(t, null);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'no-host consumer retains local alert, context and ordinary expiry',
    (t) async {
      final semantics = t.ensureSemantics();
      var done = 0;
      await t.pumpWidget(
        dshTestApp(
          _OwnerValue(
            value: 'local',
            child: DshToast(
              text: 'Local fallback',
              icon: const _OwnerIcon(),
              onDone: () => done++,
            ),
          ),
        ),
      );
      await flush(t, const Duration(milliseconds: 200));
      // Host-free consumers keep the original local portal semantics. The
      // SDK's logical-anchor traversal limitation is not certified here.
      final local = t
          .getSemantics(
            find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.role == SemanticsRole.alert,
            ),
          )
          .getSemanticsData();
      expect(local.role, SemanticsRole.alert);
      expect(local.label, 'Local fallback');
      expect(find.text('icon:local'), findsOneWidget);
      await flush(t, const Duration(milliseconds: 3800));
      expect(done, 1);
      expectAlert(t, null);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
}
