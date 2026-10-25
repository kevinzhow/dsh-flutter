import 'dart:async';

import 'package:dsh_models/dsh_models.dart';

/// Host-backed work presentation, independent of the collapse timing.
enum TranscriptViewMode { compact, standard, detailed, verbose }

enum CollapseTiming { completion, nextInput }

class ChatPreferences {
  ChatPreferences({bool desktop = false})
    : defaultMode = desktop
          ? TranscriptViewMode.standard
          : TranscriptViewMode.detailed,
      mode = Observable(
        desktop ? TranscriptViewMode.standard : TranscriptViewMode.detailed,
      );

  final TranscriptViewMode defaultMode;
  final Observable<TranscriptViewMode> mode;
  final timing = Observable(CollapseTiming.completion);
  ConfigForm? _host;
  void Function()? _off;
  int _generation = 0, _pending = 0;
  bool _disposed = false, _acceptedChanged = false;

  bool get foldCompleted => mode.value != TranscriptViewMode.verbose;
  bool get liveDetail =>
      mode.value == TranscriptViewMode.standard ||
      mode.value == TranscriptViewMode.detailed;
  bool get reasoningPreview => mode.value != TranscriptViewMode.compact;
  bool get writable => _host?.snapshot.writable ?? false;

  void bind(ConfigForm? host) {
    if (_disposed) return;
    _off?.call();
    _generation++;
    _pending = 0;
    _host = host;
    mode.set(defaultMode);
    timing.set(CollapseTiming.completion);
    _acceptedChanged = true;
    _off = host?.subscribe(() {
      if (host.snapshot.status == ConfigFormStatus.ready) {
        _acceptedChanged = true;
      }
      _adopt();
    });
    _adopt();
  }

  void _adopt() {
    if (_disposed || _pending > 0 || !_acceptedChanged) return;
    final value = _host?.snapshot.value;
    if (value == null || _host?.snapshot.status != ConfigFormStatus.ready) {
      return;
    }
    _acceptedChanged = false;
    final raw = value['transcriptView'];
    mode.set(
      raw == 'normal' || raw == 'expanded'
          ? TranscriptViewMode.detailed
          : TranscriptViewMode.values.where((v) => v.name == raw).firstOrNull ??
                defaultMode,
    );
    timing.set(
      value['collapseTiming'] == 'next-input'
          ? CollapseTiming.nextInput
          : CollapseTiming.completion,
    );
  }

  void setMode(TranscriptViewMode value) {
    if (mode.value == value) return;
    mode.set(value);
    _write('transcriptView', value.name);
  }

  void setTiming(CollapseTiming value) {
    if (timing.value == value) return;
    timing.set(value);
    _write(
      'collapseTiming',
      value == CollapseTiming.nextInput ? 'next-input' : 'completion',
    );
  }

  void _write(String key, String value) {
    final host = _host;
    if (host == null) return;
    final generation = _generation;
    _pending++;
    unawaited(
      host
          .set(key, value)
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() {
            if (generation != _generation) return;
            _pending--;
            _adopt();
          }),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _off?.call();
    _generation++;
    await mode.dispose();
    await timing.dispose();
  }
}
