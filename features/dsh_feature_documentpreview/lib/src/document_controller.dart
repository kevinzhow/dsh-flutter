import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';

import 'renderers.dart';

/// One loaded window of a text file (dsh `TextPage`).
class TextPage {
  const TextPage(this.offset, this.lines);

  /// 1-based number of the page's first line.
  final int offset;

  /// The page's lines (empty for a page past the end).
  final List<String> lines;
}

/// A file preview's state (dsh `TextPreview` store): which viewer, the
/// content loaded so far (text pages or the complete bytes), the version it
/// shows, the failure that stopped it, and the watch that tells a changed
/// file. Pure Dart over [WorkspaceFilesRemote], so it is tested with a
/// scripted remote.
class DocumentController extends ChangeNotifier {
  DocumentController({
    required this.sessionId,
    required this.path,
    required this.files,
    this.autoRefresh = true,
  }) : candidates = rendererCandidates(path) {
    if (candidates.isNotEmpty) {
      _selected = candidates.first;
      unawaited(_start());
    }
    _watch();
  }

  final String sessionId;

  /// The path as the address carries it: workspace-relative or absolute.
  final String path;
  final WorkspaceFilesRemote files;
  final bool autoRefresh;
  final List<DocumentRenderer> candidates;

  DocumentRenderer? _selected;
  DocumentRenderer? get selected => _selected;

  final List<TextPage> pages = [];
  Uint8List? bytes;
  bool eof = false;
  bool loading = false;

  /// The failure that stopped the content read, if any.
  Object? failure;

  /// The file's own failure (gone) from its watch or stat.
  Object? metaFailure;

  /// Absolute path and version the content shows, from the read.
  String? absolutePath;
  String? version;

  /// A newer version was observed than the one shown.
  String? observedVersion;

  bool wrap = true;

  /// 1-based line to bring into view, answered once by the view.
  int? targetLine;
  int targetRevision = -1;

  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<WorkspaceWatchEvent>? _watchSub;

  bool get changed =>
      observedVersion != null && version != null && observedVersion != version;

  /// The last loaded line (0 before anything loaded).
  int get loadedThrough =>
      pages.isEmpty ? 0 : pages.last.offset + pages.last.lines.length - 1;

  bool get hasContent => selected?.loading == DocumentLoad.bytesComplete
      ? bytes != null
      : pages.isNotEmpty;

  /// Everything loaded so far as lines, in order.
  List<String> get lines => [for (final p in pages) ...p.lines];

  void select(String id) {
    final next = candidates.where((r) => r.id == id).firstOrNull;
    if (next == null || next.id == _selected?.id) return;
    final reload = next.loading != _selected?.loading;
    _selected = next;
    if (reload) {
      _reset();
      unawaited(_start());
    }
    _changed();
  }

  void toggleWrap() {
    wrap = !wrap;
    _changed();
  }

  /// Navigate to [line] (a tool card's `offset`): load pages until it exists.
  void navigate(int? line, int revision) {
    if (revision == targetRevision) return;
    targetRevision = revision;
    targetLine = line;
    if (line != null &&
        _selected?.loading == DocumentLoad.textPages &&
        !eof &&
        line > loadedThrough) {
      unawaited(_loadUntil(line));
    }
    _changed();
  }

  void answeredTarget() {
    targetLine = null;
  }

  Future<void> _loadUntil(int line) async {
    while (!_disposed &&
        !eof &&
        failure == null &&
        line > loadedThrough &&
        _selected?.loading == DocumentLoad.textPages) {
      await loadNext();
    }
  }

  void _reset() {
    _generation++;
    pages.clear();
    bytes = null;
    eof = false;
    failure = null;
    loading = false;
    version = null;
  }

  Future<void> _start() async {
    final renderer = _selected;
    if (renderer == null) return;
    if (renderer.loading == DocumentLoad.bytesComplete) {
      await _loadBytes();
    } else {
      await loadNext();
    }
  }

  /// Read the next page of lines (the first when none is loaded).
  Future<void> loadNext() async {
    if (loading || eof || _selected?.loading != DocumentLoad.textPages) return;
    loading = true;
    failure = null;
    final generation = _generation;
    final offset = loadedThrough + 1;
    _changed();
    try {
      final page = await files.read(sessionId, path, offset: offset);
      if (_disposed || generation != _generation) return;
      pages.add(
        TextPage(
          page.offset,
          page.lines == 0 ? const [] : page.text.split('\n'),
        ),
      );
      eof = page.eof;
      absolutePath = page.absolutePath;
      version ??= page.version;
      metaFailure = null;
    } on Object catch (e) {
      if (_disposed || generation != _generation) return;
      failure = e;
    }
    loading = false;
    _changed();
  }

  Future<void> _loadBytes() async {
    loading = true;
    failure = null;
    final generation = _generation;
    _changed();
    try {
      final result = await files.readBytes(sessionId, path);
      if (_disposed || generation != _generation) return;
      bytes = result.data;
      eof = true;
      absolutePath = result.absolutePath;
      version = result.version;
      metaFailure = null;
    } on Object catch (e) {
      if (_disposed || generation != _generation) return;
      failure = e;
    }
    loading = false;
    _changed();
  }

  /// Read the file again from its start, keeping what is shown until the new
  /// content arrives would flicker; dsh rebuilds the pages, so do we.
  Future<void> reload() async {
    final renderer = _selected;
    if (renderer == null) return;
    _reset();
    observedVersion = null;
    metaFailure = null;
    _changed();
    await _start();
  }

  void _watch() {
    _watchSub = files.changes(sessionId, path).listen(
      (event) {
        switch (event) {
          case WatchReady():
            break;
          case WatchReopened():
            break;
          case WatchChanged(absent: true):
            metaFailure = RemoteException(
              'workspace-file/not-found',
              'the file is gone',
              {'path': path},
            );
            _changed();
          case WatchChanged(:final version):
            metaFailure = null;
            observedVersion = version;
            _changed();
            if (autoRefresh && changed && !loading && failure == null) {
              unawaited(reload());
            }
        }
      },
      // A watch the host cannot start leaves the preview readable; the
      // reload control still rereads.
      onError: (Object _) {},
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_watchSub?.cancel());
    super.dispose();
  }
}
