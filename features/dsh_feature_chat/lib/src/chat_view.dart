import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'chat_nodes.dart';
import 'stream/extras.dart';
import 'stream/jump_button.dart';
import 'stream/load_earlier.dart';
import 'stream/loading_hint.dart';
import 'stream/reading_anchor.dart';
import 'stream/row_extents.dart';
import 'stream/selection.dart';
import 'stream/skeleton.dart';
import 'stream/timeline.dart';

/// How near the latest end (px) still counts as "following" the stream: dsh's
/// `FOLLOW_THRESHOLD` (24) plus the pixel it adds.
const followThreshold = 25.0;

/// From this width the stream follows dsh's desktop app (draggable bar,
/// list-wide selection); below it the phone adaptations apply (768 is the cut
/// raft-flutter's presentation policy uses for compact windows).
const wideLayoutWidth = 768.0;

/// One row of the timeline: a chat node, a node's turn-tail entry, a local
/// prompt echo or the running indicator. [id] is stable for the row's life.
class _Row {
  const _Row(this.id, this.build, {this.node, this.transient = false});
  final String id;
  final Widget Function() build;

  /// The chat node behind the row; null for echoes and the running status.
  final ViewNode? node;

  /// Echoes and the status row come and go; a node row never does.
  final bool transient;
}

/// The chat view of one session (dsh `ui-chat` `ChatView`): the ordered chat
/// nodes of the conversation snapshot, each rendered through the keyed
/// `conversation.chat.node` slot, plus local prompt echoes, a running
/// indicator and the history above them.
///
/// The list is a two-sided timeline (a port of raft-flutter's message
/// timeline): history grows away from a fixed center, so older pages and
/// image loads above the reader never move what is on screen; the latest end
/// is followed while the reader is at it. Older pages are read when the
/// reader nears the top; the reader's place is kept per session.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.nodeSlot,
    this.turnTailSlot,
    this.memory,
  });

  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n i18n;
  final Slot<ChatNodeOwner, Widget> nodeSlot;

  /// `conversation.chat.turnTail`: additive entries after a turn's closing row
  /// (submitted plans, file deliveries). An entry returns null to show nothing.
  final Slot<TurnTailOwner, Widget?>? turnTailSlot;

  /// Where readers stopped in each session; a session reopens there.
  final ChatReadingMemory? memory;

  @override
  State<ChatView> createState() => ChatViewState();
}

class ChatViewState extends State<ChatView> {
  late final ChatReadingMemory _fallbackMemory = ChatReadingMemory();
  ChatReadingMemory get _memory => widget.memory ?? _fallbackMemory;

  StreamSubscription<ChatSnapshot>? _chatSub;
  StreamSubscription<SessionSnapshot>? _sessionSub;

  /// The timeline's scroll controller; replaced when a context is (re)opened.
  DshTimelineController? _scroll;
  final _retired = <DshTimelineController>{};
  final _extents = RowExtents();

  List<_Row> _rows = const [];
  Map<String, int> _index = const {};
  bool _opened = false;

  /// The timeline's center: rows from [_centerFirst] on (or after
  /// [_centerAfter]) are in the forward sliver, older rows in the history
  /// sliver. Only an explicit jump moves it ([_epoch]).
  String? _centerFirst, _centerAfter;
  int _epoch = 0, _lastCenter = 0;

  bool _atBottom = true;
  int _newCount = 0;
  String? _filledFor;
  Timer? _saveTimer;

  @visibleForTesting
  ScrollController? get scrollController => _scroll;
  @visibleForTesting
  bool get atBottom => _atBottom;
  @visibleForTesting
  int get newCount => _newCount;

  String get _sessionId => widget.owner.session.sessionId;

  @override
  void initState() {
    super.initState();
    _bind();
    _refresh();
  }

  @override
  void didUpdateWidget(ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner != widget.owner) {
      _saveAnchor(oldWidget.owner.session.sessionId);
      _unbind();
      _opened = false;
      _rows = const [];
      _index = const {};
      _atBottom = true;
      _newCount = 0;
      _filledFor = null;
      _bind();
    }
    _refresh();
  }

  void _bind() {
    _chatSub = widget.owner.conversation.chat.changes.listen(_changed);
    _sessionSub = widget.owner.session.snapshot.changes.listen(_changed);
  }

  void _unbind() {
    unawaited(_chatSub?.cancel());
    unawaited(_sessionSub?.cancel());
  }

  /// Leaving the tree (the session screen closes): the render objects are
  /// still attached here, unlike in [dispose], so the reader's place is
  /// captured now.
  @override
  void deactivate() {
    _saveTimer?.cancel();
    _saveAnchor(_sessionId);
    super.deactivate();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _unbind();
    _scroll?.dispose();
    for (final retired in _retired) {
      retired.dispose();
    }
    super.dispose();
  }

  void _changed(Object _) {
    if (mounted) _refresh();
  }

  // ---- rows ---------------------------------------------------------------

  bool _showRunning(ChatSnapshot chat, SessionSnapshot session) {
    if (!session.running) return false;
    final last = chat.visibleNodes.lastOrNull;
    if (last == null) return true;
    if (last.kind == 'turn-tail' || last.kind == 'turn-error') return true;
    if (last.kind == 'assistant-step') {
      return (last.data as AssistantData).status != 'running';
    }
    if (last.kind == 'tool-call') {
      return (last.data as ToolData).root is ToolResult;
    }
    return true;
  }

  List<_Row> _computeRows() {
    final owner = widget.owner;
    final chat = owner.conversation.chat.value;
    final session = owner.session.snapshot.value;
    final rows = <_Row>[];
    for (final node in chat.visibleNodes) {
      rows.add(
        _Row(
          node.key,
          node: node,
          () =>
              widget.slots.renderKeyed(
                widget.nodeSlot,
                node.kind,
                ChatNodeOwner(session: owner, node: node, snapshot: chat),
              ) ??
              const SizedBox.shrink(),
        ),
      );
      final tailSlot = widget.turnTailSlot;
      if (tailSlot != null && node.kind == 'turn-tail') {
        final tail = widget.slots
            .renderList(
              tailSlot,
              TurnTailOwner(
                session: owner,
                turn: (node.data as TurnTailData).turn,
                snapshot: chat,
              ),
            )
            .nonNulls
            .toList();
        for (var i = 0; i < tail.length; i++) {
          rows.add(_Row('${node.key}-tail-$i', () => tail[i]));
        }
      }
    }
    for (final p in session.pendingSubmissions) {
      rows.add(
        _Row(
          'pending-${p.requestId}',
          transient: true,
          () => UserBubble(
            text: p.text,
            i18n: widget.i18n,
            pending: true,
            attachments: echoAttachmentViews(p.attachments),
            owner: owner,
            slots: widget.slots,
          ),
        ),
      );
    }
    if (_showRunning(chat, session)) {
      rows.add(
        _Row(
          'running-indicator',
          transient: true,
          () => Padding(
            padding: const EdgeInsets.symmetric(vertical: DshSpace.xs),
            child: NoticeRow(
              text: widget.i18n.t('chat', 'chat.deepDiving'),
              status: DshStatus.running,
            ),
          ),
        ),
      );
    }
    return rows;
  }

  void _refresh() {
    final next = _computeRows();
    final session = widget.owner.session.snapshot.value;
    if (!_opened) {
      // Rows published before the open call returns count as open.
      if (session.openState == OpenState.open || next.isNotEmpty) {
        _openContext(next);
      } else {
        setState(() => _rows = next);
      }
      return;
    }
    _applyRows(next);
  }

  void _reindex() {
    _index = {for (var i = 0; i < _rows.length; i++) _rows[i].id: i};
  }

  /// The last row that is a real node: the center sits after it, so echoes and
  /// the status row (which come and go) never hold the center.
  String? _lastNodeId(List<_Row> rows) {
    for (var i = rows.length - 1; i >= 0; i--) {
      if (!rows[i].transient) return rows[i].id;
    }
    return null;
  }

  /// Opens a context: a fresh controller and center, positioned inside its
  /// first layout at the reader's remembered place, else at the latest end.
  void _openContext(List<_Row> rows, {ReadingAnchor? resume}) {
    final ids = {for (final r in rows) r.id};
    final saved = resume ?? _memory.read(_sessionId);
    final target = saved != null && ids.contains(saved.rowId) ? saved : null;
    final old = _scroll;
    if (old != null) _retired.add(old);
    _opened = true;
    _rows = rows;
    _reindex();
    _centerFirst = target?.rowId;
    _centerAfter = target == null ? _lastNodeId(rows) : null;
    final afterAt = _centerAfter == null ? null : _index[_centerAfter];
    _lastCenter = target == null ? (afterAt == null ? 0 : afterAt + 1) : 0;
    _epoch++;
    _atBottom = target == null;
    _newCount = 0;
    _scroll = DshTimelineController(
      bottomAnchored: false,
      initial: target == null
          ? DshTimelineAlignment.end
          : _alignOnRow(target.rowId, leading: target.top),
    )..addListener(_scrolled);
    setState(() {});
    _retire();
    _scheduleFillCheck();
  }

  void _retire() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in _retired.toList()) {
        if (_retired.remove(c)) c.dispose();
      }
    });
  }

  void _applyRows(List<_Row> next) {
    final current = _rows;
    final wanted = {for (final r in next) r.id};
    final currentIds = [for (final r in current) r.id];
    final nextIds = [for (final r in next) r.id];
    var same = currentIds.length == nextIds.length;
    for (var i = 0; same && i < nextIds.length; i++) {
      same = currentIds[i] == nextIds[i];
    }
    // Rows are rebuilt from a new snapshot even when the ids match (a
    // streamed chunk changes a row's content).
    final previousLast = _lastNodeId(current);
    final lostCenter =
        (_centerFirst != null && !wanted.contains(_centerFirst)) ||
        (_centerAfter != null && !wanted.contains(_centerAfter));
    if (!same &&
        ((!_atBottom &&
                // Echoes and the status row come and go at the end; only
                // real rows appearing inside the history move the reader.
                insertsBetweenRetainedRows(
                  [
                    for (final r in current)
                      if (!r.transient) r.id,
                  ],
                  [
                    for (final r in next)
                      if (!r.transient) r.id,
                  ],
                )) ||
            lostCenter)) {
      _saveAnchor(_sessionId);
      final resume = _memory.read(_sessionId);
      if (resume != null && wanted.contains(resume.rowId)) {
        _openContext(next, resume: resume);
        return;
      }
    }
    if (!same) _retainCenter(current, wanted);
    var ownMessage = false;
    if (!same) {
      final from = previousLast == null ? 0 : nextIds.indexOf(previousLast) + 1;
      if (from > 0 || previousLast == null) {
        for (final row in next.skip(from)) {
          if (row.id.startsWith('pending-')) ownMessage = true;
          if (!_atBottom && _countsAsNew(row)) _newCount++;
        }
      }
    }
    _rows = next;
    _reindex();
    setState(() {});
    if (ownMessage) _showLatest();
    _scheduleFillCheck();
  }

  /// Rows that read as something new below the reader: messages and failures,
  /// not tool rows or tails (a long run adds many of those).
  bool _countsAsNew(_Row row) => switch (row.node?.kind) {
    'assistant-step' || 'user' || 'steering' || 'turn-error' => true,
    _ => false,
  };

  /// Keeps the center on a surviving row when its row leaves the list.
  void _retainCenter(List<_Row> before, Set<String> kept) {
    String? survivor(int from, int step) {
      for (var i = from; i >= 0 && i < before.length; i += step) {
        if (kept.contains(before[i].id)) return before[i].id;
      }
      return null;
    }

    final first = _centerFirst, after = _centerAfter;
    if (first != null && !kept.contains(first)) {
      final at = before.indexWhere((r) => r.id == first);
      _centerFirst = survivor(at + 1, 1);
      if (_centerFirst == null) _centerAfter = survivor(at - 1, -1);
    } else if (after != null && !kept.contains(after)) {
      final at = before.indexWhere((r) => r.id == after);
      _centerAfter = survivor(at - 1, -1);
      if (_centerAfter == null) _centerFirst = survivor(at + 1, 1);
    }
  }

  int _centerIndex() {
    final first = _centerFirst, after = _centerAfter;
    int? at;
    if (first != null) {
      at = _index[first];
    } else if (after != null) {
      final i = _index[after];
      at = i == null ? null : i + 1;
    }
    return _lastCenter = (at ?? _lastCenter).clamp(0, _rows.length);
  }

  /// Moves the center (one rebuild) and positions the next layout.
  void _recenter({
    String? first,
    String? after,
    required DshTimelineAlignment alignment,
  }) {
    _centerFirst = first;
    _centerAfter = first == null ? after : null;
    _epoch++;
    _scroll?.align(alignment);
    if (mounted) setState(() {});
  }

  DshTimelineAlignment _alignOnRow(String id, {double? leading}) =>
      DshTimelineAlignment.row(
        find: () {
          RenderBox? found;
          void visit(Element element) {
            if (found != null) return;
            if (element.widget.key == RowKey(id)) {
              final box = element.renderObject;
              if (box is RenderBox && box.attached) found = box;
              return;
            }
            element.visitChildren(visit);
          }

          try {
            (context as Element).visitChildren(visit);
          } on FlutterError {
            return null;
          }
          return found;
        },
        leading: leading,
      );

  // ---- reading position and the latest end ---------------------------------

  double _distanceFromLatest(ScrollPosition p) => p.maxScrollExtent - p.pixels;

  void _scrolled() {
    final scroll = _scroll;
    if (!mounted || scroll == null || scroll.positions.length != 1) return;
    final position = scroll.position;
    if (!position.hasContentDimensions) return;
    // The reader's place is remembered once the scrolling pauses (a fling
    // still coasts after the finger leaves).
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => _saveAnchor(_sessionId),
    );
    final near = _distanceFromLatest(position) <= followThreshold;
    if (near != _atBottom || (near && _newCount != 0)) {
      setState(() {
        _atBottom = near;
        if (near) _newCount = 0;
      });
    }
  }

  /// Remembers where the reader is (the topmost visible row), or forgets it
  /// at the latest end (dsh's `chatScroll` store).
  void _saveAnchor(String sessionId) {
    final scroll = _scroll;
    if (!_opened ||
        scroll == null ||
        !scroll.hasClients ||
        scroll.positions.length != 1 ||
        scroll.pending != null) {
      return;
    }
    final position = scroll.position;
    if (!position.hasContentDimensions) return;
    if (_distanceFromLatest(position) <= followThreshold) {
      _memory.save(sessionId, null);
    } else if (mounted) {
      final anchor = captureReadingAnchor(context);
      if (anchor != null) _memory.save(sessionId, anchor);
    }
  }

  /// Back at the latest end: a short animated move within a screen, a jump
  /// within a couple of screens, otherwise a fresh center at the end (never
  /// laying out the distance in between).
  void _showLatest() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients || scroll.positions.length != 1) {
      return;
    }
    final position = scroll.position;
    if (position.hasContentDimensions &&
        _distanceFromLatest(position) <= position.viewportDimension * 2) {
      final distance = _distanceFromLatest(position);
      if (distance <= position.viewportDimension &&
          !MediaQuery.disableAnimationsOf(context)) {
        unawaited(
          position.animateTo(
            position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        scroll.followEnd();
        if (position.pixels != position.maxScrollExtent) {
          scroll.jumpTo(position.maxScrollExtent);
        }
      }
    } else {
      _recenter(after: _lastNodeId(_rows), alignment: DshTimelineAlignment.end);
    }
    setState(() {
      _newCount = 0;
      _atBottom = true;
    });
  }

  /// A session shorter than the screen has nothing to scroll toward older
  /// history with: read pages until it fills or the history ends.
  void _scheduleFillCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = _scroll;
      if (!mounted ||
          !_opened ||
          scroll == null ||
          !scroll.hasClients ||
          scroll.positions.length != 1) {
        return;
      }
      final session = widget.owner.session.snapshot.value;
      final position = scroll.position;
      final first = _rows.firstOrNull?.id;
      if (!session.hasMore ||
          session.loadingOlder ||
          first == null ||
          _filledFor == first ||
          !position.hasContentDimensions ||
          position.maxScrollExtent - position.minScrollExtent >= 1) {
        return;
      }
      _filledFor = first;
      unawaited(widget.owner.actions.loadOlder());
    });
  }

  // ---- build --------------------------------------------------------------

  Widget _frame(BuildContext context, int index, double side, double width) {
    final row = _rows[index];
    return RowExtentRecorder(
      extents: _extents,
      id: row.id,
      child: KeyedSubtree(
        key: RowKey(row.id),
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 0, side, DshSpace.md),
          child: StreamSelection(child: row.build()),
        ),
      ),
    );
  }

  double _estimate(int index, double width) {
    if (index < 0 || index >= _rows.length) return 96;
    final row = _rows[index];
    final measured = _extents.measured(row.id, width);
    if (measured != null) return measured;
    final node = row.node;
    return (node == null ? 40.0 : guessNodeExtent(node, width)) + DshSpace.md;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.owner.session.snapshot.value;
    final theme = context.dsh;
    if (!_opened) {
      // The session is still opening. dsh's ChatView shows a hint above the
      // (empty) flow (`openState === 'loading'` -> `chat.loadingHistory`); the
      // skeleton is Raft's, behind [streamExtras].
      if (session.openState == OpenState.error) return const SizedBox.shrink();
      final hint = widget.i18n.t('chat', 'chat.loadingHistory');
      return Semantics(
        label: hint,
        liveRegion: true,
        child: SingleChildScrollView(
          key: const ValueKey('session-loading'),
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DshSpace.lg),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DshSpace.readableWidth,
              ),
              child: streamExtras
                  ? const StreamSkeleton()
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: LoadingHint(hint),
                    ),
            ),
          ),
        ),
      );
    }
    if (_rows.isEmpty && !session.hasMore) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DshSpace.xl),
          child: DshChromeText(
            key: const ValueKey('chat-empty'),
            widget.i18n.t(appNamespace, 'session.empty'),
            textAlign: TextAlign.center,
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelSecondary),
          ),
        ),
      );
    }
    final scroll = _scroll!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final side = math.max(
          DshSpace.lg,
          (width - DshSpace.readableWidth) / 2 + DshSpace.lg,
        );
        // The window, not the column: a desktop window with the sidebars open
        // still follows the desktop app.
        final wide = MediaQuery.sizeOf(context).width >= wideLayoutWidth;
        final hasOlder = session.hasMore;
        Widget header() => SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, DshSpace.lg, side, DshSpace.md),
            child: !hasOlder
                ? const SizedBox.shrink()
                : streamExtras && session.loadingOlder
                ? Semantics(
                    label: widget.i18n.t('chat', 'chat.loadingHistory'),
                    child: const StreamSkeleton(
                      key: ValueKey('older-skeleton'),
                      exchanges: 1,
                    ),
                  )
                : SelectionContainer.disabled(
                    child: Center(
                      child: LoadEarlierButton(
                        key: const ValueKey('load-older'),
                        label: session.loadingOlder
                            ? widget.i18n.t('common', 'loading')
                            : widget.i18n.t('chat', 'chat.loadOlder'),
                        onPressed: session.loadingOlder
                            ? null
                            : widget.owner.actions.loadOlder,
                      ),
                    ),
                  ),
          ),
        );
        final timeline = DshStreamTimeline(
          key: const ValueKey('chat-list'),
          controller: scroll,
          ids: [for (final r in _rows) r.id],
          centerIndex: _centerIndex(),
          epoch: _epoch,
          indexOfId: (id) => _index[id],
          rowBuilder: (context, index) => _frame(context, index, side, width),
          estimateRow: (index) => _estimate(index, width),
          slivers: (history, forward) => [
            header(),
            history,
            forward,
            const SliverToBoxAdapter(child: SizedBox(height: DshSpace.lg)),
          ],
          wide: wide,
          hasOlder: hasOlder,
          loadingOlder: session.loadingOlder,
          onLoadOlder: () => unawaited(widget.owner.actions.loadOlder()),
          onRecenter: (index, alignment) =>
              _recenter(first: _rows[index].id, alignment: alignment),
        );
        final count = streamExtras && _newCount > 0
            ? widget.i18n.t(
                appNamespace,
                'chat.newCount',
                params: {'count': _newCount},
              )
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            StreamSelection.list(timeline),
            if (!_atBottom)
              Positioned(
                right: side,
                bottom: DshSpace.lg - (DshSpace.touch - 34) / 2,
                child: StreamJumpButton(
                  label: widget.i18n.t('chat', 'chat.toBottom'),
                  countLabel: count,
                  onPressed: _showLatest,
                ),
              ),
          ],
        );
      },
    );
  }
}
