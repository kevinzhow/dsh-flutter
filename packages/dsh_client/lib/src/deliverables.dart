import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pairing.dart';
import 'remote_caller.dart';

bool _safe(Object? v) =>
    v is num &&
    v.isFinite &&
    v == v.truncateToDouble() &&
    v.abs() <= 9007199254740991;
bool _nonempty(Object? v) => v is String && v.isNotEmpty;
Map<String, Object?> _record(Object? v) =>
    v is Map<String, Object?> ? v : const {};
Never _bad() => throw const FormatException('Invalid deliverables record');

class ChangedFile {
  const ChangedFile({
    required this.path,
    required this.display,
    required this.added,
    required this.deleted,
    this.binary = false,
    this.oversized = false,
  });
  factory ChangedFile.fromJson(Object? value) {
    final m = _record(value);
    if (!_nonempty(m['path']) ||
        !_nonempty(m['display']) ||
        !_safe(m['added']) ||
        !_safe(m['deleted']) ||
        (m.containsKey('binary') && m['binary'] != true) ||
        (m.containsKey('oversized') && m['oversized'] != true)) {
      _bad();
    }
    return ChangedFile(
      path: m['path'] as String,
      display: m['display'] as String,
      added: (m['added'] as num).toInt(),
      deleted: (m['deleted'] as num).toInt(),
      binary: m['binary'] == true,
      oversized: m['oversized'] == true,
    );
  }
  final String path, display;
  final int added, deleted;
  final bool binary, oversized;
}

class ChangesSummary {
  const ChangesSummary({
    required this.turn,
    required this.files,
    required this.total,
    required this.added,
    required this.deleted,
  });
  factory ChangesSummary.fromJson(Object? value) {
    final m = _record(value);
    if (!_safe(m['turn']) ||
        (m['turn'] as num) < 1 ||
        !_safe(m['total']) ||
        !_safe(m['added']) ||
        !_safe(m['deleted']) ||
        m['files'] is! List) {
      _bad();
    }
    return ChangesSummary(
      turn: (m['turn'] as num).toInt(),
      files: List.unmodifiable((m['files'] as List).map(ChangedFile.fromJson)),
      total: (m['total'] as num).toInt(),
      added: (m['added'] as num).toInt(),
      deleted: (m['deleted'] as num).toInt(),
    );
  }
  final int turn, total, added, deleted;
  final List<ChangedFile> files;
}

class ChangesHunk {
  const ChangesHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.lines,
  });
  factory ChangesHunk.fromJson(Object? value) {
    final m = _record(value);
    for (final key in ['oldStart', 'oldLines', 'newStart', 'newLines']) {
      if (!_safe(m[key]) || (m[key] as num) < 0) _bad();
    }
    final lines = m['lines'];
    if (lines is! List ||
        !lines.every(
          (v) => v is String && v.isNotEmpty && '+ -'.contains(v[0]),
        )) {
      _bad();
    }
    return ChangesHunk(
      oldStart: (m['oldStart'] as num).toInt(),
      oldLines: (m['oldLines'] as num).toInt(),
      newStart: (m['newStart'] as num).toInt(),
      newLines: (m['newLines'] as num).toInt(),
      lines: List.unmodifiable(lines.cast<String>()),
    );
  }
  final int oldStart, oldLines, newStart, newLines;
  final List<String> lines;
}

class ChangesDiff {
  const ChangesDiff({
    required this.kind,
    required this.path,
    required this.display,
    this.before = false,
    this.after = false,
    this.coarse = false,
    this.hunks = const [],
  });
  factory ChangesDiff.fromJson(Object? value) {
    final m = _record(value), kind = _record(value)['kind'];
    if (!_nonempty(m['path']) ||
        !_nonempty(m['display']) ||
        !['binary', 'oversized', 'text'].contains(kind)) {
      _bad();
    }
    if (kind == 'text' &&
        (m['before'] is! bool ||
            m['after'] is! bool ||
            m['coarse'] is! bool ||
            m['hunks'] is! List)) {
      _bad();
    }
    return ChangesDiff(
      kind: kind as String,
      path: m['path'] as String,
      display: m['display'] as String,
      before: m['before'] == true,
      after: m['after'] == true,
      coarse: m['coarse'] == true,
      hunks: kind == 'text'
          ? List.unmodifiable((m['hunks'] as List).map(ChangesHunk.fromJson))
          : const [],
    );
  }
  final String kind, path, display;
  final bool before, after, coarse;
  final List<ChangesHunk> hunks;
}

class PresentedHost {
  const PresentedHost({
    required this.name,
    required this.available,
    this.fileManager,
  });
  factory PresentedHost.fromJson(Object? value) {
    final m = _record(value);
    if (m['name'] is! String ||
        m['available'] is! bool ||
        !m.containsKey('fileManager') ||
        ![null, 'finder', 'explorer', 'directory'].contains(m['fileManager'])) {
      _bad();
    }
    return PresentedHost(
      name: m['name'] as String,
      available: m['available'] as bool,
      fileManager: m['fileManager'] as String?,
    );
  }
  final String name;
  final bool available;
  final String? fileManager;
}

/// Cancellation settles pending connection and body reads immediately. Late
/// socket completion is drained/aborted without publishing stale host state.
class DeliverablesCancel {
  final Completer<void> _done = Completer<void>();
  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!cancelled) _done.complete();
  }
}

class DeliverablesCancelled implements Exception {
  const DeliverablesCancelled();
}

class DeliverablesHttpFailure implements Exception {
  const DeliverablesHttpFailure(this.status);
  final int status;
}

enum FileDeliveryKind { presented, changed }

enum NativeFileAction { open, reveal }

/// Durable coordinates; no client path is sent to a native-open route.
class DeliveryFile {
  const DeliveryFile(
    this.sessionId,
    this.seq,
    this.index, {
    this.kind = FileDeliveryKind.presented,
  });
  final String sessionId;
  final num seq;
  final int index;
  final FileDeliveryKind kind;
  String get actionKey => deliveryRoute(
    kind == FileDeliveryKind.presented
        ? '/api/present.open'
        : '/api/changes.open',
    sessionId,
    seq,
    index: index,
  ).toString();
}

Uri deliveryRoute(String path, String sessionId, num seq, {int? index}) => Uri(
  path: path,
  queryParameters: {
    'sessionId': sessionId,
    'seq': seq == seq.truncate() ? '${seq.truncate()}' : '$seq',
    if (index != null) 'index': '$index',
  },
);

class NativeFileApplication {
  const NativeFileApplication({
    required this.id,
    required this.name,
    required this.isDefault,
    this.icon,
  });
  factory NativeFileApplication.fromJson(Object? value) {
    final m = _record(value), icon = _record(value)['icon'];
    if (!_nonempty(m['id']) ||
        m['name'] is! String ||
        m['default'] is! bool ||
        !m.containsKey('icon') ||
        !(icon == null ||
            icon is String &&
                RegExp(r'^data:image/(?:png|svg\+xml);base64,[A-Za-z0-9+/=]+$')
                    .hasMatch(icon))) {
      _bad();
    }
    return NativeFileApplication(
      id: m['id'] as String,
      name: m['name'] as String,
      isDefault: m['default'] as bool,
      icon: icon as String?,
    );
  }
  final String id, name;
  final bool isDefault;
  final String? icon;
}

abstract interface class DeliverablesClient {
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  });
  Future<ChangesSummary> summary(
    String sessionId,
    num seq, {
    DeliverablesCancel? cancel,
  });
  Future<ChangesDiff> diff(
    String sessionId,
    num seq,
    int index, {
    DeliverablesCancel? cancel,
  });
  Future<PresentedHost> host({DeliverablesCancel? cancel});
  Future<void> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
    DeliverablesCancel? cancel,
  });
}

class HttpDeliverablesClient implements DeliverablesClient {
  HttpDeliverablesClient({
    required PairedCredential? Function() credential,
    HttpClient? httpClient,
    HttpClient Function(Uri origin)? clientFor,
  }) : _credential = credential,
       _http = httpClient ?? HttpClient(),
       _clientFor = clientFor;
  final PairedCredential? Function() _credential;
  final HttpClient _http;
  final HttpClient Function(Uri origin)? _clientFor;
  Future<Object?> _send(
    String method,
    Uri route,
    DeliverablesCancel? cancel, {
    bool json = true,
  }) async {
    final credential = _credential();
    if (credential == null) {
      throw RemoteException('connection/not-connected', 'no live generation');
    }
    if (cancel?.cancelled ?? false) throw const DeliverablesCancelled();
    HttpClientRequest? request;
    StreamSubscription<List<int>>? body;
    final completed = Completer<Object?>();
    void fail(Object e, [StackTrace? stack]) {
      if (!completed.isCompleted) completed.completeError(e, stack);
    }

    // A subscription, rather than a never-completing Future listener, can be
    // released when a normal request finishes.
    final cancellation = cancel?.whenCancelled.asStream().listen((_) {
      request?.abort(const DeliverablesCancelled());
      unawaited(body?.cancel());
      fail(const DeliverablesCancelled());
    });
    unawaited(() async {
      try {
        request = await (_clientFor?.call(credential.origin) ?? _http).openUrl(
          method,
          credential.origin.replace(path: route.path, query: route.query),
        );
        if (completed.isCompleted) {
          request!.abort();
          return;
        }
        request!.followRedirects = false;
        request!.headers.set(HttpHeaders.cookieHeader, credential.cookieHeader);
        final response = await request!.close();
        if (completed.isCompleted) {
          unawaited(response.listen((_) {}).cancel());
          return;
        }
        final bytes = <int>[];
        body = response.listen(
          bytes.addAll,
          onError: fail,
          onDone: () {
            if (completed.isCompleted) return;
            try {
              if (response.statusCode < 200 || response.statusCode >= 300) {
                throw DeliverablesHttpFailure(response.statusCode);
              }
              completed.complete(json ? jsonDecode(utf8.decode(bytes)) : null);
            } on Object catch (e, st) {
              fail(e, st);
            }
          },
          cancelOnError: true,
        );
      } on Object catch (e, st) {
        fail(e, st);
      }
    }());
    try {
      return await completed.future;
    } finally {
      await cancellation?.cancel();
    }
  }

  @override
  Future<ChangesSummary> summary(
    String sessionId,
    num seq, {
    DeliverablesCancel? cancel,
  }) async => ChangesSummary.fromJson(
    await _send(
      'GET',
      deliveryRoute('/api/changes.summary', sessionId, seq),
      cancel,
    ),
  );
  @override
  Future<ChangesDiff> diff(
    String sessionId,
    num seq,
    int index, {
    DeliverablesCancel? cancel,
  }) async => ChangesDiff.fromJson(
    await _send(
      'GET',
      deliveryRoute('/api/changes.diff', sessionId, seq, index: index),
      cancel,
    ),
  );
  @override
  Future<PresentedHost> host({DeliverablesCancel? cancel}) async =>
      PresentedHost.fromJson(
        await _send('GET', Uri(path: '/api/present.host'), cancel),
      );
  @override
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  }) async {
    final value = await _send('GET', Uri.parse(file.actionKey), cancel);
    if (value is! List) _bad();
    return List.unmodifiable(value.map(NativeFileApplication.fromJson));
  }

  @override
  Future<void> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
    DeliverablesCancel? cancel,
  }) async {
    final route = Uri.parse(file.actionKey);
    await _send(
      'POST',
      route.replace(
        queryParameters: {
          ...route.queryParameters,
          if (action == NativeFileAction.reveal) 'action': 'reveal',
          if (action == NativeFileAction.open && application != null)
            'application': application,
        },
      ),
      cancel,
      json: false,
    );
  }

  void close() => _http.close(force: true);
}
