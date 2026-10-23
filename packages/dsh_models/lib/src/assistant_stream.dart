import 'event_window.dart';

/// One timed model chunk (dsh `TimedStreamChunk`).
typedef TimedChunk = ({num time, Map<String, Object?> chunk});

/// Expand the compact records embedded in a durable assistant attempt
/// (dsh `expandAssistantStream`): packed `text-chunks` / `reasoning-chunks` /
/// `tool-call-chunks` runs become one chunk per member, a raw `chunk` stays.
List<TimedChunk> expandAssistantStream(List<Object?> stream) {
  final out = <TimedChunk>[];
  for (final candidate in stream) {
    if (candidate is! Map<String, Object?>) {
      throw const FormatException('assistant stream record is not an object');
    }
    final type = candidate['type'];
    if (type == 'chunk') {
      out.add((
        time: candidate['time']! as num,
        chunk: Map<String, Object?>.from(candidate['chunk']! as Map),
      ));
      continue;
    }
    final members =
        (type == 'tool-call-chunks' ? candidate['args'] : candidate['texts'])!
            as List;
    final dt = candidate['dt']! as List;
    var time = candidate['time0']! as num;
    for (var i = 0; i < members.length; i++) {
      if (i > 0) time += dt[i - 1]! as num;
      final Map<String, Object?> chunk;
      switch (type) {
        case 'text-chunks':
          chunk = {
            'type': 'text-delta',
            'index': candidate['index'],
            'text': members[i],
          };
        case 'reasoning-chunks':
          chunk = {
            'type': 'reasoning-delta',
            'index': candidate['index'],
            'text': members[i],
          };
        case 'tool-call-chunks':
          chunk = {
            'type': 'tool-call-delta',
            'index': candidate['index'],
            'id': candidate['id'],
            if (candidate.containsKey('name')) 'name': candidate['name'],
            'argumentsDelta': members[i],
          };
        default:
          throw FormatException('unknown assistant stream record $type');
      }
      out.add((time: time, chunk: chunk));
    }
  }
  return out;
}

/// One publication decision of the fold (dsh `ClientAssistantStreamResult`).
sealed class AssistantResult {
  const AssistantResult();
}

class PublishDurable extends AssistantResult {
  const PublishDurable(this.entry, {this.retireAttemptId});
  final EventEntry entry;

  /// Retire the successful attempt's transient rows after publishing Step end.
  final String? retireAttemptId;
}

class SettleAssistant extends AssistantResult {
  const SettleAssistant(this.attemptId, this.entry);
  final String attemptId;
  final EventEntry entry;
}

class AbandonAttempt extends AssistantResult {
  const AbandonAttempt(this.attemptId);
  final String attemptId;
}

class TransientChunk extends AssistantResult {
  const TransientChunk(this.entry);
  final EventEntry entry;
}

/// The fold lost sync (index gap, unexpected start); reopen follow once.
class Rebaseline extends AssistantResult {
  const Rebaseline();
}

class _Attempt {
  _Attempt(
    this.attemptId,
    this.startedAfterSeq,
    this.turn,
    this.step,
    this.nextIndex,
  );
  final String attemptId;
  final num startedAfterSeq;
  final num turn;
  final num step;
  int nextIndex;
}

/// Joins transient assistant frames to the one durable settlement that
/// supersedes them (dsh `ClientAssistantStream`). Live chunks are presentation
/// only; reconnect and paged history reproduce the same assistant state from
/// durable settlements, so no token rows are persisted.
class ClientAssistantStream {
  _Attempt? _active;
  ({String attemptId, num turn, num step})? _retained;
  final Map<num, EventEntry> _pending = {};
  Set<num> _published = {};
  num _durableCursor = -1;
  int _transientInGap = 0;

  /// Replace the durable window and adopt an optional reconnect baseline
  /// (`{revision, activeAttempt?}`); returns the visible entries including
  /// the reconstructed transient prefix.
  List<EventEntry> replace(
    List<EventEntry> entries,
    Map<String, Object?>? baseline,
  ) {
    _pending.clear();
    _transientInGap = 0;
    _active = null;
    _retained = null;
    final opening = baseline?['activeAttempt'] as Map<String, Object?>?;
    if (opening != null) {
      _active = _Attempt(
        opening['attemptId']! as String,
        opening['startedAfterSeq']! as num,
        opening['turn']! as num,
        opening['step']! as num,
        (opening['nextIndex']! as num).toInt(),
      );
    }
    final visible = [...entries];
    _published = visible.map((e) => e.seq).toSet();
    _durableCursor = visible.fold<num>(-1, (c, e) => e.seq > c ? e.seq : c);
    if (opening != null) {
      final expanded = expandAssistantStream(opening['stream']! as List);
      final next = (opening['nextIndex']! as num).toInt();
      for (var i = 0; i < expanded.length; i++) {
        _transientInGap += 1;
        visible.add(
          EventEntry({
            'type': 'assistant/live-chunk',
            'seq': _durableCursor + 1 - 1 / (_transientInGap + 1),
            'time': expanded[i].time,
            'data': {
              'attemptId': opening['attemptId'],
              'turn': opening['turn'],
              'step': opening['step'],
              'chunk': expanded[i].chunk,
            },
          }, transient: true),
        );
        if (i + 1 >= next) break;
      }
    }
    return visible;
  }

  /// Stage or publish one newly followed durable entry.
  AssistantResult? acceptDurable(EventEntry entry) {
    _durableCursor = entry.seq > _durableCursor ? entry.seq : _durableCursor;
    _transientInGap = 0;
    if (_isSettlement(entry) && _attemptFor(entry) != null) {
      if (_pending.containsKey(entry.seq)) return const Rebaseline();
      _pending[entry.seq] = entry;
      return null;
    }
    return _publish(entry);
  }

  /// Fold one dense transient frame and release its named durable settlement.
  AssistantResult? acceptFrame(Map<String, Object?> frame) {
    switch (frame['type']) {
      case 'start':
        if (_active != null || _retained != null || _pending.isNotEmpty) {
          return const Rebaseline();
        }
        _pending.clear();
        _active = _Attempt(
          frame['attemptId']! as String,
          frame['startedAfterSeq']! as num,
          frame['turn']! as num,
          frame['step']! as num,
          0,
        );
        return null;
      case 'chunk':
        final attempt = _active;
        // A client mounted after the host saw this attempt has no start frame;
        // its durable settlement publishes directly, so the suffix is ignored.
        if (attempt == null || attempt.attemptId != frame['attemptId']) {
          return null;
        }
        if (frame['index'] != attempt.nextIndex) return const Rebaseline();
        attempt.nextIndex += 1;
        _transientInGap += 1;
        return TransientChunk(
          EventEntry({
            'type': 'assistant/live-chunk',
            'seq': _durableCursor + 1 - 1 / (_transientInGap + 1),
            'time': frame['time'],
            'data': {
              'attemptId': frame['attemptId'],
              'turn': attempt.turn,
              'step': attempt.step,
              'chunk': frame['chunk'],
            },
          }, transient: true),
        );
      case 'end':
        final attempt = _active;
        if (attempt == null || attempt.attemptId != frame['attemptId']) {
          return null;
        }
        _active = null;
        if (frame['index'] != attempt.nextIndex) return const Rebaseline();
        final outcome = frame['outcome']! as Map<String, Object?>;
        if (outcome['kind'] == 'abandoned') {
          return _pending.isEmpty
              ? AbandonAttempt(attempt.attemptId)
              : const Rebaseline();
        }
        final seq = outcome['seq']! as num;
        if (_published.contains(seq)) return null;
        final entry = _pending[seq];
        if (entry == null || entry.type != outcome['eventType']) {
          return const Rebaseline();
        }
        _pending.remove(seq);
        final data = entry.data as Map<String, Object?>?;
        if (entry.type == 'assistant/message' && data?['interrupted'] != true) {
          _retained = (
            attemptId: attempt.attemptId,
            turn: attempt.turn,
            step: attempt.step,
          );
          return _publish(entry);
        }
        _published.add(entry.seq);
        return SettleAssistant(attempt.attemptId, entry);
    }
    return null;
  }

  bool _isSettlement(EventEntry e) =>
      e.type == 'assistant/message' || e.type == 'assistant/attempt';

  _Attempt? _attemptFor(EventEntry e) {
    final attempt = _active;
    final data = e.data as Map<String, Object?>?;
    if (attempt == null ||
        (e.type == 'assistant/message' && e.event['surfaceOp'] != 'append') ||
        e.seq <= attempt.startedAfterSeq ||
        data == null ||
        attempt.turn != data['turn'] ||
        attempt.step != data['step']) {
      return null;
    }
    return attempt;
  }

  AssistantResult _publish(EventEntry entry) {
    _published.add(entry.seq);
    final retained = _retained;
    final data = entry.data as Map<String, Object?>?;
    if (retained != null &&
        entry.type == 'step/end' &&
        data?['turn'] == retained.turn &&
        data?['step'] == retained.step) {
      _retained = null;
      return PublishDurable(entry, retireAttemptId: retained.attemptId);
    }
    return PublishDurable(entry);
  }
}
