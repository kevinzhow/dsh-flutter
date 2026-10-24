// Frame-timing probe for scrolling measurements; not the product entry.
//   flutter run|build --profile -t lib/perf_main.dart
// Every second with frames it logs one line
//   PERF n=<frames> build=<p50>/<p90>/<p99>/<max> raster=<...> total=<...> over16=<n> over33=<n>
//        hb=/hr=/ht= histograms (build, raster, total) over <8,<16.7,<25,<33.4,<50,<100,>=100 ms
// (microseconds, from `FrameTiming`), which `adb logcat -s flutter` shows.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'main.dart' as app;

String _pct(List<int> v) {
  if (v.isEmpty) return '-';
  final s = List<int>.of(v)..sort();
  int at(double p) => s[((s.length - 1) * p).round()];
  return '${at(.5)}/${at(.9)}/${at(.99)}/${s.last}';
}

/// Counts per bucket: <8, <16.7, <25, <33.4, <50, <100, >=100 ms.
String _hist(List<int> v) {
  const edges = [8000, 16700, 25000, 33400, 50000, 100000];
  final c = List<int>.filled(edges.length + 1, 0);
  for (final x in v) {
    var i = 0;
    while (i < edges.length && x >= edges[i]) {
      i++;
    }
    c[i]++;
  }
  return c.join(',');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final build = <int>[], raster = <int>[], total = <int>[];
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
      total.add(t.totalSpan.inMicroseconds);
    }
  });
  Timer.periodic(const Duration(seconds: 1), (_) {
    if (total.isEmpty) return;
    debugPrint(
      'PERF n=${total.length} build=${_pct(build)} raster=${_pct(raster)} '
      'total=${_pct(total)} over16=${total.where((v) => v > 16700).length} '
      'over33=${total.where((v) => v > 33400).length} '
      'hb=${_hist(build)} hr=${_hist(raster)} ht=${_hist(total)}',
    );
    build.clear();
    raster.clear();
    total.clear();
  });
  await app.main();
}
