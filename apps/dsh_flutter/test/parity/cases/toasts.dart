import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/toast_fixture.dart';

final Map<String, ParityCase> toastCases = {
  'toast.source': ParityCase(
    widgets: ['dsh_ui:DshToast', 'dsh_ui:DshToastHost'],
    framed: false,
    settle: Duration.zero,
    notes: 'Actual canonical Toast with explicit long hold only for stable PNGs. Normal motion is default; reduced motion is separate. Original text and actual CSS-collapsed display text are both retained; mixed oversized runs and complex Unicode remain pending.',
    build: (ctx) => ToastCaptureSurface(
      id: ctx.props['scenarioId'] as String,
      locale: ctx.locale,
      reduced: ctx.props['reducedMotion'] as bool,
      hold: Duration(milliseconds: ctx.props['holdMs'] as int),
    ),
    interact: (tester, ctx) async {
      // Mount the queued root occurrence, then advance by the actual source
      // entry duration. The unchanged capture harness adds its final16ms frame.
      await tester.pump();
      await tester.pump();
      await tester.pump(
        Duration(microseconds: (DshToastRecipe.enterMs * 1000).round()),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    },
    geometryProbe: toastGeometryProbe,
  ),
};

class ToastCaptureSurface extends StatelessWidget {
  const ToastCaptureSurface({
    super.key,
    required this.id,
    required this.locale,
    required this.reduced,
    required this.hold,
  });
  final String id, locale;
  final bool reduced;
  final Duration hold;
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: DshToastHost(
      child: ColoredBox(
        key: const ValueKey('toast-capture-root'),
        color: context.dsh.bgBase,
        child: toastFixtureWidget(id, locale, hold: hold, onDone: () {}),
      ),
    ),
  );
}

Map<String, Object?> toastGeometryProbe(
  WidgetTester t,
  ParityContext ctx,
  RenderBox root,
) {
  Element? one(Finder finder) => finder.evaluate().firstOrNull;
  Map<String, Object?>? box(Element? element) {
    final render = element?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final offset = render.localToGlobal(Offset.zero, ancestor: root);
    final rect = offset & render.size;
    return {
      'bounds': [rect.left, rect.top, rect.width, rect.height],
      'rawFlutterRect': {
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
      },
      'widgetType': element!.widget.runtimeType.toString(),
      'renderType': render.runtimeType.toString(),
    };
  }

  final surface = one(find.byType(DshShadowBox));
  final text = one(find.byType(DshChromeText));
  final icon = one(find.byType(DshIcon));
  final opacity = one(
    find.ancestor(
      of: find.byType(DshShadowBox),
      matching: find.byType(Opacity),
    ),
  );
  final transform = one(
    find.ancestor(
      of: find.byType(DshShadowBox),
      matching: find.byType(Transform),
    ),
  );
  final row = one(
    find.descendant(of: find.byType(DshShadowBox), matching: find.byType(Row)),
  );
  return {
    'schema': 'dsh-toast-geometry/1',
    'coordinateBasis': {
      'space': 'capture-root logical viewport pixels',
      'devicePixelRatio': ctx.density,
      'rounding': 'none',
    },
    'toast': box(surface),
    'text': {
      ...?box(text),
      'text':
          (text?.widget as DshChromeText?)?.semanticsLabel ??
          (text?.widget as DshChromeText?)?.data,
      'originalText':
          (text?.widget as DshChromeText?)?.semanticsLabel ??
          (text?.widget as DshChromeText?)?.data,
      'displayedText': (text?.widget as DshChromeText?)?.data,
      'measurement': 'DshChromeText outer line box; not glyph ink',
    },
    'icon': box(icon),
    'iconPresent': icon != null,
    'rowSeatCount': (row?.widget as Row?)?.children.length,
    'rowSeatCountMeaning': 'native Row children include the explicit generated-gap SizedBox; source CSS flex child count excludes its gap',
    'contentSeatCount': (row?.widget as Row?)?.children
        .where((child) => child is! SizedBox)
        .length,
    'interSeatGaps': [
      for (final child in (row?.widget as Row?)?.children ?? <Widget>[])
        if (child is SizedBox) {'width': child.width, 'height': child.height},
    ],
    'opacity': (opacity?.widget as Opacity?)?.opacity,
    'translateY': (transform?.widget as Transform?)?.transform
        .getTranslation()
        .y,
    'reducedMotion': ctx.props['reducedMotion'],
    'holdMs': ctx.props['holdMs'],
    'entrySourceDurationMs': DshToastRecipe.enterMs,
    'phase': 'steady after actual entry duration plus settled frames; before explicit fixture hold ends',
    'scope': 'read-only actual root portal geometry; no style/crop fitting',
    if (toastScenario(ctx.props['scenarioId'] as String)['pending']
        case final String reason)
      'pending': reason,
  };
}
