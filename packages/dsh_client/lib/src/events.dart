/// Items of the Gateway-internal `$events` logical stream (docs: gateway
/// stream-protocol.ts "Forwarded host events"). The first item is `ready`
/// and is consumed by the connection; the rest are one of these.
sealed class HostEvent {
  const HostEvent();

  static HostEvent? tryParse(int generation, Object? item) {
    if (item is! Map<String, Object?>) return null;
    switch (item['type']) {
      case 'emit':
        final args = item['args'];
        return EmitEvent('${item['event']}', args is List ? args : const []);
      case 'waterfall':
        final request = item['request'];
        return WaterfallEvent(
          generation: generation,
          event: '${item['event']}',
          eventId: '${item['eventId']}',
          agentId: '${item['agentId']}',
          request: request is Map<String, Object?> ? request : const {},
        );
      case 'cancel':
        return CancelEvent('${item['eventId']}');
    }
    return null;
  }
}

/// A host notification (`api-session/status`, `settings/document-updated`, ...).
class EmitEvent extends HostEvent {
  const EmitEvent(this.event, this.args);
  final String event;
  final List<Object?> args;
}

/// A pending Agent-scoped question such as `approval/request` or
/// `user-questions/request`. It stays pending on the host until some answerer
/// replies through `POST /api/$events/result` (see `DshConnection.answer`).
class WaterfallEvent extends HostEvent {
  const WaterfallEvent({
    required this.generation,
    required this.event,
    required this.eventId,
    required this.agentId,
    required this.request,
  });

  /// Connection generation that delivered it; an answer is only valid for
  /// the `clientId` of that same generation.
  final int generation;
  final String event;
  final String eventId;
  final String agentId;
  final Map<String, Object?> request;
}

/// The host withdrew a pending waterfall (turn cancelled, another answerer won).
class CancelEvent extends HostEvent {
  const CancelEvent(this.eventId);
  final String eventId;
}

/// Client reply to a [WaterfallEvent] (`RemoteEventResult.outcome`).
sealed class WaterfallOutcome {
  const WaterfallOutcome();
  Map<String, Object?> toJson();
}

/// Delegate to the next answerer.
class WaterfallNext extends WaterfallOutcome {
  const WaterfallNext();
  @override
  Map<String, Object?> toJson() => {'kind': 'next'};
}

/// Claim the request with a result value (for approvals: one of
/// `allowed-once`, `rejected`, `cancelled`, `unavailable`).
class WaterfallResult extends WaterfallOutcome {
  const WaterfallResult(this.value);
  final Object? value;
  @override
  Map<String, Object?> toJson() => {'kind': 'result', 'value': value};
}

/// Reject the waterfall with an error.
class WaterfallRejected extends WaterfallOutcome {
  const WaterfallRejected(this.name, this.message, {this.code});
  final String name;
  final String message;

  /// Wire-preserved error code (`ASK_CANCELLED` for a dismissed question).
  final String? code;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'rejected',
    'error': {'name': name, 'message': message, 'code': ?code},
  };
}
