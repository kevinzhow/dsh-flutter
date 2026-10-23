import 'package:dsh_models/dsh_models.dart';

/// One event of the Session window as the conversation layer sees it (dsh
/// `SessionEventLike`): a durable log event or a client-only
/// `assistant/live-chunk` row. Wraps the wire map without copying it.
class ConvEvent {
  ConvEvent(this.entry);

  final EventEntry entry;

  String get type => entry.type;
  num get seq => entry.seq;
  num get time => (entry.event['time'] as num?) ?? 0;
  bool get transient => entry.transient;
  Object? get surfaceOp => entry.event['surfaceOp'];

  /// The event payload; an event without a map payload reads as empty.
  Map<String, Object?> get data {
    final d = entry.event['data'];
    return d is Map<String, Object?> ? d : const {};
  }

  /// dsh `isSurfaceEvent`: a message-producing type carrying its marker.
  bool get isSurfaceEvent => _surfaceTypes.contains(type) && surfaceOp != null;

  /// dsh `isAppendSurfaceEvent`.
  bool get isAppendSurface => isSurfaceEvent && surfaceOp == 'append';

  /// dsh `isReplacementSurfaceEvent`.
  bool get isReplacementSurface => isSurfaceEvent && surfaceOp != 'append';

  @override
  String toString() => 'ConvEvent($type #$seq)';
}

const _surfaceTypes = {
  'system/message',
  'developer/message',
  'user/message',
  'assistant/message',
  'tool/result',
};

/// JavaScript `String(seq)` for a log seq: integers print without a fraction.
String seqText(num seq) => seq == seq.truncate() ? '${seq.truncate()}' : '$seq';

/// A finite non-negative integer payload field, else null (dsh `coordinate`).
int? coordinate(Object? value) =>
    value is num && value == value.truncate() && value >= 0
    ? value.truncate()
    : null;
