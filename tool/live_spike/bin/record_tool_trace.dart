// Usage (from tool/live_spike): dart run bin/record_tool_trace.dart [--port 18731] [--ws DIR] [--raw FILE] [--token-file FILE] [--prompt TEXT]
// Records ONE raw behaviour-vector trace of a live turn that calls a tool (streamed tool-call deltas, tool/call,
// tool/result, final answer). Starts its own `dsh web` on 127.0.0.1 (never the user's instance), keeps the launch
// token in a mode-600 file and never prints it, and stops the host by the PID it started. The raw trace holds real
// text and goes outside the repository; scrub it with tool/vectors/scrub_trace.py.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_live_spike/checks.dart';
import 'package:dsh_live_spike/live_host.dart';
import 'package:dsh_live_spike/recorder.dart';
import 'package:dsh_models/dsh_models.dart';

String arg(List<String> a, String name, String fallback) {
  final i = a.indexOf('--$name');
  return i >= 0 && i + 1 < a.length ? a[i + 1] : fallback;
}

bool hasEvent(Session s, String type, {num after = -1}) => s
    .eventSource
    .window
    .entries
    .any((e) => !e.transient && e.type == type && e.seq > after);

num lastSeq(Session s) => s.eventSource.window.entries
    .where((e) => !e.transient)
    .fold<num>(-1, (a, e) => e.seq > a ? e.seq : a);

Future<void> main(List<String> args) async {
  final port = int.parse(arg(args, 'port', '18731'));
  if (port == 18686 || port == 8686) {
    stderr.writeln('refusing to use port $port');
    exit(2);
  }
  final wsArg = arg(args, 'ws', '${Directory.systemTemp.path}/whalee-live/ws');
  final rawFile = arg(
    args,
    'raw',
    '${Directory.systemTemp.path}/whalee-live/raw/tool_trace.json',
  );
  final tokenFile = arg(args, 'token-file', '/tmp/cindy/dsh-p1a/launch-token');
  final prompt = arg(
    args,
    'prompt',
    'Run the shell command `echo hello` and tell me its output in one short sentence.',
  );
  Directory(wsArg).createSync(recursive: true);
  final ws = Directory(wsArg).resolveSymbolicLinksSync();
  Directory(File(rawFile).parent.path).createSync(recursive: true);
  Directory(File(tokenFile).parent.path).createSync(recursive: true);

  LiveHost? host;
  DshConnection? conn;
  var exitStatus = 0;
  try {
    host = await LiveHost.start(port: port, workspace: ws);
    stdout.writeln('started dsh pid ${host.pid} on 127.0.0.1:$port');
    final token = await host.token;
    File(tokenFile).createSync();
    Process.runSync('chmod', ['600', tokenFile]);
    File(tokenFile).writeAsStringSync(token);
    await host.waitListening();

    conn = DshConnection(origin: host.origin);
    conn.start(token);
    await conn.untilConnected();
    final transport = DshSessionTransport(conn);
    final hostVersion = await readHostVersion(conn.caller);
    stdout.writeln('paired, host version $hostVersion');

    // Answer an approval if the preset asks for one, so the prompt completes.
    var approvals = 0;
    final approvalSub = conn.hostEvents.listen((e) {
      if (e is WaterfallEvent && e.event == 'approval/request') {
        approvals++;
        unawaited(conn!.answer(e, const WaterfallResult('allowed-once')));
      }
    });

    final manager = SessionManager(transport)..start();
    await manager.refreshList();
    final created = await manager.create(cwd: ws);
    final sessionId = created.sessionId;
    final preset =
        (created.projections.get('permissions') as Map?)?['currentValue'];
    stdout.writeln('session created, permission preset: $preset');
    await manager.refreshList();

    final rec = RecordingTransport(transport);
    final s2 = Session(
      sessionId,
      rec,
      pageOptions: const {
        'maxMessages': 2,
        'turnWindow': {'minMessages': 1, 'minTurns': 1},
      },
    );
    rec.action('open');
    await s2.open();
    final base = lastSeq(s2);
    await s2.prompt(prompt);
    await until(
      'turn/end',
      () => hasEvent(s2, 'turn/end', after: base),
      timeout: const Duration(seconds: 180),
    );
    var pages = 0;
    while (s2.snapshot.value.hasMore && pages < 6) {
      rec.action('loadOlder');
      await s2.loadOlder();
      pages++;
    }
    final types = <String, int>{};
    for (final e in s2.eventSource.window.entries) {
      if (e.transient) continue;
      types[e.type] = (types[e.type] ?? 0) + 1;
    }
    await s2.dispose();
    File(rawFile).createSync();
    Process.runSync('chmod', ['600', rawFile]);
    File(rawFile).writeAsStringSync(
      jsonEncode({
        'format': 'dsh-session-trace/1',
        'hostVersion': hostVersion,
        'openOptions': s2.pageOptions,
        'steps': rec.steps,
      }),
    );
    stdout.writeln(
      'recorded ${rec.steps.length} steps, loadOlder pages=$pages, approvals answered=$approvals, event types $types',
    );
    stdout.writeln('raw trace: $rawFile');
    await approvalSub.cancel();
  } on Object catch (e, st) {
    exitStatus = 1;
    stdout.writeln('ABORT ${e.runtimeType}: $e\n$st');
    if (host != null) stdout.writeln('stderr tail: ${host.redactedStderrTail}');
  } finally {
    await conn?.stop();
    if (host != null) {
      await host.stop();
      stdout.writeln('stopped dsh pid ${host.pid}');
    }
  }
  exit(exitStatus);
}
