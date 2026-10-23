import 'dart:async';
import 'dart:typed_data';

import 'connection.dart';
import 'remote_caller.dart';

// The `workspaceFiles` Remote namespace of dsh (`packages/api/workspace-files`).
// Hand-written, not generated: tool/codegen only extracts the `session`
// namespace. `tool/tests/test_workspace_files_pin.py` checks the method and
// wire-argument names below against the pinned dsh checkout, so a drift fails
// preflight. The first wire argument of every method is the Session identity,
// named `workspaceFileScopeId` (a Typert lookup parameter), not `sessionId`.

/// Identity and freshness of one workspace file, without its content.
class WorkspaceFileStat {
  const WorkspaceFileStat({
    required this.absolutePath,
    required this.version,
    this.bytes,
  });

  factory WorkspaceFileStat.fromJson(Object? json) {
    final m = _map(json, 'stat');
    return WorkspaceFileStat(
      absolutePath: _str(m, 'absolutePath'),
      version: _str(m, 'version'),
      bytes: m['bytes'] is int ? m['bytes'] as int : null,
    );
  }

  /// Absolute path in the filesystem's execution world, symlinks resolved.
  final String absolutePath;

  /// Opaque freshness token; never parsed.
  final String version;

  /// Byte size of the complete file, when the backend reports it.
  final int? bytes;
}

/// One page of a workspace text file: lines joined by `\n` without a trailing
/// terminator (`lines` tells an empty page from one empty line).
class WorkspaceFileText extends WorkspaceFileStat {
  const WorkspaceFileText({
    required super.absolutePath,
    required super.version,
    super.bytes,
    required this.offset,
    required this.text,
    required this.lines,
    required this.eof,
  });

  factory WorkspaceFileText.fromJson(Object? json) {
    final m = _map(json, 'read');
    final s = WorkspaceFileStat.fromJson(m);
    return WorkspaceFileText(
      absolutePath: s.absolutePath,
      version: s.version,
      bytes: s.bytes,
      offset: _int(m, 'offset'),
      text: _str(m, 'text'),
      lines: _int(m, 'lines'),
      eof: _bool(m, 'eof'),
    );
  }

  /// First line of the page (1-based).
  final int offset;
  final String text;
  final int lines;

  /// Whether the page includes the file's last line.
  final bool eof;
}

/// One byte window (or the complete file) of a workspace file.
class WorkspaceFileBytes extends WorkspaceFileStat {
  const WorkspaceFileBytes({
    required super.absolutePath,
    required super.version,
    super.bytes,
    required this.offset,
    required this.data,
    required this.eof,
  });

  factory WorkspaceFileBytes.fromJson(Object? json) {
    final m = _map(json, 'readBytes');
    final s = WorkspaceFileStat.fromJson(m);
    final data = m['data'];
    if (data is! Uint8List) {
      throw RemoteException(
        'transport/bad-envelope',
        'readBytes carried no byte data',
      );
    }
    return WorkspaceFileBytes(
      absolutePath: s.absolutePath,
      version: s.version,
      bytes: s.bytes,
      offset: _int(m, 'offset'),
      data: data,
      eof: _bool(m, 'eof'),
    );
  }

  /// First byte of the window (0-based).
  final int offset;
  final Uint8List data;
  final bool eof;
}

enum WorkspaceEntryType { file, directory, other }

/// One direct child of a listed directory.
class WorkspaceDirectoryEntry {
  const WorkspaceDirectoryEntry({
    required this.name,
    required this.type,
    this.size,
  });

  factory WorkspaceDirectoryEntry.fromJson(Object? json) {
    final m = _map(json, 'entry');
    return WorkspaceDirectoryEntry(
      name: _str(m, 'name'),
      type: switch (m['type']) {
        'file' => WorkspaceEntryType.file,
        'directory' => WorkspaceEntryType.directory,
        _ => WorkspaceEntryType.other,
      },
      size: m['size'] is int ? m['size'] as int : null,
    );
  }

  final String name;
  final WorkspaceEntryType type;
  final int? size;
}

/// Direct children of one workspace directory.
class WorkspaceDirectoryListing {
  const WorkspaceDirectoryListing({
    required this.path,
    required this.entries,
    required this.truncated,
  });

  factory WorkspaceDirectoryListing.fromJson(Object? json) {
    final m = _map(json, 'list');
    final entries = m['entries'];
    if (entries is! List) {
      throw RemoteException('transport/bad-envelope', 'list without entries');
    }
    return WorkspaceDirectoryListing(
      path: _str(m, 'path'),
      entries: [for (final e in entries) WorkspaceDirectoryEntry.fromJson(e)],
      truncated: _bool(m, 'truncated'),
    );
  }

  /// The directory as a workspace path, empty for the root.
  final String path;
  final List<WorkspaceDirectoryEntry> entries;

  /// Whether the entry cap dropped children.
  final bool truncated;
}

/// A byte window request (`range` of `readBytes`): offsets are 0-based.
class ByteRange {
  const ByteRange({this.offset, this.length});
  final int? offset;
  final int? length;

  Map<String, Object?> toJson() => {'offset': ?offset, 'length': ?length};
}

/// What a change watch tells its consumer.
sealed class WorkspaceWatchEvent {
  const WorkspaceWatchEvent();
}

/// The watcher of the current connection generation is initialized.
class WatchReady extends WorkspaceWatchEvent {
  const WatchReady();
}

/// The target changed (current metadata) or was observed gone.
class WatchChanged extends WorkspaceWatchEvent {
  const WatchChanged({required this.absolutePath, this.version, this.absent});
  final String absolutePath;
  final String? version;
  final bool? absent;
}

/// A new connection generation opened the watch again; anything cached may
/// have changed while the link was down.
class WatchReopened extends WorkspaceWatchEvent {
  const WatchReopened();
}

/// The workspace file service as the features see it. The real implementation
/// is [DshWorkspaceFiles]; widget tests inject a scripted one.
abstract interface class WorkspaceFilesRemote {
  Future<WorkspaceFileStat> stat(String sessionId, String path);

  /// One window of lines (1-based [offset], at most [limit], both default to
  /// the host's page).
  Future<WorkspaceFileText> read(
    String sessionId,
    String path, {
    int? offset,
    int? limit,
  });

  /// The complete file (under the host's complete-file cap), or one byte
  /// [range]. [baseFile] resolves a relative [path] from that file's directory.
  Future<WorkspaceFileBytes> readBytes(
    String sessionId,
    String path, {
    ByteRange? range,
    String? baseFile,
  });

  Future<WorkspaceDirectoryListing> list(String sessionId, String path);

  /// Watch one file or a directory's direct entries; reopens by itself on each
  /// connection generation (a [WatchReopened] precedes the new [WatchReady]).
  Stream<WorkspaceWatchEvent> changes(String sessionId, String path);
}

/// [WorkspaceFilesRemote] over a live [DshConnection].
class DshWorkspaceFiles implements WorkspaceFilesRemote {
  DshWorkspaceFiles(this.connection);

  final DshConnection connection;

  static const String namespace = 'workspaceFiles';

  Future<Object?> _call(
    String method,
    String sessionId,
    Map<String, Object?> args,
  ) => connection.caller.call(namespace, method, {
    'workspaceFileScopeId': sessionId,
    ...args,
  });

  @override
  Future<WorkspaceFileStat> stat(String sessionId, String path) async =>
      WorkspaceFileStat.fromJson(
        await _call('stat', sessionId, {'path': path}),
      );

  @override
  Future<WorkspaceFileText> read(
    String sessionId,
    String path, {
    int? offset,
    int? limit,
  }) async => WorkspaceFileText.fromJson(
    await _call('read', sessionId, {
      'path': path,
      'range': {'offset': ?offset, 'limit': ?limit},
    }),
  );

  @override
  Future<WorkspaceFileBytes> readBytes(
    String sessionId,
    String path, {
    ByteRange? range,
    String? baseFile,
  }) async => WorkspaceFileBytes.fromJson(
    await _call('readBytes', sessionId, {
      'path': path,
      'options': {
        if (range != null) 'range': range.toJson(),
        'baseFile': ?baseFile,
      },
    }),
  );

  @override
  Future<WorkspaceDirectoryListing> list(String sessionId, String path) async =>
      WorkspaceDirectoryListing.fromJson(
        await _call('list', sessionId, {'path': path}),
      );

  @override
  Stream<WorkspaceWatchEvent> changes(String sessionId, String path) {
    return connection
        .openStream(
          '$namespace/changes',
          () => {'workspaceFileScopeId': sessionId, 'path': path},
        )
        .transform(
          StreamTransformer.fromHandlers(
            handleData: (frame, sink) {
              switch (frame) {
                case StreamOpened():
                  sink.add(const WatchReopened());
                case StreamEnded(:final error):
                  // A watch the host cannot start is terminal for this
                  // consumer; a lost generation reopens by itself.
                  if (error is RemoteException &&
                      error.code != 'transport/carrier-lost') {
                    sink.addError(error);
                  }
                case StreamItem(:final value):
                  final event = _watchEvent(value);
                  if (event != null) sink.add(event);
              }
            },
          ),
        );
  }

  static WorkspaceWatchEvent? _watchEvent(Object? value) {
    if (value is! Map<String, Object?>) return null;
    if (value['kind'] == 'ready') return const WatchReady();
    if (value['kind'] != 'change') return null;
    final change = value['change'];
    if (change is! Map<String, Object?> || change['absolutePath'] is! String) {
      return null;
    }
    return WatchChanged(
      absolutePath: change['absolutePath']! as String,
      version: change['version'] is String ? change['version'] as String : null,
      absent: change['absent'] == true ? true : null,
    );
  }
}

// ---- field readers ------------------------------------------------------

Map<String, Object?> _map(Object? json, String what) {
  if (json is Map<String, Object?>) {
    return json;
  }
  throw RemoteException('transport/bad-envelope', '$what: not an object');
}

String _str(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is String) {
    return v;
  }
  throw RemoteException('transport/bad-envelope', 'missing string "$key"');
}

int _int(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is int) {
    return v;
  }
  throw RemoteException('transport/bad-envelope', 'missing integer "$key"');
}

bool _bool(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is bool) {
    return v;
  }
  throw RemoteException('transport/bad-envelope', 'missing boolean "$key"');
}
