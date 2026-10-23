import 'dart:async';

import 'package:dsh_models/dsh_models.dart';

import 'assembler.dart';
import 'chat/definitions.dart';
import 'chat/snapshot.dart';
import 'contract.dart';
import 'event.dart';

/// Decides when requested `animation-frame` publications flush. The default
/// coalesces them on a short timer; tests use [FlushScheduler.immediate].
abstract interface class FlushScheduler {
  /// Run [flush] soon, at most once for any burst of requests.
  void schedule(void Function() flush);
  void cancel();

  static FlushScheduler immediate() => _Immediate();
  static FlushScheduler frames({
    Duration frame = const Duration(milliseconds: 48),
  }) => _Timed(frame);
}

class _Immediate implements FlushScheduler {
  @override
  void schedule(void Function() flush) => flush();
  @override
  void cancel() {}
}

class _Timed implements FlushScheduler {
  _Timed(this.frame);
  final Duration frame;
  Timer? _timer;
  @override
  void schedule(void Function() flush) {
    if (_timer != null) return;
    _timer = Timer(frame, () {
      _timer = null;
      flush();
    });
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// One Session's conversation assembly (dsh `BoundConversation`): follows the
/// Session's event window, feeds the assembler with each exact delta, and
/// publishes the chat target snapshot.
class ConversationBinding {
  ConversationBinding(
    MutableEventSource feed, {
    required ConversationAssembler assembler,
    FlushScheduler? scheduler,
  }) : _feed = feed,
       _assembler = assembler,
       _scheduler = scheduler ?? FlushScheduler.frames() {
    _assembler.activateTarget(chatTarget);
    _replace(feed.window);
    _sub = feed.changes.listen(_accept);
    _publishSnapshot();
  }

  /// A binding over the default chat registries.
  factory ConversationBinding.chat(
    MutableEventSource feed, {
    FlushScheduler? scheduler,
  }) {
    final r = defaultChatRegistries();
    return ConversationBinding(
      feed,
      assembler: ConversationAssembler(r.events, r.views),
      scheduler: scheduler,
    );
  }

  final MutableEventSource _feed;
  final ConversationAssembler _assembler;
  final FlushScheduler _scheduler;
  late final StreamSubscription<EventWindow> _sub;
  int _revision = -1;

  /// The latest chat snapshot.
  final Observable<ChatSnapshot> chat = Observable(ChatSnapshot.empty);

  /// The open turn number, null unless the latest turn started and is open.
  final Observable<int?> openTurn = Observable(null);

  MutableEventSource get feed => _feed;

  List<ConvEvent> _events(Iterable<EventEntry> e) => [
    for (final x in e) ConvEvent(x),
  ];

  void _replace(EventWindow w) {
    _revision = w.revision;
    _publish(_assembler.replaceWindow(_events(w.entries), w.hasMore));
  }

  void _accept(EventWindow w) {
    if (w.revision == _revision) return;
    if (w.revision != _revision + 1 || w.change == WindowChangeKind.replace) {
      _replace(w);
      return;
    }
    _revision = w.revision;
    switch (w.change) {
      case WindowChangeKind.prepend:
        _publish(_assembler.prepend(_events(w.delta), w.hasMore));
      case WindowChangeKind.append:
        var publication = Publication.none;
        for (final e in w.delta) {
          final next = _assembler.append(ConvEvent(e));
          if (next == Publication.immediate ||
              publication == Publication.none) {
            publication = next;
          }
        }
        _publish(publication);
      case WindowChangeKind.settleAssistant:
        _publish(
          _assembler.settleAssistant(
            w.settledAttemptId!,
            w.settlement == null ? null : ConvEvent(w.settlement!),
          ),
        );
      case WindowChangeKind.replace:
        break;
    }
  }

  void _publish(Publication p) {
    switch (p) {
      case Publication.none:
        return;
      case Publication.animationFrame:
        _scheduler.schedule(_flush);
      case Publication.immediate:
        _scheduler.cancel();
        _flush();
    }
  }

  void _flush() {
    if (_assembler.flush()) _publishSnapshot();
    openTurn.set(_assembler.openTurn());
  }

  void _publishSnapshot() {
    final s = _assembler.snapshot(chatTarget);
    if (s is ChatSnapshot) chat.set(s);
  }

  Future<void> dispose() async {
    _scheduler.cancel();
    await _sub.cancel();
  }
}
