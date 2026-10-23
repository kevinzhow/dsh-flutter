import 'dart:async';
import 'dart:collection';

import 'package:dsh_client/dsh_client.dart';

import 'event_window.dart';

/// One complete event-window change (dsh `SessionJournalChange`).
sealed class JournalChange {
  const JournalChange();
}

/// Opening snapshot of a follow generation, or a gap-repair page.
class JournalReplace extends JournalChange {
  const JournalReplace(
    this.entries,
    this.hasMore, {
    this.projections,
    this.assistantStream,
  });
  final List<EventEntry> entries;
  final bool hasMore;

  /// Follow snapshot only: `{asOfSeq, values}`.
  final Map<String, Object?>? projections;

  /// Follow snapshot only: `{revision, activeAttempt?}`.
  final Map<String, Object?>? assistantStream;
}

class JournalPrepend extends JournalChange {
  const JournalPrepend(this.entries, this.hasMore);
  final List<EventEntry> entries;
  final bool hasMore;
}

class JournalAppend extends JournalChange {
  const JournalAppend(this.entry);
  final EventEntry entry;
}

/// A cursorless `assistant-stream` frame.
class JournalNotification extends JournalChange {
  const JournalNotification(this.frame);
  final Map<String, Object?> frame;
}

/// The host broke the stream contract (dsh `protocolViolation`).
class ProtocolViolation extends RemoteException {
  ProtocolViolation(String message) : super('gateway/internal', message);
}

class _Tagged {
  _Tagged(this.epoch, this.frame);
  final int epoch;
  final GenerationFrame frame;
}

/// Snapshot-first opening, ordered live delivery, pagination and gap repair
/// over a reopening follow stream (dsh `RemoteJournalStream`, specialised to
/// the session log: cursors are inclusive `seq` integers, `follows` is `+1`).
///
/// The published window is retained across reconnects; a replacement is
/// published only after the opening snapshot reaches the generation's cursor.
/// Frames are processed serially, so entries that arrive while a repair page is
/// in flight queue behind it and are merged into the replacement, and
/// notifications never overtake an in-flight repair.
class SessionJournal {
  SessionJournal({
    required Stream<GenerationFrame> Function() openFollow,
    required Future<Map<String, Object?>> Function(Map<String, Object?> request)
    readPage,
    required void Function(JournalChange change) publish,
    required void Function(Object error) failed,
    Map<String, Object?> Function()? pageAddress,
  }) : _openFollow = openFollow,
       _readPage = readPage,
       _publish = publish,
       _failed = failed,
       _pageAddress = pageAddress ?? (() => const {});

  final Stream<GenerationFrame> Function() _openFollow;
  final Future<Map<String, Object?>> Function(Map<String, Object?>) _readPage;
  final void Function(JournalChange) _publish;
  final void Function(Object) _failed;
  final Map<String, Object?> Function() _pageAddress;

  final Queue<_Tagged> _queue = Queue();
  StreamSubscription<GenerationFrame>? _sub;
  Completer<void>? _opening;
  int _epoch = 0; // bumped on every StreamOpened
  int _currentEpoch = -1; // epoch whose snapshot is applied
  bool _opened = false;
  bool _disposed = false;
  bool _draining = false;
  int? _first;
  int _last = -1;
  int? _assistantRevision;
  Map<String, Object?> _initialRequest = const {};

  /// Open follow and publish the opening snapshot (first complete window).
  Future<void> open(Map<String, Object?> pageOptions) {
    if (_sub != null) throw StateError('session journal already opened');
    _initialRequest = pageOptions;
    final c = _opening = Completer<void>();
    _subscribe();
    return c.future;
  }

  void _subscribe() {
    _sub = _openFollow().listen(_enqueue, onDone: () {});
  }

  /// Replace the physical generation while retaining the published window
  /// (dsh `restart`): used after an assistant-stream rebaseline.
  void restart() {
    if (_disposed) return;
    unawaited(_sub?.cancel());
    _subscribe();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _queue.clear();
    final o = _opening;
    if (o != null && !o.isCompleted) o.completeError(StateError('disposed'));
  }

  /// Read and prepend one older page after a successful open.
  Future<void> prepend(Map<String, Object?> request) async {
    if (!_opened || _disposed) throw StateError('session journal is not open');
    final page = await _readPage({
      ..._pageAddress(),
      'throughSeq': _last,
      ...request,
    });
    final all = _entries(page);
    _assertContiguous(all);
    final before = _first;
    final accepted = before == null
        ? all
        : all.where((e) => e.seq < before).toList();
    if (accepted.isNotEmpty &&
        before != null &&
        accepted.last.seq.toInt() + 1 != before) {
      _publish(const JournalPrepend([], false));
      throw ProtocolViolation(
        'session event stream history page is discontinuous',
      );
    }
    if (accepted.isNotEmpty) _first = accepted.first.seq.toInt();
    _publish(JournalPrepend(accepted, page['hasMore'] == true));
  }

  void _enqueue(GenerationFrame frame) {
    if (_disposed) return;
    if (frame is StreamOpened) _epoch++;
    _queue.add(_Tagged(_epoch, frame));
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        await _handle(_queue.removeFirst());
      }
    } on Object catch (e) {
      _fail(e);
    } finally {
      _draining = false;
    }
  }

  void _fail(Object error) {
    final o = _opening;
    if (o != null && !o.isCompleted) {
      o.completeError(error);
    } else if (!_disposed) {
      _failed(error);
    }
  }

  Future<void> _handle(_Tagged tagged) async {
    final frame = tagged.frame;
    switch (frame) {
      case StreamOpened():
        return;
      case StreamEnded(:final error):
        if (error is RemoteException && error is! CarrierLost) {
          _fail(error);
        } else if (error == null && _opened) {
          // A clean end without a terminal result is a carrier failure in dsh:
          // reopen on the same generation.
          restart();
        }
        return;
      case StreamItem(:final value):
        await _item(tagged.epoch, value);
    }
  }

  Future<void> _item(int epoch, Object? raw) async {
    if (raw is! Map<String, Object?>) {
      throw ProtocolViolation('session follow emitted a non-object frame');
    }
    switch (raw['type']) {
      case 'snapshot':
        _applySnapshot(epoch, raw);
      case 'assistant-stream':
        if (!_opened) {
          throw ProtocolViolation(
            'session follow emitted an entry before its opening cursor',
          );
        }
        final frame = raw['frame']! as Map<String, Object?>;
        final expected = (_assistantRevision ?? 0) + 1;
        if (frame['revision'] != expected) {
          // dsh: RemoteStreamCarrierError -> physical restart, window retained.
          restart();
          return;
        }
        _assistantRevision = expected;
        _publish(JournalNotification(frame));
      case 'event':
        if (!_opened) {
          throw ProtocolViolation(
            'session follow emitted an entry before its opening cursor',
          );
        }
        await _acceptEntry(epoch, EventEntry.fromRecord(raw));
      default:
        throw ProtocolViolation('unknown follow frame ${raw['type']}');
    }
  }

  List<EventEntry> _entries(Map<String, Object?> page) => [
    for (final r in page['records']! as List) EventEntry.fromRecord(r),
  ];

  void _assertContiguous(List<EventEntry> entries) {
    for (var i = 1; i < entries.length; i++) {
      if (entries[i - 1].seq.toInt() + 1 != entries[i].seq.toInt()) {
        throw ProtocolViolation(
          'session event stream page contains discontinuous entries',
        );
      }
    }
  }

  num _tail(List<EventEntry> entries) =>
      entries.isEmpty ? -1 : entries.last.seq;

  void _applySnapshot(int epoch, Map<String, Object?> snap) {
    final resumed = _opened;
    final cursor = (snap['cursor']! as num).toInt();
    if (resumed && cursor < _last) {
      throw ProtocolViolation(
        'session event stream resumed at a cursor behind the last applied entry',
      );
    }
    final entries = _entries(snap);
    if (_tail(entries) != cursor) {
      throw ProtocolViolation(
        'session event stream page did not end at its requested cursor',
      );
    }
    _assertContiguous(entries);
    final assistant = snap['assistantStream'];
    if (assistant is! Map<String, Object?>) {
      throw ProtocolViolation(
        'session assistant stream omitted its opted-in opening baseline',
      );
    }
    _assistantRevision = (assistant['revision']! as num).toInt();
    _currentEpoch = epoch;
    _first = entries.isEmpty ? null : entries.first.seq.toInt();
    _last = cursor;
    _publish(
      JournalReplace(
        entries,
        snap['hasMore'] == true,
        projections: snap['projections'] as Map<String, Object?>?,
        assistantStream: assistant,
      ),
    );
    if (!_opened) {
      _opened = true;
      _opening?.complete();
    }
  }

  Future<void> _acceptEntry(int epoch, EventEntry entry) async {
    if (epoch != _currentEpoch) return;
    final first = entry.seq.toInt();
    final cursor = first;
    if (cursor <= _last) return;
    if (first != _last + 1) {
      await _repair(epoch, entry);
      return;
    }
    _first ??= first;
    _last = cursor;
    _publish(JournalAppend(entry));
  }

  /// Gap: read a page through the triggering entry, merge entries that queued
  /// behind it, publish one replacement. A newer generation supersedes it.
  Future<void> _repair(int epoch, EventEntry trigger) async {
    final queued = <EventEntry>[trigger];
    final notifications = <Map<String, Object?>>[];

    // Pull in-flight entries that already arrived on this epoch.
    void absorb() {
      while (_queue.isNotEmpty && _queue.first.epoch == epoch) {
        final f = _queue.first.frame;
        if (f is! StreamItem || f.value is! Map<String, Object?>) break;
        final v = f.value! as Map<String, Object?>;
        if (v['type'] == 'event') {
          queued.add(EventEntry.fromRecord(v));
        } else if (v['type'] == 'assistant-stream') {
          notifications.add(v['frame']! as Map<String, Object?>);
        } else {
          break;
        }
        _queue.removeFirst();
      }
    }

    Future<Map<String, Object?>?> read(int through) async {
      try {
        final page = await _readPage({
          ..._pageAddress(),
          'throughSeq': through,
          ..._repairRequest(),
        });
        return page;
      } on RemoteException catch (e) {
        // Transport loss: the next generation's snapshot replaces the window.
        if (e is CarrierLost ||
            e is NotConnected ||
            e is UnauthorizedException) {
          return null;
        }
        rethrow;
      }
    }

    absorb();
    var target = queued
        .map((e) => e.seq.toInt())
        .reduce((a, b) => a > b ? a : b);
    var page = await read(target);
    if (page == null) return;
    absorb();
    // A newer generation arrived while the page was in flight: drop the repair.
    if (_queue.any((t) => t.epoch != epoch)) return;
    var entries = _merge(page, queued);
    target = queued
        .map((e) => e.seq.toInt())
        .fold(target, (a, b) => a > b ? a : b);
    if (entries == null || _tail(entries) < target) {
      page = await read(target);
      if (page == null) return;
      absorb();
      if (_queue.any((t) => t.epoch != epoch)) return;
      entries = _merge(page, queued);
      target = queued
          .map((e) => e.seq.toInt())
          .fold(target, (a, b) => a > b ? a : b);
    }
    if (entries == null || _tail(entries) < target) {
      throw ProtocolViolation(
        'session event stream page did not reach its opening cursor',
      );
    }
    _first = entries.isEmpty ? null : entries.first.seq.toInt();
    _last = _tail(entries).toInt();
    _publish(JournalReplace(entries, page['hasMore'] == true));
    for (final n in notifications) {
      _publish(JournalNotification(n));
    }
  }

  Map<String, Object?> _repairRequest() => {
    if (_initialRequest['maxMessages'] != null)
      'maxMessages': _initialRequest['maxMessages'],
    if (_initialRequest['turnWindow'] != null)
      'turnWindow': _initialRequest['turnWindow'],
  };

  List<EventEntry>? _merge(Map<String, Object?> page, List<EventEntry> queued) {
    final entries = _entries(page);
    _assertContiguous(entries);
    final sorted = [...queued]..sort((a, b) => a.seq.compareTo(b.seq));
    var tail = _tail(entries);
    for (final e in sorted) {
      if (e.seq <= tail) continue;
      if (e.seq.toInt() != tail.toInt() + 1) return null;
      entries.add(e);
      tail = e.seq;
    }
    return entries;
  }
}
