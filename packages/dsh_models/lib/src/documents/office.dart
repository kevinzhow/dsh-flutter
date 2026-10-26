import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_office_to_pdf.dart';

import '../settings/host_remotes.dart';

class _Superseded implements Exception {
  const _Superseded();
}

class _PendingOffice {
  _PendingOffice(this.cancellation, this.future);
  final RemoteCancellation cancellation;
  final Future<RenderedDocumentBytes> future;
  int users = 0;
}

Future<T> _wait<T>(Future<T> future, RemoteCancellation signal) async {
  signal.throwIfCancelled();
  final cancelled = Completer<T>();
  final off = signal.listen(() => cancelled.completeError(signal.reason));
  try {
    return await Future.any([future, cancelled.future]);
  } finally {
    off();
  }
}

/// A bounded cache of converted PDFs. Every reader reauthorizes in its original
/// Session and checks file version plus renderer generation before reuse.
class OfficePreviewService {
  OfficePreviewService({
    required this.remotes,
    required this.files,
    this.maxEntries = 8,
    this.maxBytes = 64 * 1024 * 1024,
    this.maxPending = 8,
    this.maxReaders = 32,
  }) {
    _generations = remotes.generations.listen((_) => reset());
  }
  final HostRemotes remotes;
  final WorkspaceFilesRemote files;
  final int maxEntries, maxBytes, maxPending, maxReaders;
  final _ready = <String, RenderedDocumentBytes>{};
  final _pending = <String, _PendingOffice>{};
  final _tasks = <Future<RenderedDocumentBytes>>{};
  final _readers = <RemoteCancellation>{};
  int _bytes = 0, _generationQuery = 0, _acceptedQuery = 0;
  String? _generation;
  bool _disposed = false;
  StreamSubscription<Object?>? _generations;
  int get cachedEntries => _ready.length;
  int get cachedBytes => _bytes;
  RemoteException _busy() => RemoteException(
    'document-render/failed',
    'Office preview capacity is full',
    {'reason': 'busy'},
  );

  Future<RenderedDocumentBytes> read(
    String sessionId,
    String path, {
    RemoteCancellation? cancellation,
    OfficeToPdfPriority priority = OfficeToPdfPriority.foreground,
  }) async {
    final signal = cancellation ?? RemoteCancellation();
    signal.throwIfCancelled();
    if (_disposed) {
      throw RemoteException('transport/disposed', 'Office preview disposed');
    }
    final background = priority == OfficeToPdfPriority.background;
    if (_readers.length >= (background ? maxReaders - 1 : maxReaders) ||
        (background && maxPending == 1)) {
      throw _busy();
    }
    // A unique owned signal lets service teardown cancel all readers, including
    // callers who happened to share their own cancellation signal.
    final owned = RemoteCancellation();
    final off = signal.listen(() => owned.cancel(signal.reason));
    _readers.add(owned);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await _lookup(sessionId, path, owned, priority);
        } on _Superseded {
          /* Reauthorize once against the new renderer. */
        }
      }
      throw _busy();
    } finally {
      off();
      _readers.remove(owned);
    }
  }

  Future<RenderedDocumentBytes> _lookup(
    String sessionId,
    String path,
    RemoteCancellation signal,
    OfficeToPdfPriority priority,
  ) async {
    signal.throwIfCancelled();
    final remote = OfficeToPdfRemote(
      ScopedRemoteCaller(remotes.caller, signal),
    );
    final query = ++_generationQuery;
    final generation = await remote.generation();
    signal.throwIfCancelled();
    if (query < _acceptedQuery && generation != _generation) {
      throw const _Superseded();
    }
    if (query > _acceptedQuery) _acceptedQuery = query;
    if (generation != _generation) {
      _generation = generation;
      _ready.clear();
      _bytes = 0;
      for (final pending in _pending.values.toList()) {
        pending.cancellation.cancel(const _Superseded());
      }
      _pending.clear();
    }
    // A metadata-only cache lookup is insufficient: ordinary read permission
    // must be checked even when a previous reader already converted the file.
    final authorized = await _wait(
      files.readBytes(
        sessionId,
        path,
        range: const ByteRange(offset: 0, length: 1),
      ),
      signal,
    );
    final metadata = await _wait(files.stat(sessionId, path), signal);
    signal.throwIfCancelled();
    if (authorized.absolutePath != metadata.absolutePath ||
        authorized.version != metadata.version) {
      throw RemoteException('document-render/failed', 'Office source changed', {
        'reason': 'source-changed',
      });
    }
    if (generation != _generation) throw const _Superseded();
    final key = jsonEncode([
      generation,
      sessionId,
      metadata.absolutePath,
      metadata.version,
    ]);
    final cached = _ready.remove(key);
    if (cached != null) {
      _ready[key] = cached;
      return cached;
    }
    final pendingKey = jsonEncode([key, priority.value]);
    var pending = _pending[pendingKey];
    if (pending == null) {
      final limit = priority == OfficeToPdfPriority.background
          ? maxPending - 1
          : maxPending;
      if (_tasks.length >= limit) throw _busy();
      final cancellation = RemoteCancellation();
      late final Future<RenderedDocumentBytes> future;
      future =
          Future<RenderedDocumentBytes>.microtask(() async {
            cancellation.throwIfCancelled();
            final converter = OfficeToPdfRemote(
              ScopedRemoteCaller(remotes.caller, cancellation),
            );
            final answer = await converter.render(sessionId, path, priority);
            cancellation.throwIfCancelled();
            if (generation == _generation &&
                answer.generation == generation &&
                answer.absolutePath == metadata.absolutePath &&
                answer.version == metadata.version) {
              _retain(key, answer);
            }
            return answer;
          }).whenComplete(() {
            _tasks.remove(future);
            if (identical(_pending[pendingKey]?.cancellation, cancellation)) {
              _pending.remove(pendingKey);
            }
          });
      _tasks.add(future);
      pending = _PendingOffice(cancellation, future);
      _pending[pendingKey] = pending;
    }
    final shared = pending;
    shared.users++;
    try {
      return await _wait(shared.future, signal);
    } finally {
      shared.users--;
      if (shared.users == 0 && identical(_pending[pendingKey], shared)) {
        _pending.remove(pendingKey);
        shared.cancellation.cancel();
      }
    }
  }

  void _retain(String key, RenderedDocumentBytes file) {
    final previous = _ready.remove(key);
    if (previous != null) _bytes -= previous.data.length;
    final size = file.data.length;
    if (size > maxBytes) return;
    while (_ready.isNotEmpty &&
        (_ready.length >= maxEntries || _bytes + size > maxBytes)) {
      _bytes -= _ready.remove(_ready.keys.first)!.data.length;
    }
    _ready[key] = file;
    _bytes += size;
  }

  void reset() {
    _generation = null;
    _generationQuery++;
    _acceptedQuery = _generationQuery;
    _ready.clear();
    _bytes = 0;
    final reason = RemoteException(
      'connection/reset',
      'Office preview connection changed',
    );
    for (final reader in _readers.toList()) {
      reader.cancel(reason);
    }
    for (final pending in _pending.values.toList()) {
      pending.cancellation.cancel(reason);
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    _disposed = true;
    reset();
    await _generations?.cancel();
    await Future.wait([
      for (final task in _tasks.toList())
        task.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }
}
