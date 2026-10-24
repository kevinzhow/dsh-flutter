import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'chat_nodes.dart';

/// How near the bottom (px) still counts as "following" the stream.
const followThreshold = 96.0;

/// The chat view of one session (dsh `ui-chat` `ChatView`): the ordered chat
/// nodes of the conversation snapshot, each rendered through the keyed
/// `conversation.chat.node` slot, plus local prompt echoes, a running
/// indicator and a "load earlier" row. It keeps the newest content in view
/// while the reader is at the bottom and leaves the scroll alone otherwise.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.nodeSlot,
    this.turnTailSlot,
  });

  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n i18n;
  final Slot<ChatNodeOwner, Widget> nodeSlot;

  /// `conversation.chat.turnTail`: additive entries after a turn's closing row
  /// (submitted plans, file deliveries). An entry returns null to show nothing.
  final Slot<TurnTailOwner, Widget?>? turnTailSlot;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ScrollController _scroll = ScrollController();
  StreamSubscription<ChatSnapshot>? _chatSub;
  StreamSubscription<SessionSnapshot>? _sessionSub;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _bind();
    // A session opens at its newest message.
    _scrollToEnd(3);
  }

  @override
  void didUpdateWidget(ChatView old) {
    super.didUpdateWidget(old);
    if (old.owner != widget.owner) {
      _unbind();
      _follow = true;
      _bind();
    }
  }

  void _bind() {
    _chatSub = widget.owner.conversation.chat.changes.listen(_changed);
    _sessionSub = widget.owner.session.snapshot.changes.listen(_changed);
  }

  void _unbind() {
    unawaited(_chatSub?.cancel());
    unawaited(_sessionSub?.cancel());
  }

  void _changed(Object _) {
    if (!mounted) return;
    setState(() {});
    if (_follow) _scrollToEnd(2);
  }

  /// Rows are built lazily, so the extent is an estimate until they lay out:
  /// jump, then jump again once on the next frame.
  void _scrollToEnd(int passes) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_follow) return;
      final end = _scroll.position.maxScrollExtent;
      if ((_scroll.offset - end).abs() > 1) _scroll.jumpTo(end);
      if (passes > 1) _scrollToEnd(passes - 1);
    });
  }

  @override
  void dispose() {
    _unbind();
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _follow = n.metrics.extentAfter < followThreshold;
    }
    return false;
  }

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

  @override
  Widget build(BuildContext context) {
    final owner = widget.owner;
    final chat = owner.conversation.chat.value;
    final session = owner.session.snapshot.value;
    final nodes = chat.visibleNodes;
    // Items are built lazily: only the rows on screen run their builders, so a
    // long history costs nothing per streamed chunk.
    final items = <Widget Function()>[];

    if (session.hasMore) {
      items.add(
        () => Align(
          alignment: Alignment.center,
          child: DshButton(
            key: const ValueKey('load-older'),
            size: DshButtonSize.sm,
            onPressed: session.loadingOlder ? null : owner.actions.loadOlder,
            child: DshChromeText(
              session.loadingOlder
                  ? widget.i18n.t('chat', 'chat.loadingHistory')
                  : widget.i18n.t('chat', 'chat.loadOlder'),
            ),
          ),
        ),
      );
    }
    for (final node in nodes) {
      items.add(
        () => KeyedSubtree(
          key: ValueKey(node.key),
          child:
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
          items.add(
            () => KeyedSubtree(
              key: ValueKey('${node.key}-tail-$i'),
              child: tail[i],
            ),
          );
        }
      }
    }
    for (final p in session.pendingSubmissions) {
      items.add(
        () => UserBubble(
          key: ValueKey('pending-${p.requestId}'),
          text: p.text,
          i18n: widget.i18n,
          pending: true,
          attachments: echoAttachmentViews(p.attachments),
          owner: owner,
          slots: widget.slots,
        ),
      );
    }
    if (_showRunning(chat, session)) {
      items.add(
        () => Padding(
          key: const ValueKey('running-indicator'),
          padding: const EdgeInsets.symmetric(vertical: DshSpace.xs),
          child: NoticeRow(
            text: widget.i18n.t('chat', 'chat.deepDiving'),
            status: DshStatus.running,
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DshSpace.xl),
          child: DshChromeText(
            key: const ValueKey('chat-empty'),
            widget.i18n.t(appNamespace, 'session.empty'),
            textAlign: TextAlign.center,
            style: context.dsh
                .textStyle('--dsw-font-s-14')
                .copyWith(color: context.dsh.labelSecondary),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: DshSpace.readableWidth),
          child: ListView.separated(
            key: const ValueKey('chat-list'),
            controller: _scroll,
            padding: const EdgeInsets.all(DshSpace.lg),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: DshSpace.md),
            itemBuilder: (_, i) => items[i](),
          ),
        ),
      ),
    );
  }
}
