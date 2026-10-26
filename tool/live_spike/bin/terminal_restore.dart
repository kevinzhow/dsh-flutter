// Real isolated Host terminal identity restoration; synthetic workspace only.
// No model is called and no launch token or terminal output is published.
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated.dart';
import 'package:dsh_live_spike/live_host.dart';
import 'package:dsh_models/dsh_models.dart';

class CountingCaller implements RemoteCaller {
  CountingCaller(this.delegate);
  final RemoteCaller delegate;
  int creates = 0;
  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) {
    if (namespace == 'terminal' && method == 'create') creates++;
    return delegate.call(namespace, method, args);
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('workspace and output directory required');
  }
  final workspace = Directory(args[0]).absolute..createSync(recursive: true);
  final out = Directory(args[1])..createSync(recursive: true);
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  LiveHost? host;
  DshConnection? connection;
  ClientTerminals? first, second;
  TerminalHost? terminalHost;
  String? sessionId, terminalId;
  try {
    host = await LiveHost.start(port: port, workspace: workspace.path);
    final token = await host.token.timeout(const Duration(seconds: 30));
    await host.waitListening();
    final connected = connection = DshConnection(origin: host.origin)
      ..start(token);
    await connected.untilConnected().timeout(const Duration(seconds: 30));
    final session = await SessionRemote(connected.caller)
        .create(SessionCreateRequest(cwd: workspace.path));
    sessionId = session.sessionId;
    final caller = CountingCaller(connected.caller);
    final terminal = terminalHost = TerminalHost(
      caller: caller,
      attach: (s, id) => TerminalHost.attachOn(connected, s, id),
      retain: (s, id) => TerminalHost.retainOn(connected, s, id),
      generations: connected.generations,
      currentGeneration: () => connected.generation,
    );
    first = ClientTerminals(host: terminal);
    final created = first.view(sessionId, 'synthetic-tab');
    await created.refresh().timeout(const Duration(seconds: 30));
    terminalId = created.snapshot.info?.id;
    if (terminalId == null || caller.creates != 1) {
      throw StateError('Initial synthetic terminal was not created');
    }
    await first.dispose();
    first = null;
    second = ClientTerminals(
      host: terminal,
      newId: () => throw StateError('Restoration must not allocate a terminal'),
    );
    final restored = second.view(
      sessionId,
      'restored-tab',
      terminalId: terminalId,
    );
    await restored.refresh().timeout(const Duration(seconds: 30));
    if (restored.snapshot.info?.id != terminalId || caller.creates != 1) {
      throw StateError('Existing terminal identity was not retained');
    }
    final missing = second.view(
      sessionId,
      'missing-tab',
      terminalId: 'synthetic-missing',
    );
    await missing.refresh().timeout(const Duration(seconds: 30));
    await missing.refresh().timeout(const Duration(seconds: 30));
    if (missing.snapshot.issue != TerminalViewIssue.missingTerminal ||
        caller.creates != 1) {
      throw StateError('Missing terminal attempted replacement work');
    }
    await File('${out.path}/receipt.json').writeAsString(
      '${jsonEncode({'syntheticOnly': true, 'realDshHost': true, 'modelInvoked': false, 'initialCreates': caller.creates, 'existingIdentityRestored': true, 'missingIdentityRetryCreatesNothing': true})}\n',
    );
    stdout.writeln('Real Host terminal restoration: 3 checks passed');
  } catch (e) {
    stderr.writeln(
      'Synthetic terminal restoration failed: ${e.runtimeType}${e is RemoteException ? ' (${e.code})' : ''}',
    );
    exitCode = 1;
  } finally {
    await first?.dispose();
    await second?.dispose();
    if (sessionId != null && terminalId != null) {
      try {
        await terminalHost?.remote.close(sessionId, terminalId);
      } on Object {
        // Stopping the owned Host below also reaps its synthetic process.
      }
    }
    await connection?.stop();
    await host?.stop();
  }
}
