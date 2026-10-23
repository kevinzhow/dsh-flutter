import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart' show WorkspaceFilesRemote;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';

/// Operations a session view can ask of the composition root. Features never
/// reach the connection themselves; they call these injected services.
abstract interface class SessionActions {
  /// Send a prompt (`session/prompt`); rejects when the host refuses it.
  /// [attachments] are the frozen composer drafts (images inline, files by
  /// receipt) and go before the text.
  Future<void> send(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  });

  /// Cancel the active turn (`session/cancel`).
  Future<void> cancel();

  /// Read one older page into the window.
  Future<void> loadOlder();
}

/// Owner props of the session-scoped slots (`conversation.session`,
/// `conversation.header`, `conversation.view`, `conversation.composer`, ...):
/// the one open session and what is derived from it. dsh declares these owner
/// types in the owning `ui-*` packages; here they live below the features so
/// no feature has to import another to fill a slot.
class SessionOwner {
  const SessionOwner({
    required this.session,
    required this.conversation,
    required this.actions,
    this.cwdReader,
    this.hostHome = '',
    this.attachments,
    this.files,
  });

  /// The composer's attachment drafts and the platform pickers; null where a
  /// session takes no attachments (a read-only subagent transcript).
  final AttachmentServices? attachments;

  /// Workspace files of this session and what the host platform can do with a
  /// file; null for a transcript that opens none.
  final SessionFileServices? files;

  final Session session;
  final ConversationBinding conversation;
  final SessionActions actions;

  /// Reads the session workspace root (known once the session list carries it).
  final String? Function()? cwdReader;

  /// The host account home, used only to abbreviate displayed paths.
  final String hostHome;

  /// The session workspace root, when known.
  String? get cwd => cwdReader?.call();

  String get sessionId => session.sessionId;
}

/// Owner props of the keyed `conversation.chat.node` slot: one chat node to
/// render, keyed by its kind (`user`, `assistant-step`, `tool-call`, ...).
class ChatNodeOwner {
  const ChatNodeOwner({
    required this.session,
    required this.node,
    required this.snapshot,
  });

  final SessionOwner session;
  final ViewNode node;
  final ChatSnapshot snapshot;
}

/// Owner props of the keyed `tool.call.toolview` slot: one tool call to render,
/// keyed by its wire tool name. Tool-specific views occupy it; the generic card
/// renders when no entry matches.
class ToolViewOwner {
  const ToolViewOwner({required this.session, required this.call});
  final SessionOwner session;
  final ToolCall call;
}

/// What the host platform lets a tool view open. Both are optional: a
/// composition without a file preview shows paths as plain text, one without a
/// browser launcher shows URLs unlinked.
class ToolHostActions {
  const ToolHostActions({this.openUrl, this.openFile, this.openSubagent});

  /// Open one direct subagent child's read-only transcript. [parent] is the
  /// session the tool row belongs to; the receiver resolves the child's mode
  /// from the parent's subagent catalog.
  final void Function(SessionOwner parent, String childId)? openSubagent;

  /// Open an http(s) URL in the system browser.
  final void Function(Uri url)? openUrl;

  /// Open a workspace file at an optional 1-based line.
  final void Function(String path, {int? line})? openFile;
}

/// Owner props of `conversation.chat.turnTail`: one finished or running turn's
/// closing area (submitted plans, file deliveries). Entries read what they
/// need from the chat snapshot.
class TurnTailOwner {
  const TurnTailOwner({
    required this.session,
    required this.turn,
    required this.snapshot,
  });

  final SessionOwner session;
  final int turn;
  final ChatSnapshot snapshot;
}

/// A source the composer's attach control offers (phones: photo library,
/// camera, files; desktop: files).
enum AttachSource { photos, camera, files }

/// Platform picking, implemented by the composition root with the platform
/// plugins; features see only picked [PickedFile]s.
abstract interface class AttachmentPicker {
  /// The sources this platform offers, in menu order.
  List<AttachSource> get sources;

  /// Let the person pick from [source]. An empty list means cancelled.
  Future<List<PickedFile>> pick(AttachSource source);
}

/// What the attachment surfaces need from a session (dsh `ui-conversation`'s
/// draft registry and file-upload service).
abstract interface class AttachmentServices {
  /// The composer drafts of this session; they survive leaving the session.
  DraftAttachments get drafts;

  /// Null on platforms without pickers (tests).
  AttachmentPicker? get picker;

  /// Whether a dropped file may be added now (desktop drop target).
  bool get acceptsDrops;

  /// Files dropped on the window; the composer adds them like picked ones.
  Stream<List<PickedFile>> get dropped;
}

/// One image of a gallery: a durable reference, or the local preview of a
/// message that is still being admitted.
sealed class GalleryImage {
  const GalleryImage();
}

final class DurableGalleryImage extends GalleryImage {
  const DurableGalleryImage(this.image, {this.label});
  final ImageRef image;

  /// Presentation-only name for the thumbnail and lightbox.
  final String? label;
}

final class PreviewGalleryImage extends GalleryImage {
  const PreviewGalleryImage(this.bytes, {this.name, this.width, this.height});
  final Uint8List bytes;
  final String? name;
  final int? width;
  final int? height;
}

/// Owner props of the image-group slots (`conversation.chat.user.images`,
/// `conversation.chat.message.images`, `tool.call.images`).
class ImageGalleryOwner {
  const ImageGalleryOwner({
    required this.session,
    required this.images,
    this.alignEnd = false,
    this.compact = false,
    this.thumbnail = false,
    this.group,
    this.groupIndex = 0,
  });

  final SessionOwner session;
  final List<GalleryImage> images;

  /// All images of the message these belong to, when the message renders its
  /// images one slot call at a time (dsh does): the lightbox pages through
  /// them. [groupIndex] is where [images] starts in the group.
  final List<GalleryImage>? group;
  final int groupIndex;

  /// Right-aligned (user messages).
  final bool alignEnd;

  /// Every image a fixed square tile.
  final bool compact;

  /// Fixed, uncropped thumbnail for a list row.
  final bool thumbnail;
}

/// Workspace files of one session, plus the platform's file handling.
abstract interface class SessionFileServices {
  WorkspaceFilesRemote get remote;

  /// Null when the platform can neither open nor save a file.
  HostFileActions? get actions;
}

/// Receives a file's bytes in order; used to download a file to the device
/// before handing it to the system.
abstract interface class HostFileSink {
  Future<void> add(Uint8List bytes);

  /// Close the file; after this it can be opened or saved.
  Future<void> finish();

  /// Hand the downloaded file to the system's viewer.
  Future<bool> open();

  /// Let the person save a copy somewhere (share sheet or save dialog).
  Future<bool> save();

  /// Delete the temporary file.
  Future<void> discard();
}

/// What the host platform can do with a file.
abstract interface class HostFileActions {
  bool get canOpen;
  bool get canSave;

  /// Start a download of a file named [name].
  Future<HostFileSink> begin(String name);
}

/// Owner props of the keyed `sidebar.right.pane.tab` slot: one tab's body.
class SidebarTabOwner {
  const SidebarTabOwner({
    required this.session,
    required this.kind,
    required this.contentId,
    required this.actions,
    this.line,
    this.revision = 0,
  });

  final SessionOwner session;

  /// The tab kind (`files`, `text`).
  final String kind;

  /// The content address (`dsh-resource://file/session/<id>/<path>` for a
  /// file tab).
  final String contentId;

  /// The 1-based line a navigation asked for, if any, and the navigation's
  /// revision: it changes each time the same tab is navigated to again, so a
  /// body can answer a new request for the same line.
  final int? line;
  final int revision;

  final SidebarTabActions actions;
}

/// What a tab body may ask of the sidebar that holds it (dsh `tab.actions`).
abstract interface class SidebarTabActions {
  /// Open another resource in the sidebar; a file address opens a preview tab.
  void openResource(String address, {int? line});
}

/// The window width from which a session shows its right sidebar beside the
/// conversation; narrower windows present it as a sheet (phones).
const double sidebarInlineMinWindowWidth = 1100;

/// Width of the inline right sidebar.
const double sidebarInlineWidth = 400;
