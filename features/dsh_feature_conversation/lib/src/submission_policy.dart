import 'dart:async';

import 'package:dsh_models/dsh_models.dart';

/// Plain Enter and Send share one delivery intent; accelerated Enter uses
/// the opposite intent only while steering is supported and the agent runs.
String resolveSubmitMode(
  String preferred,
  bool running, {
  bool accelerated = false,
  bool steeringAvailable = true,
}) {
  if (!running || !steeringAvailable) return 'queue';
  return accelerated ? (preferred == 'queue' ? 'steer' : 'queue') : preferred;
}

/// The Host's ui-conversation.busyEnter setting. Rebinding resets the local
/// default so a previous Host's preference never leaks into another Host.
class ConversationPreferences {
  final busyEnter = Observable('queue');
  ConfigForm? _host;
  void Function()? _off;
  int _generation = 0, _pending = 0;
  bool _acceptedChanged = false;

  void bind(ConfigForm? host) {
    _off?.call();
    _generation++;
    _pending = 0;
    _host = host;
    busyEnter.set('queue');
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
    if (_pending > 0 ||
        !_acceptedChanged ||
        _host?.snapshot.status != ConfigFormStatus.ready) {
      return;
    }
    final raw = _host?.snapshot.value?['busyEnter'];
    _acceptedChanged = false;
    busyEnter.set(raw == 'steer' ? 'steer' : 'queue');
  }

  void setBusyEnter(String value) {
    if ((value != 'queue' && value != 'steer') || busyEnter.value == value) {
      return;
    }
    busyEnter.set(value);
    final host = _host;
    if (host == null) return;
    final generation = _generation;
    _pending++;
    unawaited(
      host
          .set('busyEnter', value)
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() {
            if (generation != _generation) return;
            _pending--;
            _adopt();
          }),
    );
  }

  Future<void> dispose() async {
    _off?.call();
    _generation++;
    await busyEnter.dispose();
  }
}
