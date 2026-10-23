/// Test support for features: a [SessionOwner] over an in-memory session.
/// Import only from tests.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';

import 'dsh_slots.dart';

export 'package:dsh_models/testing.dart' show FakeTransport;

/// Recording [SessionActions] for tests.
class FakeActions implements SessionActions {
  final List<String> sent = [];
  final List<List<OutgoingAttachment>> sentAttachments = [];
  int cancels = 0;
  int olderLoads = 0;
  Object? failSend;

  @override
  Future<void> send(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  }) async {
    if (failSend != null) throw failSend!;
    sent.add(text);
    sentAttachments.add(attachments);
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> loadOlder() async => olderLoads++;
}

/// An owner over a Session that never talks to a host. Feed it events through
/// `owner.session.eventSource` (replace/append/...); the chat snapshot follows
/// synchronously.
SessionOwner testSessionOwner(
  String sessionId, {
  SessionActions? actions,
  Session? session,
  AttachmentServices? attachments,
  SessionFileServices? files,
}) {
  final s = session ?? Session(sessionId, FakeTransport());
  return SessionOwner(
    session: s,
    conversation: ConversationBinding.chat(
      s.eventSource,
      scheduler: FlushScheduler.immediate(),
    ),
    actions: actions ?? FakeActions(),
    attachments: attachments,
    files: files,
  );
}

/// [AttachmentServices] over a caller-provided [DraftAttachments] and picker.
class FakeAttachmentServices implements AttachmentServices {
  FakeAttachmentServices(this.drafts, {this.picker, this.acceptsDrops = true});

  final StreamController<List<LocalFile>> dropController =
      StreamController<List<LocalFile>>.broadcast();

  @override
  Stream<List<LocalFile>> get dropped => dropController.stream;

  @override
  final DraftAttachments drafts;
  @override
  final AttachmentPicker? picker;
  @override
  final bool acceptsDrops;
}

/// A picker that returns scripted files.
class FakePicker implements AttachmentPicker {
  FakePicker({
    this.sources = const [AttachSource.photos, AttachSource.files],
    this.result = const [],
  });

  @override
  final List<AttachSource> sources;
  List<LocalFile> result;
  final List<AttachSource> picked = [];

  @override
  Future<List<LocalFile>> pick(AttachSource source) async {
    picked.add(source);
    return result;
  }
}

/// An uploader whose calls the test completes by hand.
class FakeUploadClient implements FileUploadClient {
  final List<FakeUpload> calls = [];

  @override
  Future<FileUploadReceipt> upload({
    required String sessionId,
    required Stream<List<int>> data,
    int? length,
    String? name,
    UploadCancelToken? cancel,
    void Function(UploadProgress progress)? onProgress,
  }) {
    final call = FakeUpload(sessionId, name, length, cancel, onProgress);
    calls.add(call);
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (!call.done.isCompleted) {
          call.done.completeError(const UploadCancelled());
        }
      }),
    );
    return call.done.future;
  }
}

class FakeUpload {
  FakeUpload(
    this.sessionId,
    this.name,
    this.length,
    this.cancel,
    this.onProgress,
  );
  final String sessionId;
  final String? name;
  final int? length;
  final UploadCancelToken? cancel;
  final void Function(UploadProgress)? onProgress;
  final Completer<FileUploadReceipt> done = Completer();

  void progress(int loaded) => onProgress?.call(UploadProgress(loaded, length));

  void succeed({String receipt = 'rcpt'}) => done.complete(
    FileUploadReceipt(
      receiptId: receipt,
      attachmentId: 'sha256:$receipt',
      name: name ?? 'file',
      bytes: length ?? 0,
    ),
  );

  void fail(Object error) => done.completeError(error);
}

/// A [LocalFile] over in-memory bytes.
LocalFile pickedBytes(String name, Uint8List bytes, {String? type}) =>
    LocalFile(
      name: name,
      size: bytes.length,
      mediaType: type,
      open: () => Stream.value(bytes),
      read: () async => bytes,
    );

/// A scripted [WorkspaceFilesRemote]: the maps answer by path.
class FakeWorkspaceFiles implements WorkspaceFilesRemote {
  /// Directory listings by path (the workspace root is both `.` and the cwd).
  final Map<String, Object> listings = {};

  /// Text files by path.
  final Map<String, String> texts = {};

  /// Binary files by path.
  final Map<String, Uint8List> binaries = {};

  /// Paths that fail with a code.
  final Map<String, RemoteException> failures = {};

  final List<String> calls = [];
  final Map<String, StreamController<WorkspaceWatchEvent>> watches = {};
  int pageLines = 5000;
  String root = '/work/project';

  Never _fail(String path) => throw failures[path]!;

  String _abs(String path) => path.startsWith('/') ? path : '$root/$path';

  @override
  Future<WorkspaceFileStat> stat(String sessionId, String path) async {
    calls.add('stat $path');
    if (failures.containsKey(path)) _fail(path);
    final size = texts[path]?.length ?? binaries[path]?.length;
    if (size == null) {
      throw RemoteException('workspace-file/not-found', 'no entry', {
        'path': path,
      });
    }
    return WorkspaceFileStat(
      absolutePath: _abs(path),
      version: 'v1',
      bytes: size,
    );
  }

  @override
  Future<WorkspaceFileText> read(
    String sessionId,
    String path, {
    int? offset,
    int? limit,
  }) async {
    calls.add('read $path ${offset ?? 1}');
    if (failures.containsKey(path)) _fail(path);
    final text = texts[path];
    if (text == null) {
      if (binaries.containsKey(path)) {
        throw RemoteException('workspace-file/not-text', 'not text', {
          'path': path,
        });
      }
      throw RemoteException('workspace-file/not-found', 'no entry', {
        'path': path,
      });
    }
    final lines = text.split('\n');
    final start = (offset ?? 1) - 1;
    final take = limit ?? pageLines;
    final page = start >= lines.length
        ? const <String>[]
        : lines.sublist(start, (start + take).clamp(0, lines.length));
    return WorkspaceFileText(
      absolutePath: _abs(path),
      version: 'v1',
      bytes: text.length,
      offset: start + 1,
      text: page.join('\n'),
      lines: page.length,
      eof: start + page.length >= lines.length,
    );
  }

  @override
  Future<WorkspaceFileBytes> readBytes(
    String sessionId,
    String path, {
    ByteRange? range,
    String? baseFile,
  }) async {
    calls.add('readBytes $path ${range?.offset ?? 0}');
    if (failures.containsKey(path)) _fail(path);
    final data =
        binaries[path] ??
        (texts[path] != null
            ? Uint8List.fromList(texts[path]!.codeUnits)
            : null);
    if (data == null) {
      throw RemoteException('workspace-file/not-found', 'no entry', {
        'path': path,
      });
    }
    final offset = range?.offset ?? 0;
    final end = range?.length == null
        ? data.length
        : (offset + range!.length!).clamp(0, data.length);
    return WorkspaceFileBytes(
      absolutePath: _abs(path),
      version: 'v1',
      bytes: data.length,
      offset: offset,
      data: Uint8List.sublistView(data, offset.clamp(0, data.length), end),
      eof: end >= data.length,
    );
  }

  @override
  Future<WorkspaceDirectoryListing> list(String sessionId, String path) async {
    calls.add('list $path');
    if (failures.containsKey(path)) _fail(path);
    final key = path == root ? '.' : path;
    final listing = listings[key];
    if (listing == null) {
      throw RemoteException('workspace-file/not-found', 'no entry', {
        'path': path,
      });
    }
    if (listing is WorkspaceDirectoryListing) return listing;
    return WorkspaceDirectoryListing(
      path: key == '.' ? '' : key,
      entries: listing as List<WorkspaceDirectoryEntry>,
      truncated: false,
    );
  }

  @override
  Stream<WorkspaceWatchEvent> changes(String sessionId, String path) {
    calls.add('changes $path');
    return (watches[path] ??= StreamController.broadcast()).stream;
  }
}

/// [SessionFileServices] over scripted parts.
class FakeFileServices implements SessionFileServices {
  FakeFileServices(this.remote, {this.actions});
  @override
  final WorkspaceFilesRemote remote;
  @override
  final HostFileActions? actions;
}

/// A [HostFileActions] that records what was opened or saved.
class FakeHostFileActions implements HostFileActions {
  FakeHostFileActions({this.canOpen = true, this.canSave = true});

  @override
  final bool canOpen;
  @override
  final bool canSave;
  final List<String> began = [];
  final List<String> opened = [];
  final List<String> saved = [];
  final Map<String, BytesBuilder> content = {};

  @override
  Future<HostFileSink> begin(String name) async {
    began.add(name);
    final builder = content[name] = BytesBuilder();
    return _Sink(this, name, builder);
  }
}

class _Sink implements HostFileSink {
  _Sink(this.owner, this.name, this.builder);
  final FakeHostFileActions owner;
  final String name;
  final BytesBuilder builder;

  @override
  Future<void> add(Uint8List bytes) async => builder.add(bytes);
  @override
  Future<void> finish() async {}
  @override
  Future<bool> open() async {
    owner.opened.add(name);
    return true;
  }

  @override
  Future<bool> save() async {
    owner.saved.add(name);
    return true;
  }

  @override
  Future<void> discard() async {}
}
