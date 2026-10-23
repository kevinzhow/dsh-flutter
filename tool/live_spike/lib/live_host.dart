import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A `dsh web` host this harness starts and owns. Only this process (by the
/// PID `Process.start` returned) is ever signalled. The launch token is
/// captured in memory from the child's stdout and never printed.
class LiveHost {
  LiveHost._(this._process, this.port, this.workspace);

  final Process _process;
  final int port;
  final String workspace;
  String? _token;
  final Completer<String> _tokenReady = Completer<String>();
  final StringBuffer _stderrTail = StringBuffer();
  late final Future<int> exitCode = _process.exitCode;

  int get pid => _process.pid;
  Uri get origin => Uri.parse('http://127.0.0.1:$port');
  Future<String> get token => _tokenReady.future;
  String? get tokenIfReady => _token;

  /// Spawn `dsh web --host 127.0.0.1 --port <port> --no-open` in [workspace].
  /// The shared `DSH_HOME` is inherited from the environment on purpose (the
  /// configured model must work); nothing is copied or written by this class.
  static Future<LiveHost> start({
    required int port,
    required String workspace,
    String dshBinary = 'dsh',
  }) async {
    final process = await Process.start(dshBinary, [
      'web',
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
      '--no-open',
    ], workingDirectory: workspace);
    final host = LiveHost._(process, port, workspace);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final m = RegExp(r'[?&]token=([A-Za-z0-9_\-%.]+)').firstMatch(line);
          if (m != null && !host._tokenReady.isCompleted) {
            host._token = Uri.decodeComponent(m.group(1)!);
            host._tokenReady.complete(host._token);
          }
        });
    process.stderr.transform(utf8.decoder).listen((chunk) {
      host._stderrTail.write(chunk);
      final s = host._stderrTail.toString();
      if (s.length > 4000) {
        host._stderrTail
          ..clear()
          ..write(s.substring(s.length - 2000));
      }
    });
    unawaited(
      process.exitCode.then((_) {
        if (!host._tokenReady.isCompleted) {
          host._tokenReady.completeError(
            StateError('dsh exited before printing a launch token'),
          );
        }
      }),
    );
    return host;
  }

  /// Wait until the port accepts TCP connections.
  Future<void> waitListening({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      try {
        final s = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(seconds: 1),
        );
        s.destroy();
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw TimeoutException('dsh did not listen on $port');
  }

  /// Stop this child by PID: SIGTERM, then SIGKILL after [grace].
  Future<void> stop({Duration grace = const Duration(seconds: 15)}) async {
    _process.kill(ProcessSignal.sigterm);
    try {
      await exitCode.timeout(grace);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await exitCode;
    }
  }

  /// Last stderr bytes with anything token-shaped removed.
  String get redactedStderrTail => _stderrTail.toString().replaceAll(
    RegExp(r'token=[^\s&]+'),
    'token=<redacted>',
  );
}
