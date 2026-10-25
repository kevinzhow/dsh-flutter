import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart' show WorkspaceFilesRemote;
import 'package:dsh_client/generated_workspace.dart' show WorkspaceView;
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
    String mode = 'queue',
  });

  /// Update a durable queue occurrence.
  Future<void> updateQueue(String itemId, Map<String, Object?> action);

  /// Cancel the active turn (`session/cancel`).
  Future<void> cancel();

  /// Read one older page into the window.
  Future<void> loadOlder();
}

/// The composer's draft, kept outside the composer widget: the widget goes
/// away when the session screen is left, or while the app shows the pairing
/// page after a host restart, and the draft (text, reference chips, a claimed
/// command) must still be there when it comes back (dsh web keeps composer
/// drafts per session, too).
class TextDraft {
  TextDraft({String sessionId = '', ComposerInput? input})
    : input = input ?? ComposerInput(sessionId: sessionId);

  /// The draft model: text with its reference chips, the submit machine and the
  /// trigger pipeline of this session.
  final ComposerInput input;

  /// The draft as plain text (reference chips expanded to their clipboard
  /// text). Writing replaces the whole draft.
  String get text => input.clipboardText;
  set text(String value) => input.setPlainText(value);
}

/// The tap-region group of one session's composer: the composer card and its
/// floating overlays (the candidate menu, the command popup) share it, so a
/// press inside any of them is not "outside" for the others (dsh's `[data-
/// composer-card]` containment test).
Object composerTapGroup(String sessionId) => ('composer-card', sessionId);

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
    this.blankReader,
    this.hostHome = '',
    this.attachments,
    this.files,
    this.textDraft,
    this.queueMutable = true,
  });

  /// The composer's unsent draft; null where the composer keeps none.
  final TextDraft? textDraft;

  /// The composer model (draft chips, submit machine, trigger pipeline).
  ComposerInput? get input => textDraft?.input;

  /// The composer's attachment drafts and the platform pickers; null where a
  /// session takes no attachments (a read-only subagent transcript).
  final AttachmentServices? attachments;

  /// Workspace files of this session and what the host platform can do with a
  /// file; null for a transcript that opens none.
  final SessionFileServices? files;

  final Session session;
  final ConversationBinding conversation;
  final SessionActions actions;
  final bool queueMutable;

  /// Reads the session workspace root (known once the session list carries it).
  final String? Function()? cwdReader;

  /// Whether the session list already proves this session blank (the hero can
  /// show before the session itself is open); null while the list does not
  /// carry it.
  final bool? Function()? blankReader;

  /// The host account home, used only to abbreviate displayed paths.
  final String hostHome;

  /// The session workspace root, when known.
  String? get cwd => cwdReader?.call();

  /// What the session list says about this session being blank.
  bool? get summaryBlank => blankReader?.call();

  String get sessionId => session.sessionId;
}

/// Input-owned locked state of the plan control.
class PlanInputOwner {
  const PlanInputOwner(this.session, {this.locked = false});
  final SessionOwner session;
  final bool locked;
}

/// Data needed to open the exact plan under review, without coupling the
/// question domain's pending-answer lifecycle to a preview implementation.
class PlanReviewOwner {
  const PlanReviewOwner({
    required this.session,
    required this.requestKey,
    required this.markdown,
    this.callId,
  });
  final SessionOwner session;
  final String requestKey, markdown;
  final String? callId;
}

/// Owner props of the keyed `conversation.chat.node` slot: one chat node to
/// render, keyed by its kind (`user`, `assistant-step`, `tool-call`, ...).
class ChatNodeOwner {
  const ChatNodeOwner({
    required this.session,
    required this.node,
    required this.snapshot,
    this.groupPart,
    this.reasoningPreview = true,
    this.turnProcess,
  });

  final SessionOwner session;
  final ViewNode node;
  final ChatSnapshot snapshot;
  final String? groupPart;
  final bool reasoningPreview;
  final TurnProcessControls? turnProcess;
}

/// Session-owned disclosure state passed through the keyed Node seat.
class TurnProcessControls {
  const TurnProcessControls({
    required this.open,
    required this.foldable,
    required this.hasContent,
    required this.setOpen,
  });
  final bool open, foldable, hasContent;
  final void Function(bool) setOpen;
}

/// Command-name specialization at `conversation.chat.commandview`.
class CommandViewOwner {
  const CommandViewOwner({required this.session, required this.command});
  final SessionOwner session;
  final CommandData command;
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
  const ToolHostActions({
    this.openUrl,
    this.openFile,
    this.openSubagent,
    this.revealQuestion,
  });

  /// Put one `ask_user_question` call's answer panel back in the composer (dsh
  /// `userQuestionPanels.reveal`); false when no panel is there to show.
  final bool Function(SessionOwner parent, String callId)? revealQuestion;

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
/// plugins; features see only picked [LocalFile]s.
abstract interface class AttachmentPicker {
  /// The sources this platform offers, in menu order.
  List<AttachSource> get sources;

  /// Let the person pick from [source]. An empty list means cancelled.
  Future<List<LocalFile>> pick(AttachSource source);
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
  Stream<List<LocalFile>> get dropped;
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

/// Owner props of the keyed `sidebar.right.pane.tab` slot (and of its title):
/// one tab.
class SidebarTabOwner {
  const SidebarTabOwner({
    required this.session,
    required this.kind,
    required this.contentId,
    required this.actions,
    this.id = '',
    this.params = const {},
    this.line,
    this.revision = 0,
    this.visible = true,
  });

  final SessionOwner session;

  /// The tab kind (`files`, `text`, `terminal`).
  final String kind;

  /// The tab's identity within its session's sidebar (stable while it is open).
  final String id;

  /// The content address (`dsh-resource://file/session/<id>/<path>` for a
  /// file tab; `sidebar://terminal/<n>` for a terminal).
  final String contentId;

  /// What the opener passed (`{shellPath}` for a terminal chosen on the guide).
  final Map<String, Object?> params;

  /// The 1-based line a navigation asked for, if any, and the navigation's
  /// revision: it changes each time the same tab is navigated to again, so a
  /// body can answer a new request for the same line.
  final int? line;
  final int revision;

  /// Whether the tab is the one in front (a body kept mounted behind another
  /// tab is not visible).
  final bool visible;

  final SidebarTabActions actions;
}

/// What a tab body may ask of the sidebar that holds it (dsh `tab.actions`).
abstract interface class SidebarTabActions {
  /// Open another resource in the sidebar; a file address opens a preview tab.
  void openResource(String address, {int? line});

  /// Open a page of [kind] (dsh `openTab`); [replaceTab] closes the tab named
  /// by [replaceTabId] (the guide that offered it) and takes its place.
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  });
}

/// Owner props of the keyed `sidebar.right.tab.guide.entry` slot: the card of
/// one tab type on the guide page.
class SidebarGuideOwner {
  const SidebarGuideOwner({
    required this.session,
    required this.kind,
    required this.tabId,
    required this.actions,
  });

  final SessionOwner session;
  final String kind;

  /// The guide tab that shows the card (the one an opened page replaces).
  final String tabId;
  final SidebarTabActions actions;
}

/// The window width from which a session shows its right sidebar beside the
/// conversation; narrower windows present it as a sheet (phones).
const double sidebarInlineMinWindowWidth = 1100;

/// Width of the inline right sidebar.
const double sidebarInlineWidth = 400;

/// Owner props of the root-scoped settings slots (`settings.section`,
/// `settings.general.item`, `plugins.item`): the surface supplies nothing, an
/// occupant draws its own copy and owns its write path, as in dsh.
class SettingsOwner {
  const SettingsOwner();
}

/// What the workspace surfaces ask of the composition root (dsh's
/// `ctx.workspaces` list and `ctx.uiWorkspace` navigation).
abstract interface class WorkspaceServices {
  /// The Host's workspaces, live.
  Observable<WorkspaceSnapshot> get workspaces;

  /// Adopt an existing host directory as a workspace (`workspace/create`);
  /// rejects with the Host's failure (`workspace/invalid-path`).
  Future<WorkspaceView> createWorkspace(String path);

  /// "New session": a fresh session in [workspaceId], else in the workspace of
  /// the session in view, else in the most recent workspace; with none to
  /// choose from the conversation area shows the workspace chooser. Throws
  /// what the Host refused with.
  Future<void> startSession([String? workspaceId]);

  /// A workspace was picked for the conversation being prepared: its first
  /// reusable blank session opens (else a new one), and the draft of [from]
  /// moves over. Throws what the Host refused with.
  Future<void> openWorkspace(String workspaceId, {String? from});
}

/// Owner props of `conversation.hero.workspace` (dsh `EmptyWorkspaceOwnerProps`):
/// the picker the blank-session hero shows under its workspace chip.
class HeroWorkspaceOwner {
  const HeroWorkspaceOwner({
    required this.open,
    required this.onPick,
    required this.onClose,
    this.selectedId,
    this.anchor,
  });

  /// The chip asked for the picker.
  final bool open;

  /// The workspace the blank session belongs to (the trailing check).
  final String? selectedId;

  /// A real workspace was picked or adopted.
  final void Function(String workspaceId) onPick;

  /// Close the picker (outside tap, Escape, after a pick).
  final void Function() onClose;

  /// What the picker anchors to on a wide window (the owner's chip link; the
  /// slot registry knows no widget types).
  final Object? anchor;
}

/// Owner props of the two directory-flow holes (dsh `DirectoryFlowOwnerProps`):
/// the whole conversation between the surface that offers "Add workspace" and
/// the picking interaction. The occupant reads [open] to run its interaction
/// and reports exactly one outcome per open.
class DirectoryFlowOwner {
  const DirectoryFlowOwner({
    required this.open,
    required this.busy,
    required this.onPicked,
    required this.onCancel,
    required this.onError,
  });

  /// A picking interaction is requested; flipping back to false withdraws it.
  final bool open;

  /// The owner is adopting a picked path: occupants disable their commit
  /// affordances.
  final bool busy;

  /// The operator picked a directory (an absolute host path).
  final void Function(String path) onPicked;

  /// The operator dismissed the interaction.
  final void Function() onCancel;

  /// The interaction itself failed (listing denied); the owner shows its error
  /// surface.
  final void Function(String message) onError;
}

/// Owner props of `sidebar.workspaces`: the add-workspace action of the
/// session list.
class SidebarWorkspacesOwner {
  const SidebarWorkspacesOwner({required this.onStarted});

  /// A workspace was adopted and its session opened.
  final void Function() onStarted;
}
