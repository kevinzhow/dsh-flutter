import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show OpenInAppClient;
import 'package:flutter/foundation.dart';

import 'applications.dart';

/// Availability, the remembered choice and the launch state shared by every
/// header (dsh `OpenInAppController`). It offers nothing until [enabled]: the
/// applications live on the host machine, so the controls are for a host that
/// is this one.
class OpenInAppController extends ChangeNotifier {
  OpenInAppController({
    required OpenInAppClient client,
    required String? Function() readChoice,
    required void Function(String id) writeChoice,
  }) : _client = client,
       _readChoice = readChoice,
       _writeChoice = writeChoice;

  final OpenInAppClient _client;
  final String? Function() _readChoice;
  final void Function(String id) _writeChoice;
  final Map<String, Future<Uint8List?>> _icons = {};
  bool _enabled = false;
  bool _busy = false;
  bool _failed = false;
  List<String>? _apps;
  int _epoch = 0;

  /// Whether the host is this machine.
  bool get enabled => _enabled;

  /// Installed application ids in host menu order; null until the host answered.
  List<String>? get apps => _apps;

  /// A launch is in flight.
  bool get busy => _busy;

  /// The last launch failed.
  bool get failed => _failed;

  /// Turn the controls on or off with the host's locality. Turning on reads the
  /// installed applications once; turning off forgets them (and the icons).
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _epoch++;
    _apps = null;
    _icons.clear();
    notifyListeners();
    if (value) unawaited(load());
  }

  /// Read the installed applications (a failed read is an empty list).
  Future<void> load() async {
    final epoch = _epoch;
    final apps = await _client.apps();
    if (epoch != _epoch) return;
    _apps = apps;
    notifyListeners();
  }

  /// The nameable installed ids.
  List<String> get nameable => [
    for (final id in _apps ?? const <String>[])
      if (applicationLabelKey.containsKey(id)) id,
  ];

  /// The remembered application, falling back to the first one installed.
  String? currentApp() {
    final ids = nameable;
    final choice = _readChoice();
    return choice != null && ids.contains(choice)
        ? choice
        : (ids.isEmpty ? null : ids.first);
  }

  /// Remember [id] as the choice.
  void choose(String id) {
    if (_busy) return;
    _writeChoice(id);
    notifyListeners();
  }

  /// The icon bytes of [id], read once; null when the host has none.
  Future<Uint8List?> icon(String id) => _icons[id] ??= _client.icon(id);

  /// Launch [appId] on [path]. Concurrent gestures are ignored; any failure is
  /// rethrown after the state shows it.
  Future<void> launch(String appId, String path) async {
    if (_busy) return;
    _busy = true;
    _failed = false;
    notifyListeners();
    try {
      await _client.open(appId, path);
    } on Object {
      _failed = true;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
