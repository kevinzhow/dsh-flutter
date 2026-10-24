import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';

import 'platform/platform_services.dart';

/// Image dimensions without decoding the pixels: what the composer needs to
/// size a preview (dsh probes them off the preview URL).
Future<({int width, int height})?> probeImageSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (width: descriptor.width, height: descriptor.height);
  } on Object {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// The composer-side services of one session, as the features see them.
class _Attachments implements AttachmentServices {
  _Attachments(this.drafts, this.picker, this.acceptsDrops);

  @override
  final DraftAttachments drafts;
  @override
  final AttachmentPicker? picker;
  @override
  final bool acceptsDrops;

  final StreamController<List<LocalFile>> dropController =
      StreamController<List<LocalFile>>.broadcast();

  @override
  Stream<List<LocalFile>> get dropped => dropController.stream;
}

class _Files implements SessionFileServices {
  _Files(this.remote, this.actions);

  @override
  final WorkspaceFilesRemote remote;
  @override
  final HostFileActions? actions;
}

/// One open session: the model [Session], its conversation binding, and the
/// operations features may call. The app keeps one per session id while it is
/// resident, like dsh's `SessionManager` keeps its sessions.
class SessionController implements SessionActions {
  SessionController(
    this.session, {
    required FileUploadClient uploader,
    required WorkspaceFilesRemote files,
    PlatformServices platform = const PlatformServices(),
    FlushScheduler? scheduler,
    String? Function()? cwdReader,
    String hostHome = '',
    this.readOnly = false,
  }) : conversation = ConversationBinding.chat(
         session.eventSource,
         scheduler: scheduler,
       ) {
    // A transcript opened read-only takes no attachments but still opens files.
    _attachments = readOnly
        ? null
        : _Attachments(
            DraftAttachments(
              sessionId: session.sessionId,
              uploader: uploader,
              limits: () =>
                  ImageLimits.tryParse(session.projections.get('imageLimits')),
              probe: probeImageSize,
            ),
            platform.picker,
            platform.acceptsDrops,
          );
    owner = SessionOwner(
      session: session,
      conversation: conversation,
      actions: this,
      cwdReader: cwdReader,
      hostHome: hostHome,
      attachments: _attachments,
      textDraft: readOnly ? null : TextDraft(),
      files: _Files(files, platform.fileActions),
    );
  }

  /// A subagent transcript: nothing can be sent or cancelled.
  final bool readOnly;

  final Session session;
  final ConversationBinding conversation;
  late final SessionOwner owner;
  late final _Attachments? _attachments;

  String get sessionId => session.sessionId;

  /// Files dropped on the window go to this session's composer.
  void dropFiles(List<LocalFile> files) =>
      _attachments?.dropController.add(files);

  /// Start following the session (single flight).
  Future<void> open() => session.open();

  @override
  Future<void> send(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  }) => readOnly
      ? Future.value()
      : session.prompt(text.trim(), attachments: attachments);

  @override
  Future<void> cancel() => readOnly ? Future.value() : session.cancel();

  @override
  Future<void> loadOlder() => session.loadOlder();

  Future<void> dispose() async {
    await conversation.dispose();
    await _attachments?.drafts.dispose();
    await _attachments?.dropController.close();
  }
}
