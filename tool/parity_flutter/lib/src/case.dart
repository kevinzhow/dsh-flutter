import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshSurface;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout.dart';

/// Builds the real Flutter widget tree for one case (the counterpart of a React host `kinds` entry).
typedef ParityBuilder = Widget Function(ParityContext ctx);

/// Optional extra step after the manifest's own `interactions` (for state a case cannot describe).
typedef ParityInteraction = Future<void> Function(
  WidgetTester tester,
  ParityContext ctx,
);

/// Optional read-only measurement of the tree represented by the PNG. Bounds
/// may be expressed relative to [captureRoot]; do not pump, send input or mutate
/// the widget tree from this synchronous callback.
typedef ParityGeometryProbe = Map<String, Object?> Function(
  WidgetTester tester,
  ParityContext ctx,
  RenderBox captureRoot,
);

/// One mapped renderer: the real widget path the app uses for what the React host shows for the
/// same `kind` (or exact case id; an id wins over a kind).
class ParityCase {
  /// Creates a mapping.
  const ParityCase({
    required this.widgets,
    required this.build,
    this.interact,
    this.geometryProbe,
    this.notes = '',
    this.settle = const Duration(milliseconds: 400),
    this.framed = true,
  });

  /// Product widgets exercised, for the coverage report (`dsh_ui:DshButton`).
  final List<String> widgets;

  /// Builds the widgets for the case.
  final ParityBuilder build;

  /// Optional extra interaction.
  final ParityInteraction? interact;

  /// Optional JSON-compatible component measurements, captured before releasing
  /// held input. Absent callbacks add no field to the provider metadata.
  final ParityGeometryProbe? geometryProbe;

  /// Free text recorded in the metadata.
  final String notes;

  /// Time pumped after the last interaction.
  final Duration settle;

  /// Whether the harness wraps the built widget in the parity frame (viewport-sized, padded, filled
  /// with `--dsw-alias-bg-base`). Full screens (`screens.*` cases, `capture.crop: viewport`) set false.
  final bool framed;
}

/// Why a case has no Flutter capture. All of these count as NOT COVERED.
enum ParityGap {
  /// Harness work not done yet; a Flutter implementation may exist.
  harnessTodo,

  /// The Flutter app has no implementation of this surface or component yet.
  noFlutterSurface,

  /// Only a real device can show this state honestly.
  deviceOnly,

  /// The React baseline does not show the component, so a match would be meaningless.
  invalidBaseline,
}

/// A kind or case id with no Flutter capture, and why.
class ParityUncovered {
  /// Creates an entry.
  const ParityUncovered(this.gap, this.reason);

  /// Category.
  final ParityGap gap;

  /// Human readable reason.
  final String reason;
}

/// Everything a builder may read: the manifest case and variant, the official theme in the requested
/// mode, and the layout helpers that mirror the React host's frame.
class ParityContext {
  /// Creates a context.
  ParityContext({
    required this.caseJson,
    required this.variant,
    required this.theme,
    required this.fixtures,
  });

  /// The manifest case.
  final Map<String, dynamic> caseJson;

  /// The variant being captured.
  final Map<String, dynamic> variant;

  /// The resolved dsh theme (official pack, requested mode).
  final DshThemeData theme;

  /// `fixtures/*.json` of the suite keyed by file stem.
  final Map<String, dynamic> fixtures;

  /// Key of the capture target (the parity frame).
  static const ValueKey<String> targetKey = ValueKey<String>('parity-target');

  /// Case id.
  String get id => caseJson['id'] as String;

  /// Renderer key.
  String get kind => caseJson['kind'] as String;

  /// `light` or `dark`.
  String get themeName => caseJson['theme'] as String;

  /// Locale tag.
  String get locale => caseJson['locale'] as String;

  /// The variant's props (same JSON the React host receives).
  Map<String, dynamic> get props =>
      Map<String, dynamic>.from((variant['props'] as Map?) ?? const {});

  /// Viewport map `{width, height, density}`.
  Map<String, dynamic> get viewport =>
      Map<String, dynamic>.from(caseJson['viewport'] as Map);

  /// CSS-px width of the page.
  double get width => (viewport['width'] as num).toDouble();

  /// CSS-px height of the page.
  double get height => (viewport['height'] as num).toDouble();

  /// Device pixel ratio.
  double get density => (viewport['density'] as num).toDouble();

  /// The `layout` prop as a [ParityLayout].
  ParityLayout get layout =>
      ParityLayout.fromJson(props['layout'] as Map<String, dynamic>?);

  /// The parity frame: the same box the React host renders around every case (viewport-sized,
  /// 16px padding, `--dsw-alias-bg-base` fill, clipped). Cropping defaults to it.
  Widget frame(Widget child) => Align(
    alignment: Alignment.topLeft,
    child: KeyedSubtree(
      key: targetKey,
      child: ClipRect(
        child: Container(
          width: width,
          height: height,
          color: theme.bgBase,
          padding: const EdgeInsets.all(16),
          alignment: Alignment.topLeft,
          // The frame is the page: translucent fills inside it composite onto
          // `bg-base`, which dsh widgets learn through DshSurface.
          child: DshSurface(color: theme.bgBase, child: child),
        ),
      ),
    ),
  );
}
