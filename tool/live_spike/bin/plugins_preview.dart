// Synthetic Office-only live check. No model is invoked and no credential or
// runtime log is written into its portable result receipt.
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated.dart';
import 'package:dsh_live_spike/live_host.dart';
import 'package:dsh_models/dsh_models.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('workspace and result directory required');
  }
  final workspace = Directory(args[0]).absolute.path;
  final out = Directory(args[1])..createSync(recursive: true);
  final portProbe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = portProbe.port;
  await portProbe.close();
  LiveHost? host;
  DshConnection? connection;
  OfficePreviewService? service;
  final checks = <String, bool>{};
  try {
    host = await LiveHost.start(port: port, workspace: workspace);
    final token = await host.token.timeout(const Duration(seconds: 30));
    await host.waitListening(timeout: const Duration(seconds: 30));
    connection = DshConnection(origin: host.origin)..start(token);
    await connection.untilConnected().timeout(const Duration(seconds: 30));
    final remote = SessionRemote(connection.caller);
    final session = await remote.create(SessionCreateRequest(cwd: workspace));
    final remotes = HostRemotes(
      caller: connection.caller,
      hostEvents: connection.hostEvents,
      generations: connection.generations,
      currentGeneration: () => connection!.generation,
    );
    service = OfficePreviewService(
      remotes: remotes,
      files: DshWorkspaceFiles(connection),
    );
    final result = await service
        .read(session.sessionId, 'synthetic.docx')
        .timeout(const Duration(seconds: 60));
    if (result.data.length < 1000 ||
        ascii.decode(result.data.take(5).toList()) != '%PDF-') {
      throw StateError('Host did not return PDF');
    }
    checks['authorized-real-host-conversion'] = true;
    checks['generated-multipart-byte-decoder'] = true;
    final cached = await service
        .read(session.sessionId, 'synthetic.docx')
        .timeout(const Duration(seconds: 30));
    if (!identical(result, cached) || service.cachedEntries != 1) {
      throw StateError('Current-source reuse failed');
    }
    checks['reauthorized-current-generation-reuse'] = true;
    await File('${out.path}/synthetic-converted.pdf').writeAsBytes(result.data);
    await File('${out.path}/receipt.json').writeAsString(
      '${jsonEncode({'synthetic': true, 'realDshHost': true, 'modelInvoked': false, 'checks': checks, 'pdfBytes': result.data.length, 'missingFonts': result.missingFonts})}\n',
    );
    stdout.writeln(
      jsonEncode({'passed': checks.length, 'pdfBytes': result.data.length}),
    );
  } catch (e) {
    await File('${out.path}/failure.json').writeAsString(
      '${jsonEncode({'synthetic': true, 'checks': checks, 'errorType': '${e.runtimeType}', 'code': e is RemoteException ? e.code : null})}\n',
    );
    stderr.writeln(
      'Synthetic Office live check failed: ${e.runtimeType}${e is RemoteException ? ' (${e.code})' : ''}',
    );
    exitCode = 1;
  } finally {
    await service?.dispose();
    await connection?.stop();
    await host?.stop();
  }
}
