// Usage (from tool/live_spike): dart run bin/live_app.dart [--port 18741] [--ws DIR] [--out FILE] [--test FILE] [--keep-ws]
// Runs the app-layer live integration test (apps/dsh_flutter/test/live) against a dsh host this harness starts:
// a separate `dsh web` on 127.0.0.1 sharing ~/.dsh (never Kevin's instance on 18686/8686). The launch URL (with its
// token) goes to a mode-600 file the test reads and is never printed; the host is stopped by the PID started here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_live_spike/live_host.dart';

String arg(List<String> a, String name, String fallback) {
  final i = a.indexOf('--$name');
  return i >= 0 && i + 1 < a.length ? a[i + 1] : fallback;
}

Future<void> main(List<String> args) async {
  final port = int.parse(arg(args, 'port', '18741'));
  if (port == 18686 || port == 8686) {
    stderr.writeln('refusing to use port $port');
    exit(2);
  }
  final wsArg = arg(args, 'ws', '${Directory.systemTemp.path}/whalee-live/ws');
  final scratch = '${Directory.systemTemp.path}/whalee-live';
  final out = arg(args, 'out', '$scratch/live-app-result.json');
  final launchFile = arg(args, 'launch-file', '$scratch/live-launch-url');
  final testFile = arg(args, 'test', 'test/live/live_app_test.dart');
  final logFile = arg(args, 'log', '$scratch/live-app.log');
  final flutter =
      Platform.environment['FLUTTER_BIN'] ??
      '${Platform.environment['HOME']}/flutter-sdks/versions/3.47.6/bin/flutter';
  Directory(wsArg).createSync(recursive: true);
  final ws = Directory(wsArg).resolveSymbolicLinksSync();
  Directory(File(launchFile).parent.path).createSync(recursive: true);
  Directory(File(logFile).parent.path).createSync(recursive: true);
  Directory(File(out).parent.path).createSync(recursive: true);
  final appDir = Directory.fromUri(
    Platform.script.resolve('../../../apps/dsh_flutter'),
  ).path;

  LiveHost? host;
  var status = 0;
  try {
    final sw = Stopwatch()..start();
    host = await LiveHost.start(port: port, workspace: ws);
    stdout.writeln('started dsh pid ${host.pid} on 127.0.0.1:$port');
    final token = await host.token;
    File(launchFile).createSync();
    Process.runSync('chmod', ['600', launchFile]);
    File(launchFile).writeAsStringSync('http://127.0.0.1:$port/?token=$token');
    await host.waitListening();
    stdout.writeln('host listening after ${sw.elapsedMilliseconds}ms');

    final test = await Process.start(
      'nice',
      [
        '-n',
        '15',
        flutter,
        'test',
        '--tags',
        'live',
        '-r',
        'expanded',
        testFile,
      ],
      workingDirectory: appDir,
      environment: {
        'DSH_LIVE_LAUNCH_FILE': launchFile,
        'DSH_LIVE_RESULT': out,
        'DSH_LIVE_WORKSPACE': ws,
      },
    );
    final log = File(logFile).openWrite();
    String redact(String s) =>
        s.replaceAll(RegExp(r'token=[^\s&"]+'), 'token=<redacted>');
    final done = Future.wait([
      test.stdout.transform(utf8.decoder).forEach((c) => log.write(redact(c))),
      test.stderr.transform(utf8.decoder).forEach((c) => log.write(redact(c))),
    ]);
    status = await test.exitCode;
    await done;
    await log.close();
    stdout.writeln('flutter test exited $status');
    if (File(out).existsSync()) {
      final rows = jsonDecode(File(out).readAsStringSync()) as List;
      for (final r in rows) {
        final m = r as Map;
        stdout.writeln(
          '${(m['state'] as String).padRight(5)} ${(m['ms'] as num).toString().padLeft(7)}ms  ${m['check']}  ${m['detail']}',
        );
      }
    }
  } on Object catch (e, st) {
    status = 1;
    stdout.writeln('ABORT ${e.runtimeType}: $e\n$st');
    if (host != null) stdout.writeln('stderr tail: ${host.redactedStderrTail}');
  } finally {
    if (host != null) {
      await host.stop();
      stdout.writeln('stopped dsh pid ${host.pid}');
    }
    final f = File(launchFile);
    if (f.existsSync()) f.deleteSync();
  }
  exit(status);
}
