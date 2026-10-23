import 'observable.dart';

/// One entry of a Session event window (dsh `SessionEventLikeEntry`): a durable
/// log event, or a client-only `assistant/live-chunk` presentation row whose
/// fractional [seq] orders it between durable seqs.
class EventEntry {
  const EventEntry(this.event, {this.transient = false});

  /// Wire form `{type, seq, time, data, surfaceOp?, ...}`.
  final Map<String, Object?> event;
  final bool transient;

  num get seq => event['seq'] as num;
  String get type => event['type'] as String;
  Object? get data => event['data'];

  /// Wire history record `{type:'event', event}` (a `SessionHistoryRecord`).
  static EventEntry fromRecord(Object? record) {
    if (record is! Map<String, Object?> || record['event'] is! Map) {
      throw const FormatException('history record without event');
    }
    return EventEntry(Map<String, Object?>.from(record['event']! as Map));
  }
}

/// What produced the latest window revision (dsh `SessionEventChange`).
enum WindowChangeKind { replace, prepend, append, settleAssistant }

/// Immutable view of the contiguous Session event window.
class EventWindow {
  const EventWindow({
    required this.entries,
    required this.hasMore,
    required this.revision,
    required this.change,
  });

  static const empty = EventWindow(
    entries: [],
    hasMore: false,
    revision: 0,
    change: WindowChangeKind.replace,
  );

  final List<EventEntry> entries;
  final bool hasMore;
  final int revision;
  final WindowChangeKind change;
}

/// Session-owned feed; every accepted mutation publishes synchronously
/// (dsh `MutableSessionEventSource`).
class MutableEventSource {
  final Observable<EventWindow> _window = Observable(EventWindow.empty);

  EventWindow get window => _window.value;
  Stream<EventWindow> get changes => _window.changes;

  void _publish(List<EventEntry> entries, bool hasMore, WindowChangeKind kind) {
    _window.set(
      EventWindow(
        entries: List.unmodifiable(entries),
        hasMore: hasMore,
        revision: window.revision + 1,
        change: kind,
      ),
    );
  }

  void replace(List<EventEntry> entries, bool hasMore) =>
      _publish(entries, hasMore, WindowChangeKind.replace);

  void prepend(List<EventEntry> older, bool hasMore) => _publish(
    [...older, ...window.entries],
    hasMore,
    WindowChangeKind.prepend,
  );

  void append(EventEntry entry) => _publish(
    [...window.entries, entry],
    window.hasMore,
    WindowChangeKind.append,
  );

  /// Replace one attempt's transient rows with its durable settlement.
  void settleAssistant(String attemptId, EventEntry? settlement) {
    final entries = window.entries
        .where(
          (e) =>
              !(e.transient &&
                  (e.data as Map<String, Object?>)['attemptId'] == attemptId),
        )
        .toList();
    if (settlement != null) {
      final index = entries.indexWhere((e) => e.seq > settlement.seq);
      if (index < 0) {
        entries.add(settlement);
      } else {
        entries.insert(index, settlement);
      }
    }
    _publish(entries, window.hasMore, WindowChangeKind.settleAssistant);
  }
}
