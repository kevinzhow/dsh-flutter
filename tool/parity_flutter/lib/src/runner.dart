import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capture.dart';
import 'case.dart';
import 'fonts.dart';

/// Body of a capture entry point (`test/parity/parity_capture_test.dart`).
///
/// Driven by `tool/parity`: `PARITY_PLAN` names the run plan JSON written for both providers
///
///     { resultsDir, fontsManifest?, fixturesDirs: [...], runInfo: {...},
///       entries: [{key, case, variant}],      // what to capture
///       coverage: [{id, kind}] }              // every case of the manifest, for the coverage map
///
/// A plain `flutter test` (no `PARITY_PLAN`) skips the capture. [cases] and [uncovered] are keyed by
/// manifest `kind` or exact case id (an id wins).
void runParityCapture({
  required Map<String, ParityCase> cases,
  required Map<String, ParityUncovered> uncovered,
}) {
  final planPath = Platform.environment['PARITY_PLAN'];
  if (planPath == null) {
    test(
      'parity capture (set PARITY_PLAN, see tool/parity)',
      () {},
      skip: true,
    );
    return;
  }
  final plan =
      json.decode(File(planPath).readAsStringSync()) as Map<String, dynamic>;
  final resultsDir = plan['resultsDir'] as String;
  final outputDir = Directory('$resultsDir/flutter')
    ..createSync(recursive: true);
  final fixtures = <String, dynamic>{};
  for (final dir
      in (plan['fixturesDirs'] as List? ?? const []).cast<String>()) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final file in d.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.json')) {
        fixtures[name.substring(0, name.length - 5)] = json.decode(
          file.readAsStringSync(),
        );
      }
    }
  }
  final runInfo = (plan['runInfo'] as Map?)?.cast<String, dynamic>() ?? {};
  final entries = (plan['entries'] as List).cast<Map<String, dynamic>>();
  var fonts = <ParityFontFace>[];

  ParityCase? mappingFor(Map<String, dynamic> caseJson) =>
      cases[caseJson['id']] ?? cases[caseJson['kind']];

  setUpAll(() async {
    fonts = await loadParityFonts(
      (plan['fontsManifest'] as String?) ?? findParityFontsManifest(),
    );
  });

  tearDownAll(() {
    final coverage = <String, dynamic>{};
    for (final c in (plan['coverage'] as List).cast<Map<String, dynamic>>()) {
      final id = c['id'] as String;
      final kind = c['kind'] as String;
      final mapped = cases[id] ?? cases[kind];
      final gap = uncovered[id] ?? uncovered[kind];
      coverage[id] = switch ((mapped, gap)) {
        (final ParityCase m?, _) => {
          'status': 'mapped',
          'widgets': m.widgets,
          if (m.notes.isNotEmpty) 'notes': m.notes,
        },
        (_, final ParityUncovered u?) => {
          'status': u.gap.name,
          'reason': u.reason,
        },
        _ => {
          'status': ParityGap.harnessTodo.name,
          'reason': 'No Flutter builder mapped for kind "$kind" yet.',
        },
      };
    }
    final label = Platform.environment['PARITY_PACKAGE'] ?? 'dsh_parity';
    File('$resultsDir/flutter-case-map.$label.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(coverage)}\n',
    );
  });

  for (final entry in entries) {
    final caseJson = entry['case'] as Map<String, dynamic>;
    final mapping = mappingFor(caseJson);
    if (mapping == null) continue;
    testWidgets('parity ${entry['key']}', (t) async {
      await captureParityCase(
        t,
        entry: entry,
        mapping: mapping,
        fixtures: fixtures,
        outputDir: outputDir,
        runInfo: runInfo,
        fonts: fonts,
        framed: mapping.framed,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
}
