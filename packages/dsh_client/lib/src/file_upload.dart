import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pairing.dart';
import 'remote_caller.dart';

/// Where a streamed upload is (dsh `FileUploadProgress`): bytes handed to the
/// socket so far, and the total when the body length is known.
class UploadProgress {
  const UploadProgress(this.loaded, [this.total]);
  final int loaded;
  final int? total;

  @override
  String toString() => 'UploadProgress($loaded/${total ?? '?'})';
}

/// The durable receipt of one staged upload (dsh `FileUploadValue`): the opaque
/// [receiptId] a later prompt cites, and the stored file reference.
class FileUploadReceipt {
  const FileUploadReceipt({
    required this.receiptId,
    required this.attachmentId,
    required this.name,
    required this.bytes,
  });

  factory FileUploadReceipt.fromJson(Object? json) {
    final m = json is Map<String, Object?> ? json : const <String, Object?>{};
    final file = m['file'] is Map<String, Object?>
        ? m['file'] as Map<String, Object?>
        : const <String, Object?>{};
    final receipt = m['receiptId'];
    final id = file['attachmentId'];
    final name = file['name'];
    final bytes = file['bytes'];
    if (receipt is! String ||
        id is! String ||
        name is! String ||
        bytes is! int ||
        bytes < 0) {
      throw RemoteException(
        'transport/bad-envelope',
        'file upload returned an invalid receipt',
      );
    }
    return FileUploadReceipt(
      receiptId: receipt,
      attachmentId: id,
      name: name,
      bytes: bytes,
    );
  }

  final String receiptId;
  final String attachmentId;
  final String name;
  final int bytes;
}

/// Cancels one active upload. `cancel()` is idempotent; [whenCancelled]
/// completes once.
class UploadCancelToken {
  final Completer<void> _done = Completer<void>();

  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// The upload was cancelled through its [UploadCancelToken].
class UploadCancelled implements Exception {
  const UploadCancelled();
  @override
  String toString() => 'UploadCancelled';
}

/// The route answered something other than HTTP 200 (dsh: 400 without a
/// session id, 405, 415 for a content type other than
/// `application/octet-stream`, 401 for a dead Peer) or the connection failed.
class UploadTransportFailure extends RemoteException {
  UploadTransportFailure(int? status, String message)
    : status = status,
      super(
        status == HttpStatus.unauthorized
            ? 'transport/unauthorized'
            : 'transport/http-${status ?? 'io'}',
        message,
      );

  final int? status;
}

/// What a client needs to stage one file for a session. The real
/// implementation is [HttpFileUploadClient]; tests pass a fake transport.
abstract interface class FileUploadClient {
  /// Stream [data] to the host as one file of [sessionId]. [length] (when
  /// known) makes the request fixed-length so [onProgress] has a total.
  ///
  /// Throws [UploadCancelled] once [cancel] fires, [RemoteException] for a host
  /// refusal (`session/attachment-invalid`, `session/not-found`, ...) and
  /// [UploadTransportFailure] for transport failures.
  Future<FileUploadReceipt> upload({
    required String sessionId,
    required Stream<List<int>> data,
    int? length,
    String? name,
    UploadCancelToken? cancel,
    void Function(UploadProgress progress)? onProgress,
  });
}

/// `POST /api/session/uploadFileBinary?sessionId=&name=` with the body as raw
/// `application/octet-stream` bytes (dsh `file-upload` package: the route, its
/// JSON `{ok, value | error}` answer with HTTP 200, the 415/400 refusals).
///
/// Authentication is the paired API cookie of the live generation, read at the
/// start of each upload through [credential].
class HttpFileUploadClient implements FileUploadClient {
  HttpFileUploadClient({
    required PairedCredential? Function() credential,
    HttpClient? httpClient,
    HttpClient Function(Uri origin)? clientFor,
  }) : _credential = credential,
       _clientFor = clientFor,
       _http = httpClient ?? HttpClient();

  final PairedCredential? Function() _credential;
  final HttpClient Function(Uri origin)? _clientFor;
  final HttpClient _http;

  /// The route path (dsh `FILE_UPLOAD_PATH`).
  static const String path = '/api/session/uploadFileBinary';

  @override
  Future<FileUploadReceipt> upload({
    required String sessionId,
    required Stream<List<int>> data,
    int? length,
    String? name,
    UploadCancelToken? cancel,
    void Function(UploadProgress progress)? onProgress,
  }) async {
    final credential = _credential();
    if (credential == null) {
      throw RemoteException('connection/not-connected', 'no live generation');
    }
    if (cancel?.isCancelled ?? false) {
      throw const UploadCancelled();
    }
    final uri = credential.origin.replace(
      path: path,
      queryParameters: {'sessionId': sessionId, 'name': ?name},
    );
    HttpClientRequest? request;
    var cancelled = false;
    unawaited(
      cancel?.whenCancelled.then((_) {
        cancelled = true;
        request?.abort(const UploadCancelled());
      }),
    );
    try {
      request = await (_clientFor?.call(credential.origin) ?? _http).postUrl(
        uri,
      );
      if (cancelled) {
        throw const UploadCancelled();
      }
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..set(HttpHeaders.cookieHeader, credential.cookieHeader);
      if (length != null) request.contentLength = length;
      var loaded = 0;
      onProgress?.call(UploadProgress(0, length));
      await request.addStream(
        data.map((chunk) {
          loaded += chunk.length;
          // Reported as the chunk is handed to the socket; addStream awaits
          // the socket's drain before pulling the next chunk, so this tracks
          // what really left the device to within one buffer.
          onProgress?.call(UploadProgress(loaded, length));
          return chunk;
        }),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) {
        throw UploadTransportFailure(
          response.statusCode,
          'file upload transport failed with HTTP ${response.statusCode}',
        );
      }
      return _parse(body);
    } on UploadCancelled {
      rethrow;
    } on Object catch (e) {
      if (cancelled || (cancel?.isCancelled ?? false)) {
        throw const UploadCancelled();
      }
      if (e is RemoteException) rethrow;
      throw UploadTransportFailure(null, '$e');
    }
  }

  FileUploadReceipt _parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw RemoteException(
        'transport/bad-envelope',
        'file upload returned invalid JSON',
      );
    }
    if (decoded is! Map<String, Object?> || decoded['ok'] is! bool) {
      throw RemoteException(
        'transport/bad-envelope',
        'file upload returned an invalid result',
      );
    }
    if (decoded['ok'] == true) {
      return FileUploadReceipt.fromJson(decoded['value']);
    }
    final error = decoded['error'];
    if (error is Map<String, Object?> &&
        error['code'] is String &&
        error['message'] is String) {
      final details = error['details'];
      throw RemoteException(
        error['code']! as String,
        error['message']! as String,
        details is Map<String, Object?> ? details : const {},
      );
    }
    throw RemoteException(
      'transport/bad-envelope',
      'file upload returned an invalid failure',
    );
  }

  void close() => _http.close(force: true);
}
