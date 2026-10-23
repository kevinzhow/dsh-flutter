import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/foundation.dart';

/// Brings a workspace file onto the device for the system to open or save
/// (dsh's "unpreviewable" action is the host's own open-in-app; a phone has no
/// host desktop, so it downloads). The file is read in windows of at most
/// [windowBytes] so a large file never sits in memory whole.
class FileDownload extends ChangeNotifier {
  FileDownload({
    required this.sessionId,
    required this.path,
    required this.name,
    required this.files,
    required this.actions,
    this.windowBytes = 1024 * 1024,
  });

  final String sessionId;
  final String path;
  final String name;
  final WorkspaceFilesRemote files;
  final HostFileActions actions;
  final int windowBytes;

  HostFileSink? _sink;
  Future<void>? _running;
  bool _disposed = false;

  /// Bytes written so far and the total when known.
  int loaded = 0;
  int? total;
  bool busy = false;
  bool done = false;
  Object? error;

  /// 0..1, or null while the total is unknown.
  double? get fraction =>
      total == null || total == 0 ? null : (loaded / total!).clamp(0.0, 1.0);

  /// Download (once), then hand the file to the system's viewer.
  Future<bool> open() async {
    if (!await _ensure()) return false;
    return _sink!.open();
  }

  /// Download (once), then let the person save a copy.
  Future<bool> save() async {
    if (!await _ensure()) return false;
    return _sink!.save();
  }

  Future<bool> _ensure() async {
    if (done) return true;
    await (_running ??= _run());
    return done;
  }

  Future<void> _run() async {
    busy = true;
    error = null;
    loaded = 0;
    _changed();
    try {
      final sink = await actions.begin(name);
      _sink = sink;
      var offset = 0;
      while (!_disposed) {
        final window = await files.readBytes(
          sessionId,
          path,
          range: ByteRange(offset: offset, length: windowBytes),
        );
        total ??= window.bytes;
        if (window.data.isNotEmpty) await sink.add(window.data);
        offset += window.data.length;
        loaded = offset;
        _changed();
        if (window.eof || window.data.isEmpty) break;
      }
      if (_disposed) {
        await sink.discard();
        return;
      }
      await sink.finish();
      done = true;
    } on Object catch (e) {
      error = e;
      await _sink?.discard();
      _sink = null;
    } finally {
      busy = false;
      _running = null;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!done) unawaited(_sink?.discard());
    super.dispose();
  }
}
