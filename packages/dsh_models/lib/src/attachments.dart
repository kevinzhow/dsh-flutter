import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';

import 'observable.dart';
import 'session.dart' show OutgoingAttachment, OutgoingFile, OutgoingImage;

// ---------------------------------------------------------------------------
// Durable references (dsh `packages/attachment`)
// ---------------------------------------------------------------------------

/// The raster formats dsh admits (`ImageMediaType`); everything else is a file.
const List<String> imageMediaTypes = [
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
];

/// dsh `isImageMediaType`.
bool isImageMediaType(String? value) =>
    value != null && imageMediaTypes.contains(value);

/// The image media type of a file name, for pickers that report no MIME type.
String? imageMediaTypeOfName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => null,
  };
}

/// A durable image reference (dsh `ImageAttachmentRef`): what a user message,
/// an assistant message or a `read_image` result carries.
class ImageRef {
  const ImageRef({
    required this.attachmentId,
    required this.mediaType,
    required this.bytes,
    required this.width,
    required this.height,
    this.name,
  });

  /// Strict parse like ui-tool's `imageReferences`: any malformed field
  /// declines (null) so the caller falls back to a plain presentation.
  static ImageRef? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['attachmentId'];
    final type = json['mediaType'];
    final bytes = json['bytes'];
    final width = json['width'];
    final height = json['height'];
    final name = json['name'];
    if (id is! String || id.isEmpty) return null;
    if (type is! String || !isImageMediaType(type)) return null;
    if (bytes is! int || bytes <= 0 || width is! int || width <= 0) return null;
    if (height is! int || height <= 0) return null;
    if (name != null && name is! String) return null;
    return ImageRef(
      attachmentId: id,
      mediaType: type,
      bytes: bytes,
      width: width,
      height: height,
      name: name as String?,
    );
  }

  final String attachmentId;
  final String mediaType;
  final int bytes;
  final int width;
  final int height;
  final String? name;
}

/// A durable file reference (dsh `FileAttachmentRef`).
class FileRef {
  const FileRef({
    required this.attachmentId,
    required this.name,
    required this.bytes,
  });

  static FileRef? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['attachmentId'];
    final name = json['name'];
    final bytes = json['bytes'];
    if (id is! String || name is! String || bytes is! int || bytes < 0) {
      return null;
    }
    return FileRef(attachmentId: id, name: name, bytes: bytes);
  }

  final String attachmentId;
  final String name;
  final int bytes;
}

/// The deployment's image intake limits (the `imageLimits` projection, dsh
/// `ImageAttachmentLimits`).
class ImageLimits {
  const ImageLimits({
    required this.maxImageBytes,
    required this.maxImagesPerMessage,
    required this.maxMessageImageBytes,
    required this.maxImagePixels,
    required this.maxImageDimension,
    required this.mediaTypes,
  });

  static ImageLimits? tryParse(Object? json) {
    if (json is! Map) return null;
    int? n(String k) => json[k] is int ? json[k] as int : null;
    final types = json['mediaTypes'];
    final a = n('maxImageBytes');
    final b = n('maxImagesPerMessage');
    final c = n('maxMessageImageBytes');
    final d = n('maxImagePixels');
    final e = n('maxImageDimension');
    if (a == null ||
        b == null ||
        c == null ||
        d == null ||
        e == null ||
        types is! List) {
      return null;
    }
    return ImageLimits(
      maxImageBytes: a,
      maxImagesPerMessage: b,
      maxMessageImageBytes: c,
      maxImagePixels: d,
      maxImageDimension: e,
      mediaTypes: [for (final t in types) '$t'],
    );
  }

  final int maxImageBytes;
  final int maxImagesPerMessage;
  final int maxMessageImageBytes;
  final int maxImagePixels;
  final int maxImageDimension;
  final List<String> mediaTypes;
}

// ---------------------------------------------------------------------------
// Durable image bytes (dsh `HistoricalImageCache`)
// ---------------------------------------------------------------------------

/// Reads durable images of one session: `session/attachment` answers JSON with
/// base64 data. Single flight per attachment, a failed read is not cached (the
/// retry control reads again), and the cache is bounded by bytes.
class SessionImages {
  SessionImages(
    this.sessionId,
    this._read, {
    this.maxCachedBytes = 96 * 1024 * 1024,
  });

  final String sessionId;
  final Future<Map<String, Object?>> Function(
    String sessionId,
    String attachmentId,
  )
  _read;
  final int maxCachedBytes;

  final LinkedHashMap<String, Future<Uint8List>> _entries = LinkedHashMap();
  final Map<String, int> _sizes = {};
  int _cached = 0;

  final Map<String, Uint8List> _settled = {};

  /// Bytes already in memory, without starting a read.
  Uint8List? peek(String attachmentId) => _settled[attachmentId];

  /// The durable bytes of [ref] (cached, or read once).
  Future<Uint8List> load(ImageRef ref) {
    final id = ref.attachmentId;
    final hit = _entries.remove(id);
    if (hit != null) {
      _entries[id] = hit; // most recently used
      return hit;
    }
    final future = _fetch(id);
    _entries[id] = future;
    future.then(
      (bytes) {
        if (!identical(_entries[id], future)) return;
        _settled[id] = bytes;
        _sizes[id] = bytes.length;
        _cached += bytes.length;
        _trim();
      },
      onError: (Object _) {
        if (identical(_entries[id], future)) _entries.remove(id);
      },
    );
    return future;
  }

  Future<Uint8List> _fetch(String attachmentId) async {
    final value = await _read(sessionId, attachmentId);
    final data = value['data'];
    if (data is Uint8List) return data;
    if (data is! String) {
      throw RemoteException(
        'transport/bad-envelope',
        'attachment read carried no data',
      );
    }
    return base64Decode(data);
  }

  void _trim() {
    while (_cached > maxCachedBytes && _entries.length > 1) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      _settled.remove(oldest);
      _cached -= _sizes.remove(oldest) ?? 0;
    }
  }

  void clear() {
    _entries.clear();
    _settled.clear();
    _sizes.clear();
    _cached = 0;
  }
}

// ---------------------------------------------------------------------------
// Draft attachments (dsh ui-conversation draft registry + file upload queue)
// ---------------------------------------------------------------------------

/// A file the platform picker, camera, drop target or clipboard produced. The
/// platform adapters (the app) build these; nothing here touches `dart:io`.
class LocalFile {
  LocalFile({
    required this.name,
    required this.size,
    this.mediaType,
    required this.open,
    required this.read,
  });

  /// Display name; may be empty.
  final String name;

  /// Exact byte length.
  final int size;

  /// The browser-style MIME type when the source knows it.
  final String? mediaType;

  /// A fresh byte stream (an upload retry opens it again).
  final Stream<List<int>> Function() open;

  /// The whole content (images are read at intake, like dsh sends them
  /// inline).
  final Future<Uint8List> Function() read;

  /// The image media type this file counts as, if any (dsh classifies by the
  /// declared MIME type; pickers without one are classified by extension).
  String? get imageType {
    if (isImageMediaType(mediaType)) return mediaType;
    if (mediaType == null || mediaType!.isEmpty) {
      return imageMediaTypeOfName(name);
    }
    return null;
  }
}

/// One unsent attachment in the composer.
sealed class DraftAttachment {
  const DraftAttachment(this.id, this.name, this.size);
  final String id;
  final String name;
  final int size;
}

/// An image draft: its bytes are held for the preview and for the inline
/// base64 of the prompt.
final class DraftImage extends DraftAttachment {
  const DraftImage(
    super.id,
    super.name,
    super.size, {
    required this.bytes,
    required this.mediaType,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String mediaType;
  final int? width;
  final int? height;
}

/// A generic file draft: uploaded in the background as soon as it is picked.
final class DraftFile extends DraftAttachment {
  const DraftFile(super.id, super.name, super.size, this.source);
  final LocalFile source;
}

/// Where one file draft's upload is (dsh `DraftFileUpload`).
sealed class FileUploadState {
  const FileUploadState();
}

final class FileUploading extends FileUploadState {
  const FileUploading(this.loaded, [this.total]);
  final int loaded;
  final int? total;

  /// 0..1 when the total is known and positive.
  double? get fraction =>
      total != null && total! > 0 ? (loaded / total!).clamp(0.0, 1.0) : null;
}

final class FileReady extends FileUploadState {
  const FileReady(this.receipt);
  final FileUploadReceipt receipt;
}

final class FileFailed extends FileUploadState {
  const FileFailed(this.error);

  /// The failure as thrown: a [RemoteException] (host refusal, with
  /// `details.reason`) or an [UploadTransportFailure].
  final Object error;
}

/// Why an addition was refused before any draft was created (dsh's intake
/// pre-check in `InputBar`): the copy names the limit.
enum IntakeRefusal { tooManyImages, imageTooLarge, imagesTooLarge }

/// The outcome of [DraftAttachments.add].
class IntakeResult {
  const IntakeResult.accepted(this.added) : refusal = null, limit = null;
  const IntakeResult.refused(IntakeRefusal this.refusal, int this.limit)
    : added = const [];

  /// The drafts created (empty when refused).
  final List<DraftAttachment> added;
  final IntakeRefusal? refusal;

  /// The limit the refusal names: a count, or a number of bytes.
  final int? limit;
}

/// An immutable view of the composer's attachments.
class DraftSnapshot {
  const DraftSnapshot(this.items, this.uploads);
  static const empty = DraftSnapshot([], {});

  final List<DraftAttachment> items;

  /// Upload state per [DraftFile] id.
  final Map<String, FileUploadState> uploads;

  bool get isEmpty => items.isEmpty;

  /// Every file draft finished uploading (dsh gates Send on this: an
  /// uploading or failed file holds it).
  bool get uploadsPending =>
      items.any((a) => a is DraftFile && uploads[a.id] is! FileReady);

  bool get hasFailedUpload =>
      items.any((a) => a is DraftFile && uploads[a.id] is FileFailed);
}

/// The composer's attachment drafts of one session: image intake with dsh's
/// limits, the FIFO background upload queue (default two at a time), retry,
/// removal that cancels an active or queued upload, and freezing the drafts
/// into [OutgoingAttachment]s at send.
class DraftAttachments {
  DraftAttachments({
    required this.sessionId,
    required FileUploadClient uploader,
    required ImageLimits? Function() limits,
    this.maxConcurrentUploads = 2,
    Future<({int width, int height})?> Function(Uint8List bytes)? probe,
  }) : _uploader = uploader,
       _limits = limits,
       _probe = probe;

  final String sessionId;
  final FileUploadClient _uploader;
  final ImageLimits? Function() _limits;
  final int maxConcurrentUploads;
  final Future<({int width, int height})?> Function(Uint8List bytes)? _probe;

  final Observable<DraftSnapshot> _state = Observable(DraftSnapshot.empty);
  final Map<String, UploadCancelToken> _tokens = {};
  final Queue<_QueuedUpload> _queue = Queue();
  int _active = 0;
  int _counter = 0;
  bool _disposed = false;

  Observable<DraftSnapshot> get state => _state;
  DraftSnapshot get value => _state.value;

  /// Add picked [files] in order. Images become image drafts (their bytes are
  /// read now); every other file becomes a file draft and starts uploading.
  /// The whole batch is checked first against the projected image limits: one
  /// violation refuses all of it (dsh `intakeFiles`).
  Future<IntakeResult> add(List<LocalFile> files) async {
    if (_disposed || files.isEmpty) return const IntakeResult.accepted([]);
    final limits = _limits();
    if (limits != null) {
      final images = files.where(
        (f) => f.imageType != null && limits.mediaTypes.contains(f.imageType),
      );
      final existing = value.items.whereType<DraftImage>();
      if (existing.length + images.length > limits.maxImagesPerMessage) {
        return IntakeResult.refused(
          IntakeRefusal.tooManyImages,
          limits.maxImagesPerMessage,
        );
      }
      if (images.any((f) => f.size > limits.maxImageBytes)) {
        return IntakeResult.refused(
          IntakeRefusal.imageTooLarge,
          limits.maxImageBytes,
        );
      }
      final total =
          existing.fold<int>(0, (n, a) => n + a.size) +
          images.fold<int>(0, (n, f) => n + f.size);
      if (total > limits.maxMessageImageBytes) {
        return IntakeResult.refused(
          IntakeRefusal.imagesTooLarge,
          limits.maxMessageImageBytes,
        );
      }
    }
    final added = <DraftAttachment>[];
    for (final file in files) {
      final type = file.imageType;
      if (type != null) {
        final bytes = await file.read();
        if (_disposed) return const IntakeResult.accepted([]);
        final dims = await _probe?.call(bytes);
        added.add(
          DraftImage(
            _nextId(),
            file.name,
            file.size,
            bytes: bytes,
            mediaType: type,
            width: dims?.width,
            height: dims?.height,
          ),
        );
      } else {
        added.add(DraftFile(_nextId(), file.name, file.size, file));
      }
    }
    if (_disposed) return const IntakeResult.accepted([]);
    _publish([...value.items, ...added], value.uploads);
    for (final a in added) {
      if (a is DraftFile) _begin(a);
    }
    return IntakeResult.accepted(added);
  }

  String _nextId() => 'draft-${++_counter}';

  /// Remove one draft: skips its queued upload or aborts the active one.
  void remove(String id) {
    final token = _tokens.remove(id);
    token?.cancel();
    _queue.removeWhere((q) => q.draft.id == id && (q.cancelled = true));
    final uploads = {...value.uploads}..remove(id);
    _publish(value.items.where((a) => a.id != id).toList(), uploads);
  }

  /// Restart one failed upload.
  void retry(String id) {
    final draft = value.items.whereType<DraftFile>().where((a) => a.id == id);
    if (draft.isEmpty || value.uploads[id] is! FileFailed) return;
    _begin(draft.first);
  }

  /// The drafts frozen for sending, in pick order. Throws [StateError] while an
  /// upload is unfinished (the composer gates Send on [DraftSnapshot]).
  List<OutgoingAttachment> freeze() {
    final snapshot = value;
    return [
      for (final a in snapshot.items)
        switch (a) {
          DraftImage() => OutgoingImage(
            name: a.name,
            bytes: a.bytes,
            mediaType: a.mediaType,
            width: a.width,
            height: a.height,
          ),
          DraftFile() => switch (snapshot.uploads[a.id]) {
            FileReady(:final receipt) => OutgoingFile(
              name: receipt.name.isEmpty ? a.name : receipt.name,
              size: receipt.bytes,
              receiptId: receipt.receiptId,
            ),
            _ => throw StateError(
              'file "${a.name}" has not finished uploading',
            ),
          },
        },
    ];
  }

  /// Forget every draft after a send was accepted (no upload is active then:
  /// sending waits for them).
  void clear() {
    for (final t in _tokens.values) {
      t.cancel();
    }
    _tokens.clear();
    for (final q in _queue) {
      q.cancelled = true;
    }
    _queue.clear();
    _publish(const [], const {});
  }

  void _begin(DraftFile draft) {
    _tokens.remove(draft.id)?.cancel();
    final token = UploadCancelToken();
    _tokens[draft.id] = token;
    _setUpload(draft.id, const FileUploading(0));
    _queue.add(_QueuedUpload(draft, token));
    _pump();
  }

  void _pump() {
    while (_active < maxConcurrentUploads && _queue.isNotEmpty) {
      final next = _queue.removeFirst();
      if (next.cancelled || next.token.isCancelled) continue;
      _active++;
      unawaited(
        _run(next).whenComplete(() {
          _active--;
          _pump();
        }),
      );
    }
  }

  Future<void> _run(_QueuedUpload job) async {
    final draft = job.draft;
    bool current() => !_disposed && identical(_tokens[draft.id], job.token);
    try {
      final receipt = await _uploader.upload(
        sessionId: sessionId,
        data: draft.source.open(),
        length: draft.source.size,
        name: draft.name.isEmpty ? null : draft.name,
        cancel: job.token,
        onProgress: (p) {
          if (current()) _setUpload(draft.id, FileUploading(p.loaded, p.total));
        },
      );
      if (current()) _setUpload(draft.id, FileReady(receipt));
    } on UploadCancelled {
      // Removed or superseded: nothing to show.
    } on Object catch (e) {
      if (current()) _setUpload(draft.id, FileFailed(e));
    } finally {
      if (identical(_tokens[draft.id], job.token)) _tokens.remove(draft.id);
    }
  }

  void _setUpload(String id, FileUploadState state) {
    if (_disposed || !value.items.any((a) => a.id == id)) return;
    _publish(value.items, {...value.uploads, id: state});
  }

  void _publish(List<DraftAttachment> items, Map<String, FileUploadState> up) {
    if (_disposed) return;
    _state.set(DraftSnapshot(List.unmodifiable(items), Map.unmodifiable(up)));
  }

  /// Cancel everything; the drafts are dropped.
  Future<void> dispose() async {
    if (_disposed) return;
    for (final t in _tokens.values) {
      t.cancel();
    }
    _tokens.clear();
    for (final q in _queue) {
      q.cancelled = true;
    }
    _queue.clear();
    _disposed = true;
    await _state.dispose();
  }
}

class _QueuedUpload {
  _QueuedUpload(this.draft, this.token);
  final DraftFile draft;
  final UploadCancelToken token;
  bool cancelled = false;
}

/// The `details.reason` code of a host attachment refusal
/// (`session/attachment-invalid`, `subagent/attachment-invalid`), if [error]
/// is one.
String? attachmentRefusalReason(Object error) {
  if (error is RemoteException &&
      (error.code == 'session/attachment-invalid' ||
          error.code == 'subagent/attachment-invalid')) {
    final reason = error.details['reason'];
    return reason is String ? reason : '';
  }
  return null;
}
