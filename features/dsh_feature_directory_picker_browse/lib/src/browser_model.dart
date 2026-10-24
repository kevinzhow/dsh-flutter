import 'dart:async';

import 'package:dsh_client/generated_directory_picker.dart'
    show DirectoryEntry, DirectoryListing;
import 'package:dsh_conversation/dsh_conversation.dart'
    show AbortController, AbortSignal;
import 'package:dsh_models/dsh_models.dart' show Observable;

/// How long a scan may stay visually silent before the floating "Loading..."
/// pill appears (dsh `SLOW_SCAN_DELAY_MS`).
const Duration slowScanDelay = Duration(milliseconds: 300);

/// How long a navigation landing waits for its parent leg before committing
/// the target alone (dsh `PARENT_LEG_WAIT_MS`).
const Duration parentLegWait = Duration(milliseconds: 200);

/// How long a typed draft rests before the panes follow it to a directory no
/// pane lists (dsh `DRAFT_PREVIEW_DEBOUNCE_MS`).
const Duration draftPreviewDebounce = Duration(milliseconds: 250);

/// List one directory level (an absent path lists the Host home); [signal]
/// aborts a superseded scan.
typedef ListDirectory = Future<DirectoryListing> Function(
  String? path,
  AbortSignal signal,
);

/// Create one child directory; answers its absolute path.
typedef CreateDirectory = Future<String> Function(String path, String name);

/// The failure text of an injected directory operation: the Host's business
/// message when it carries one, else the error's own text (dsh `failureText`).
typedef FailureText = String Function(Object error);

/// Breadcrumb rows for display: inside the home subtree the chain starts at a
/// localized Home crumb; outside it the full ancestry shows (dsh
/// `displayCrumbs`).
List<DirectoryEntry> displayCrumbs(DirectoryListing listing, String homeLabel) {
  final homeIndex = listing.crumbs.indexWhere((c) => c.path == listing.home);
  if (homeIndex == -1) return listing.crumbs;
  return [
    DirectoryEntry(name: homeLabel, path: listing.home, hidden: false),
    ...listing.crumbs.skip(homeIndex + 1),
  ];
}

/// The listing's platform separator, inferred from the home path the host
/// stamped (dsh `separatorOf`).
String separatorOf(DirectoryListing listing) =>
    listing.home.contains(r'\') ? r'\' : '/';

/// The listed level as a directory part: its own path, separator-terminated.
String levelDirectory(DirectoryListing listing) {
  final sep = separatorOf(listing);
  return listing.path.endsWith(sep) ? listing.path : '${listing.path}$sep';
}

/// The draft's directory part (through its last separator), or null while no
/// separator has been typed (dsh `draftDirectory`).
String? draftDirectory(DirectoryListing listing, String draft) {
  final cut = separatorOf(listing) == r'\'
      ? [
          draft.lastIndexOf(r'\'),
          draft.lastIndexOf('/'),
        ].reduce((a, b) => a > b ? a : b)
      : draft.lastIndexOf('/');
  return cut == -1 ? null : draft.substring(0, cut + 1);
}

/// The directory text a draft-following scan last sent, and the level path the
/// host answered it with.
class ScannedDirectory {
  const ScannedDirectory(this.directory, this.landed);
  final String directory;
  final String landed;
}

/// How the draft reads against one level (dsh `readDraft`): the directory part
/// it names, and, when [listing] is the level that directory addresses, the
/// final segment that prefix-filters it.
({String? directory, String? tail}) readDraft(
  DirectoryListing listing,
  String draft,
  ScannedDirectory? scanned,
) {
  final directory = draftDirectory(listing, draft);
  if (directory == null) return (directory: null, tail: null);
  final answers =
      directory == levelDirectory(listing) ||
      (scanned != null &&
          scanned.directory == directory &&
          scanned.landed == listing.path);
  return (
    directory: directory,
    tail: answers ? draft.substring(directory.length) : null,
  );
}

/// The rows one column renders (dsh `visibleEntries`). The selection is exempt
/// from every filter; a prefix narrows the level only while some displayable
/// row matches.
List<DirectoryEntry> visibleEntries(
  List<DirectoryEntry> entries,
  String? selectedPath,
  bool showHidden,
  String? filterPrefix,
) {
  final needle = filterPrefix?.toLowerCase() ?? '';
  bool displayable(DirectoryEntry e) =>
      showHidden || !e.hidden || needle.startsWith('.');
  bool matches(DirectoryEntry e) =>
      displayable(e) && e.name.toLowerCase().startsWith(needle);
  final narrowing = needle.isNotEmpty && entries.any(matches);
  return [
    for (final e in entries)
      if (e.path == selectedPath)
        e
      else if (narrowing)
        if (matches(e)) e else ...const <DirectoryEntry>[]
      else if (showHidden || !e.hidden)
        e,
  ];
}

/// The directory browser's state (dsh `DirectoryBrowser`, without the view).
class BrowserState {
  const BrowserState({
    this.parent,
    this.selected,
    this.child,
    this.loading = false,
    this.slowScan = false,
    this.error,
    this.pathDraft,
    this.showHidden = false,
    this.folderDraft,
    this.creatingFolder = false,
    this.createError,
  });

  /// The listed level.
  final DirectoryListing? parent;

  /// The selected row of [parent].
  final DirectoryEntry? selected;

  /// The selected folder's own listing (the right column).
  final DirectoryListing? child;
  final bool loading;

  /// A scan has been in flight past [slowScanDelay].
  final bool slowScan;
  final String? error;

  /// The path being typed; null in breadcrumb mode.
  final String? pathDraft;
  final bool showHidden;

  /// The new-folder name being typed; null while that dialog is closed.
  final String? folderDraft;
  final bool creatingFolder;
  final String? createError;

  bool get twoPane => selected != null;
  bool get draftPending => pathDraft != null;

  /// The folder a create or Open acts on: the selection, else the listed level.
  String? get targetPath => selected?.path ?? parent?.path;

  /// The listing whose crumbs name where the walk stands.
  DirectoryListing? get crumbSource => child ?? parent;

  BrowserState copyWith({
    Object? parent = _keep,
    Object? selected = _keep,
    Object? child = _keep,
    bool? loading,
    bool? slowScan,
    Object? error = _keep,
    Object? pathDraft = _keep,
    bool? showHidden,
    Object? folderDraft = _keep,
    bool? creatingFolder,
    Object? createError = _keep,
  }) => BrowserState(
    parent: identical(parent, _keep)
        ? this.parent
        : parent as DirectoryListing?,
    selected: identical(selected, _keep)
        ? this.selected
        : selected as DirectoryEntry?,
    child: identical(child, _keep) ? this.child : child as DirectoryListing?,
    loading: loading ?? this.loading,
    slowScan: slowScan ?? this.slowScan,
    error: identical(error, _keep) ? this.error : error as String?,
    pathDraft: identical(pathDraft, _keep)
        ? this.pathDraft
        : pathDraft as String?,
    showHidden: showHidden ?? this.showHidden,
    folderDraft: identical(folderDraft, _keep)
        ? this.folderDraft
        : folderDraft as String?,
    creatingFolder: creatingFolder ?? this.creatingFolder,
    createError: identical(createError, _keep)
        ? this.createError
        : createError as String?,
  );

  static const Object _keep = Object();
}

/// The interaction model of the in-app directory browser. Every operation is
/// dsh's: a navigation lands selection-anchored and quiet (the previous view
/// keeps rendering while a crumb jump or a submitted path is scanned, then
/// target and parent legs land as one two-pane frame; a slow parent leg falls
/// back to the target alone and upgrades in place), a row pick previews the
/// folder at once, the path editor keeps the panes under the draft, and Open
/// adopts the selection, falling back to the listed level.
class DirectoryBrowserModel {
  DirectoryBrowserModel({
    required ListDirectory list,
    required CreateDirectory create,
    this.failureText = defaultFailureText,
    this.homeLabel = 'Home',
  }) : _list = list,
       _create = create;

  final ListDirectory _list;
  final CreateDirectory _create;
  final FailureText failureText;

  /// The localized Home crumb.
  String homeLabel;

  final Observable<BrowserState> state = Observable(const BrowserState());

  BrowserState get value => state.value;

  int _seq = 0;
  int _generation = 0;
  AbortController? _scan;
  Timer? _slowTimer;
  Timer? _previewTimer;
  bool _previewSuspended = false;
  ScannedDirectory? _scanned;
  bool _disposed = false;
  bool _open = false;

  static String defaultFailureText(Object error) => '$error';

  void _set(BrowserState next) {
    if (!_disposed) state.set(next);
  }

  /// Newer intent wins: invalidate the pending listing and abort its wire
  /// request.
  int _supersede() {
    _scan?.abort();
    _scan = null;
    return ++_seq;
  }

  void _restartSlowWindow() {
    _slowTimer?.cancel();
    _set(value.copyWith(slowScan: false));
    _slowTimer = Timer(slowScanDelay, () {
      if (value.loading) _set(value.copyWith(slowScan: true));
    });
  }

  ({int seq, Future<DirectoryListing> scan}) _launch(String? path) {
    final seq = _supersede();
    final controller = AbortController();
    _scan = controller;
    _restartSlowWindow();
    return (seq: seq, scan: _list(path, controller.signal));
  }

  Future<DirectoryListing> _continue(String path) {
    final controller = AbortController();
    _scan = controller;
    _restartSlowWindow();
    return _list(path, controller.signal);
  }

  void _loading(bool on) {
    if (!on) _slowTimer?.cancel();
    _set(value.copyWith(loading: on, slowScan: on ? value.slowScan : false));
  }

  /// A fresh dialog: every open starts at the Host home directory.
  void open() {
    _generation++;
    _open = true;
    _set(const BrowserState());
    navigate(null);
  }

  /// Closing invalidates every in-flight response so a late arrival cannot
  /// repopulate a closed dialog.
  void close() {
    _generation++;
    _open = false;
    _supersede();
    _previewTimer?.cancel();
    _slowTimer?.cancel();
    _set(const BrowserState());
  }

  void dispose() {
    _disposed = true;
    _supersede();
    _previewTimer?.cancel();
    _slowTimer?.cancel();
    state.dispose();
  }

  /// Commit a submitted path (Enter, a crumb, the initial home listing): the
  /// editor closes, failures surface.
  void navigate(String? path) => _land(path, closeEditor: true, announce: true);

  /// Replace the whole view with a freshly scanned level, two-pane away from
  /// the display root (dsh `land`).
  void _land(
    String? path, {
    required bool closeEditor,
    required bool announce,
  }) {
    final launched = _launch(path);
    final seq = launched.seq;
    _loading(true);
    if (announce) _set(value.copyWith(error: null));
    void settle() {
      _loading(false);
      if (closeEditor) {
        _set(value.copyWith(pathDraft: null));
        return;
      }
      _set(value.copyWith(error: null));
    }

    launched.scan.then(
      (target) {
        if (seq != _seq || _disposed) return;
        if (!closeEditor && path != null) {
          _scanned = ScannedDirectory(path, target.path);
        }
        var landed = false;
        void landSingle() {
          if (landed || seq != _seq || _disposed) return;
          landed = true;
          _set(value.copyWith(parent: target, selected: null, child: null));
          settle();
        }

        if (displayCrumbs(target, '').length < 2 || target.crumbs.length < 2) {
          landSingle();
          return;
        }
        final parentCrumb = target.crumbs[target.crumbs.length - 2];
        _continue(parentCrumb.path).then((parentLevel) {
          if (seq != _seq || _disposed) return;
          final sep = separatorOf(parentLevel);
          String fold(String v) => sep == r'\' ? v.toLowerCase() : v;
          DirectoryEntry? match;
          for (final e in parentLevel.entries) {
            if (fold(e.path) == fold(target.path)) match = e;
          }
          if (match == null) {
            landSingle();
            return;
          }
          landed = true;
          _set(
            value.copyWith(parent: parentLevel, selected: match, child: target),
          );
          settle();
        }, onError: (Object _) => landSingle());
        // Only a submitted navigation is bounded: it answers a gesture and may
        // not hang on a stalled parent.
        if (closeEditor) Timer(parentLegWait, landSingle);
      },
      onError: (Object reason) {
        if (seq != _seq || _disposed) return;
        _loading(false);
        if (announce) _set(value.copyWith(error: failureText(reason)));
      },
    );
  }

  /// Select a row of the listed level and preview its children on the right.
  /// Not one-frame like [navigate]: a pick's first duty is the immediate
  /// selected state on the clicked row.
  void select(DirectoryEntry entry) {
    final launched = _launch(entry.path);
    _set(
      value.copyWith(
        pathDraft: null,
        selected: entry,
        child: null,
        error: null,
      ),
    );
    _loading(true);
    launched.scan.then(
      (next) {
        if (launched.seq != _seq || _disposed) return;
        _set(value.copyWith(child: next));
        _loading(false);
      },
      onError: (Object reason) {
        if (launched.seq != _seq || _disposed) return;
        _loading(false);
        // An unreadable selection cannot be the committing target.
        _set(value.copyWith(error: failureText(reason), selected: null));
      },
    );
  }

  /// A right-column pick advances the view one level: child becomes the level.
  void advance(DirectoryEntry entry) {
    final child = value.child;
    if (child == null) return;
    _set(value.copyWith(parent: child));
    select(entry);
  }

  /// Pick a row of whichever pane shows it (a phone shows one pane: the child
  /// when there is one, else the level).
  void pick(DirectoryEntry entry) =>
      value.child == null ? select(entry) : advance(entry);

  // ---- path editor -------------------------------------------------------

  /// Open the path editor, seeded with a trailing separator.
  void startPathEdit() {
    _supersede();
    _loading(false);
    _previewSuspended = false;
    final parent = value.parent;
    if (parent == null) {
      _set(value.copyWith(pathDraft: ''));
      return;
    }
    final base = value.selected?.path ?? parent.path;
    final sep = separatorOf(parent);
    _set(value.copyWith(pathDraft: base.endsWith(sep) ? base : '$base$sep'));
  }

  /// A keystroke of the path editor.
  void setPathDraft(String draft) {
    _supersede();
    _loading(false);
    _previewSuspended = false;
    _set(value.copyWith(pathDraft: draft));
    _armPreview(draft);
  }

  /// Enter in the path editor: the submitted path owns the view.
  void submitPath() {
    final draft = value.pathDraft;
    if (draft == null || draft.trim().isEmpty) return;
    _previewSuspended = true;
    _previewTimer?.cancel();
    navigate(draft);
  }

  /// Abandon path editing and restore the crumb view.
  void cancelPathEdit() {
    _supersede();
    _previewTimer?.cancel();
    _loading(false);
    _set(value.copyWith(pathDraft: null, error: null));
    // A selection with no preview would render a half-empty two-pane view.
    if (value.child == null) _set(value.copyWith(selected: null));
    // With no level listed yet, restart the home listing.
    if (value.parent == null) navigate(null);
  }

  /// The panes follow the draft: every keystroke replaces the pending timer,
  /// and the target is decided when it fires.
  void _armPreview(String draft) {
    _previewTimer?.cancel();
    _previewTimer = Timer(draftPreviewDebounce, () {
      if (_previewSuspended || _disposed || value.pathDraft != draft) return;
      final current = value.crumbSource;
      if (current == null) return;
      final read = readDraft(current, draft, _scanned);
      if (read.directory == null || read.tail != null) return;
      _land(read.directory, closeEditor: false, announce: false);
    });
  }

  /// The prefix the draft filters the last pane with, or null.
  String? get typedPrefix {
    final source = value.crumbSource;
    final draft = value.pathDraft;
    if (source == null || draft == null) return null;
    return readDraft(source, draft, _scanned).tail;
  }

  // ---- hidden files ------------------------------------------------------

  void toggleHidden() => _set(value.copyWith(showHidden: !value.showHidden));

  // ---- new folder --------------------------------------------------------

  /// Open the nested create dialog targeting the selected folder or the level.
  void startCreate() =>
      _set(value.copyWith(folderDraft: '', createError: null));

  void setFolderDraft(String draft) => _set(value.copyWith(folderDraft: draft));

  void cancelCreate() {
    if (value.creatingFolder) return;
    _set(value.copyWith(folderDraft: null, createError: null));
  }

  /// The name of the folder a create acts in (the selection, else the level).
  String get targetName {
    final selected = value.selected;
    if (selected != null) return selected.name;
    final parent = value.parent;
    if (parent == null) return '';
    final crumbs = displayCrumbs(parent, homeLabel);
    return crumbs.isEmpty ? parent.path : crumbs.last.name;
  }

  /// Create the named folder and land on it, selected, like a right-column
  /// pick. The Host gets the original spelling (trim only rejects all-blank).
  Future<void> confirmCreate() async {
    final target = value.targetPath;
    final name = value.folderDraft;
    if (target == null || name == null || value.creatingFolder) return;
    if (name.trim().isEmpty) return;
    _set(value.copyWith(creatingFolder: true, createError: null));
    final generation = _generation;
    final String created;
    try {
      created = await _create(target, name);
    } on Object catch (reason) {
      if (generation != _generation || _disposed) return;
      _set(
        value.copyWith(creatingFolder: false, createError: failureText(reason)),
      );
      return;
    }
    if (generation != _generation || _disposed) return;
    _set(value.copyWith(creatingFolder: false, folderDraft: null));
    final launched = _launch(target);
    _loading(true);
    _set(value.copyWith(error: null));
    try {
      final level = await launched.scan;
      if (launched.seq != _seq || _disposed) return;
      _set(value.copyWith(parent: level));
      _loading(false);
      select(DirectoryEntry(name: name, path: created, hidden: false));
    } on Object catch (reason) {
      if (launched.seq != _seq || _disposed) return;
      _loading(false);
      _set(value.copyWith(error: failureText(reason)));
    }
  }

  /// The directory Open adopts: the selection, else the listed level.
  String? get openTarget => value.targetPath;

  /// Whether Open may be pressed now.
  bool get canOpen =>
      value.targetPath != null && !value.loading && !value.draftPending;

  /// Whether New folder may be pressed now.
  bool get canCreate =>
      value.parent != null && !value.loading && !value.draftPending;

  bool get isOpen => _open;
}
