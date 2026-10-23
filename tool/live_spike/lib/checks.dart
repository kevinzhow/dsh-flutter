import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Collects pass/fail/blocked results with timings for the live spike report.
class Checks {
  final List<Map<String, Object?>> results = [];
  final Map<String, Object?> facts = {};

  Future<void> check(String name, Future<String?> Function() body) async {
    final sw = Stopwatch()..start();
    try {
      final note = await body();
      results.add({
        'check': name,
        'status': 'pass',
        'ms': sw.elapsedMilliseconds,
        'note': note ?? '',
      });
      stdout.writeln(
        'PASS  $name (${sw.elapsedMilliseconds} ms) ${note ?? ''}',
      );
    } on Object catch (e) {
      results.add({
        'check': name,
        'status': 'fail',
        'ms': sw.elapsedMilliseconds,
        'note': '${e.runtimeType}: $e',
      });
      stdout.writeln(
        'FAIL  $name (${sw.elapsedMilliseconds} ms) ${e.runtimeType}: $e',
      );
    }
  }

  void blocked(String name, String reason) {
    results.add({'check': name, 'status': 'blocked', 'ms': 0, 'note': reason});
    stdout.writeln('BLOCK $name: $reason');
  }

  void writeTo(String path) {
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert({'results': results, 'facts': facts}),
    );
  }
}

class Timeout2 implements Exception {
  Timeout2(this.what, this.after);
  final String what;
  final Duration after;
  @override
  String toString() => 'timed out after ${after.inSeconds}s waiting for $what';
}

/// Poll [test] until it is true or [timeout] passes.
Future<void> until(
  String what,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) throw Timeout2(what, timeout);
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
