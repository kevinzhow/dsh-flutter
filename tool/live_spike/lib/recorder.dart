import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

/// Records the raw follow frames, page reads and client actions of one session
/// in observed order, as a raw (unscrubbed) trace. The raw trace may contain
/// real prompts and replies: it lives outside the repository and goes through
/// `tool/vectors/scrub_trace.py` before anything is committed.
class RecordingTransport implements SessionTransport {
  RecordingTransport(this.inner);

  final SessionTransport inner;
  final List<Map<String, Object?>> steps = [];
  final Stopwatch _clock = Stopwatch()..start();

  void _log(Map<String, Object?> step) =>
      steps.add({'t': _clock.elapsedMilliseconds, ...step});

  /// A client action that is part of the replay script.
  void action(String name, [Map<String, Object?> args = const {}]) =>
      _log({'op': 'action', 'name': name, ...args});

  @override
  Stream<GenerationFrame> follow(Map<String, Object?> Function() request) {
    final controller = StreamController<GenerationFrame>();
    late StreamSubscription<GenerationFrame> sub;
    controller.onListen = () {
      sub = inner
          .follow(() {
            final r = request();
            _log({'op': 'follow-open', 'request': r});
            return r;
          })
          .listen((f) {
            switch (f) {
              case StreamOpened():
                _log({'op': 'opened', 'generation': f.generation});
              case StreamItem():
                _log({
                  'op': 'frame',
                  'generation': f.generation,
                  'frame': f.value,
                });
              case StreamEnded():
                _log({
                  'op': 'ended',
                  'generation': f.generation,
                  'error': f.error == null
                      ? null
                      : '${(f.error as Object).runtimeType}',
                });
            }
            controller.add(f);
          }, onDone: controller.close);
    };
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Future<Map<String, Object?>> page(Map<String, Object?> request) async {
    final response = await inner.page(request);
    _log({'op': 'page', 'request': request, 'response': response});
    return response;
  }

  @override
  Future<Map<String, Object?>> list() => inner.list();
  @override
  Future<Map<String, Object?>> create(Map<String, Object?> request) =>
      inner.create(request);
  @override
  Future<void> prompt(Map<String, Object?> request) {
    _log({'op': 'action', 'name': 'prompt'});
    return inner.prompt(request);
  }

  @override
  Future<void> updateQueue(Map<String, Object?> request) =>
      inner.updateQueue(request);

  @override
  Future<void> cancel(String sessionId) => inner.cancel(sessionId);
  @override
  Future<Map<String, Object?>> attachment(
    String sessionId,
    String attachmentId,
  ) => inner.attachment(sessionId, attachmentId);
  @override
  Stream<GenerationFrame> control() => inner.control();
  @override
  Stream<HostEvent> get hostEvents => inner.hostEvents;
  @override
  Stream<ConnectionGeneration?> get generations => inner.generations;
  @override
  ConnectionGeneration? get generation => inner.generation;
}
