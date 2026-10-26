import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshPixelModel, dshPixelModel;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case.dart';
import 'fonts.dart';
import 'interactions.dart';
import 'probes.dart';
import 'theme.dart';

/// The pixel rectangle enclosing [rect], in device pixels.
///
/// The native React provider copies this same enclosing rectangle from its full
/// viewport raster; locator screenshots can truncate a fractional device row.
/// With an emulated density (`--reference emulated`) Blink lays out in CSS pixels, so the
/// crop is the enclosing CSS-pixel box (floor / ceil in CSS px, then scaled): a card at y = 296.5 starts on the same
/// device row on both sides. With a native density (the default) layout units are device pixels and the crop is the
/// enclosing device-pixel box (a 420 CSS px wide element at 2.625x is 1102.5 device px, captured as 1103).
Rect enclosingPixelRect(Rect rect, double density) {
  if (dshPixelModel == DshPixelModel.native) {
    // Match the browser's float32 DOMRect noise tolerance; 1e-4 device px
    // remains well below Blink's smallest genuine 1/64 px layout fraction.
    double lo(double v) => (v * density + 1e-4).floorToDouble();
    double hi(double v) => (v * density - 1e-4).ceilToDouble();
    return Rect.fromLTRB(
      lo(rect.left),
      lo(rect.top),
      hi(rect.right),
      hi(rect.bottom),
    );
  }
  return Rect.fromLTRB(
    rect.left.floorToDouble() * density,
    rect.top.floorToDouble() * density,
    rect.right.ceilToDouble() * density,
    rect.bottom.ceilToDouble() * density,
  );
}

/// Pumps one manifest entry at its viewport and density and writes PNG + metadata in the provider
/// output contract (`<outputDir>/<captureKey>.png|.metadata.json`).
///
/// [entry] is `{key, case, variant}` from the run plan (the same JSON the React provider reads).
Future<Map<String, dynamic>> captureParityCase(
  WidgetTester t, {
  required Map<String, dynamic> entry,
  required ParityCase mapping,
  required Map<String, dynamic> fixtures,
  required Directory outputDir,
  required Map<String, dynamic> runInfo,
  required List<ParityFontFace> fonts,
  bool framed = true,
}) async {
  final caseJson = entry['case'] as Map<String, dynamic>;
  final variant = entry['variant'] as Map<String, dynamic>;
  final key = entry['key'] as String;
  final themeName = caseJson['theme'] as String;
  final theme = resolveParityTheme(themeName);
  final ctx = ParityContext(
    caseJson: caseJson,
    variant: variant,
    theme: theme,
    fixtures: fixtures,
  );
  final size = Size(ctx.width, ctx.height);
  final requestedPhysical = size * ctx.density;
  // Native Chromium lays out its viewport on enclosing physical pixels, even
  // though the screenshot API rounds the requested raster size to nearest.
  // At 390x421 / 2.625x, CSS 100vh is 421.3333, while the PNG is 1105px tall.
  t.view.physicalSize = dshPixelModel == DshPixelModel.native
      ? Size(
          requestedPhysical.width.ceilToDouble(),
          requestedPhysical.height.ceilToDouble(),
        )
      : requestedPhysical;
  t.view.devicePixelRatio = ctx.density;
  addTearDown(t.view.reset);

  final rootKey = GlobalKey(debugLabel: 'parity-root');
  final localeTag = (caseJson['locale'] as String).split('-');
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(
        localeTag.first,
        localeTag.length > 1 ? localeTag[1] : null,
      ),
      theme: ThemeData(
        brightness: theme.brightness,
        extensions: [theme],
        // Playwright screenshots hide the caret; hide Flutter's the same way.
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0x00000000),
        ),
      ),
      builder: (context, child) => MediaQuery(
        // Playwright runs with animations disabled and reduced motion; the product's
        // reduced-motion contract is the Flutter equivalent.
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: RepaintBoundary(key: rootKey, child: child),
      ),
      home: Builder(
        builder: (context) {
          final content = mapping.build(ctx);
          return framed ? ctx.frame(content) : content;
        },
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 50));
  final interactions = ParityInteractions(t);
  await interactions.apply((variant['interactions'] as List?) ?? const []);
  if (mapping.interact != null) await mapping.interact!(t, ctx);
  await t.pump(mapping.settle);
  await t.pump(const Duration(milliseconds: 16));
  final error = t.takeException();
  if (error != null) {
    throw StateError('case ${ctx.id} threw while rendering: $error');
  }

  final rootBox =
      rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  void hideCarets(RenderObject node) {
    if (node is RenderEditable) node.cursorColor = const Color(0x00000000);
    node.visitChildren(hideCarets);
  }

  hideCarets(rootBox);
  await t.pump();

  final capture = (caseJson['capture'] as Map?) ?? const {};
  final cropMode = (capture['crop'] as String?) ?? 'element';
  final targetKey = capture['flutterKey'] == null
      ? ParityContext.targetKey
      : ValueKey<String>(capture['flutterKey'] as String);
  Rect rect = Offset.zero & size;
  BuildContext? targetContext;
  if (cropMode == 'element') {
    final found = find.byKey(targetKey).evaluate().firstOrNull;
    if (found == null) {
      throw StateError('case ${ctx.id}: capture target $targetKey missing');
    }
    targetContext = found;
    final box = found.findRenderObject()! as RenderBox;
    rect = (box.localToGlobal(Offset.zero, ancestor: rootBox) & box.size)
        .intersect(Offset.zero & size);
  }
  final d = ctx.density;
  final pixelRect = cropMode == 'element'
      ? enclosingPixelRect(rect, d)
      : Rect.fromLTWH(
          0,
          0,
          (size.width * d).roundToDouble(),
          (size.height * d).roundToDouble(),
        );

  Color? framePixel;
  final png = await t.runAsync(() async {
    final full = await rootBox.toImage(pixelRatio: d);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & pixelRect.size,
      Paint()..color = Colors.white,
    );
    canvas.drawImageRect(
      full,
      pixelRect,
      Offset.zero & pixelRect.size,
      Paint()..filterQuality = FilterQuality.none,
    );
    final cropped = await recorder.endRecording().toImage(
      pixelRect.width.toInt(),
      pixelRect.height.toInt(),
    );
    // Check the frame's own corner, not the selected element's corner.
    // A menu/card crop may correctly start with a shadow or coloured fill.
    final raw = await full.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw != null) {
      framePixel = Color.fromARGB(
        raw.getUint8(3),
        raw.getUint8(0),
        raw.getUint8(1),
        raw.getUint8(2),
      );
    }
    final bytes = await cropped.toByteData(format: ui.ImageByteFormat.png);
    full.dispose();
    cropped.dispose();
    return bytes!.buffer.asUint8List();
  });

  // Theme self-test: the capture must show the theme the case asked for.
  final live = Theme.of(rootKey.currentContext!).extension<DshThemeData>();
  verifyCapturedTheme(
    requested: themeName,
    inTree: live,
    expected: theme,
    framePixel: framed ? framePixel : null,
  );
  await interactions.release();

  final roundedRect = {
    'x': rect.left,
    'y': rect.top,
    'width': rect.width,
    'height': rect.height,
  };
  final metadata = <String, dynamic>{
    'provider': 'flutter',
    'providerType': 'flutter-widget-test',
    'source': 'dsh-flutter',
    'caseId': ctx.id,
    'variantId': variant['id'],
    'captureKey': key,
    'theme': themeName,
    'themeResolved': {
      'pack': live?.packId,
      'brightness': live?.brightness.name,
    },
    'locale': ctx.locale,
    'image': 'visual-testing-results/flutter/$key.png',
    'viewport': ctx.viewport,
    'selector': capture['selector'],
    'crop': {
      'mode': cropMode,
      'rect': roundedRect,
      'pixelRect': {
        'x': pixelRect.left,
        'y': pixelRect.top,
        'width': pixelRect.width,
        'height': pixelRect.height,
      },
    },
    'flutter': {
      'widgets': mapping.widgets,
      'layoutViewport': {
        'width': t.view.physicalSize.width / ctx.density,
        'height': t.view.physicalSize.height / ctx.density,
      },
      if (mapping.notes.isNotEmpty) 'notes': mapping.notes,
      'targetPlatform': 'linux',
      'density': 'pointer',
      'renderer': 'flutter_test host raster (Skia/Impeller software), not a device screenshot',
      'animationPolicy':
          'reduced-motion at rest; matches Playwright animations: disabled',
      ...runInfo,
    },
    'fonts': {
      'manifest': 'tool/parity-fonts/manifest.json',
      'faces': [for (final f in fonts) f.toJson()],
      'registration':
          'FontLoader per family; flutter_test has no OS font fallback',
    },
    'typography': typographyProbes(targetContext ?? rootKey.currentContext),
    'styleTokens': styleTokenProbes(targetContext ?? rootKey.currentContext),
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
  };
  await t.runAsync(() async {
    await File('${outputDir.path}/$key.png').writeAsBytes(png!);
    await File('${outputDir.path}/$key.metadata.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
    );
  });
  return metadata;
}
