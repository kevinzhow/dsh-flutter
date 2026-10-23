import 'dart:async';
import 'dart:math';

import 'events.dart';
import 'mux.dart';
import 'pairing.dart';
import 'remote_caller.dart';
import 'unary.dart';

/// Where the connection is in dsh's generation lifecycle.
enum ConnectionState {
  /// Not started.
  idle,

  /// Exchanging the launch token (`GET /connect`).
  pairing,

  /// Opening the mux socket and waiting for the `$events` ready item.
  connecting,

  /// A generation is published: baselines may be fetched and streams opened.
  connected,

  /// The host refused the launch token (typically: host restarted and minted a
  /// new one). The loop is halted until [DshConnection.start] gets a new token.
  needsPairing,

  /// Stopped by the app.
  stopped,
}

/// One connection generation: a paired Peer, one mux socket, and the host's
/// `$events` ready item. Everything bound to it (logical streams, event
/// answers) is invalid once the generation ends.
class ConnectionGeneration {
  ConnectionGeneration._({
    required this.id,
    required this.clientId,
    required this.hostHome,
    required this.credential,
    required this.carrier,
    required this.caller,
  });

  /// Monotonic per [DshConnection]; the first generation is 1.
  final int id;

  /// `RemoteEventClientId` from the `ready` item (empty for `none` Peers).
  final String clientId;

  /// Host account home, for abbreviating displayed paths only.
  final String hostHome;
  final PairedCredential credential;
  final MuxCarrier carrier;
  final HttpRemoteCaller caller;
}

class NotConnected extends RemoteException {
  NotConnected() : super('connection/not-connected', 'no live generation');
}

/// A frame of a logical stream that reopens on every connection generation.
sealed class GenerationFrame {
  const GenerationFrame(this.generation);
  final int generation;
}

/// The stream is open on [generation]; consumers replace their window from the
/// next (snapshot) item, as dsh does for `session/follow`.
class StreamOpened extends GenerationFrame {
  const StreamOpened(super.generation);
}

class StreamItem extends GenerationFrame {
  const StreamItem(super.generation, this.value);
  final Object? value;
}

/// The stream is over for this generation (host `end`, a stream `error`, or the
/// socket going away). [error] is null for a clean host `end`. The stream
/// reopens automatically on the next generation.
class StreamEnded extends GenerationFrame {
  const StreamEnded(super.generation, this.error);
  final Object? error;
}

/// Retry delays after a lost generation: 500ms, 1s, 2s, 4s, 8s, then 10s,
/// each with 50%-100% jitter (docs: connection README, "Connection generation").
Duration reconnectDelay(int attempt, Random random) {
  const caps = [500, 1000, 2000, 4000, 8000, 10000];
  final cap = caps[min(attempt, caps.length - 1)];
  return Duration(
    milliseconds: (cap * (0.5 + random.nextDouble() / 2)).round(),
  );
}

/// Pairing + generations + `$events` + reopening logical streams, the Dart
/// counterpart of dsh's `ConnectionController`.
class DshConnection {
  DshConnection({
    required this.origin,
    this.interactions = Interactions.answer,
    this.readyTimeout = const Duration(seconds: 15),
    Random? random,
    Pairing? pairing,
  }) : _random = random ?? Random(),
       _pairing = pairing ?? Pairing();

  final Uri origin;
  final Interactions interactions;
  final Duration readyTimeout;
  final Random _random;
  final Pairing _pairing;

  ConnectionState _state = ConnectionState.idle;
  ConnectionGeneration? _generation;
  Object? _lastError;
  String? _token;
  int _generationCounter = 0;
  int _loopId = 0;
  bool _stopped = false;
  MuxCarrier? _liveCarrier;

  final _states = StreamController<ConnectionState>.broadcast();
  final _generations = StreamController<ConnectionGeneration?>.broadcast();
  final _events = StreamController<HostEvent>.broadcast();

  ConnectionState get state => _state;
  Stream<ConnectionState> get states => _states.stream;

  /// The live generation, or null while connecting or reconnecting.
  ConnectionGeneration? get generation => _generation;

  /// Publishes each new generation, and `null` when one is invalidated.
  Stream<ConnectionGeneration?> get generations => _generations.stream;

  /// Last pairing/transport failure, for diagnostics.
  Object? get lastError => _lastError;

  /// Forwarded host events of the live generation (needs `interactions=answer`).
  Stream<HostEvent> get hostEvents => _events.stream;

  /// Unary calls through the live generation's cookie.
  RemoteCaller get caller => _GenerationCaller(this);

  /// Begin (or restart after [ConnectionState.needsPairing]) with [launchToken].
  /// The token is kept in memory only; the app decides whether to persist it.
  void start(String launchToken) {
    _token = launchToken;
    _stopped = false;
    final id = ++_loopId;
    unawaited(_run(id));
  }

  Future<ConnectionGeneration> untilConnected({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final live = _generation;
    if (live != null) return live;
    return generations
        .firstWhere((g) => g != null)
        .timeout(timeout)
        .then((g) => g!);
  }

  Future<ConnectionState> untilState(
    bool Function(ConnectionState) test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (test(_state)) return _state;
    return states.firstWhere(test).timeout(timeout);
  }

  /// Drop the live socket now; the loop starts retry 1 immediately-ish
  /// (dsh `ctx.connection.reconnect()`).
  Future<void> dropForTesting() async => _liveCarrier?.close();

  Future<void> stop() async {
    _stopped = true;
    _loopId++;
    await _liveCarrier?.close();
    _setState(ConnectionState.stopped);
    _pairing.close();
  }

  void _setState(ConnectionState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  void _publish(ConnectionGeneration? g) {
    _generation = g;
    if (!_generations.isClosed) _generations.add(g);
  }

  Future<void> _run(int loopId) async {
    var attempt = 0;
    bool live() => !_stopped && loopId == _loopId;
    while (live()) {
      MuxCarrier? carrier;
      try {
        _setState(ConnectionState.pairing);
        final credential = await _pairing.pair(
          origin,
          _token!,
          interactions: interactions,
        );
        if (!live()) return;
        _setState(ConnectionState.connecting);
        carrier = await MuxCarrier.connect(credential, timeout: readyTimeout);
        _liveCarrier = carrier;
        if (!live()) {
          await carrier.close();
          return;
        }
        final generation = await _establish(credential, carrier);
        if (!live()) {
          await carrier.close();
          return;
        }
        attempt = 0;
        _publish(generation);
        _setState(ConnectionState.connected);
        await generation.carrier.closed;
      } on PairingRejected catch (e) {
        _lastError = e;
        _publish(null);
        _setState(ConnectionState.needsPairing);
        return;
      } on Object catch (e) {
        _lastError = e;
      } finally {
        if (loopId == _loopId && _generation != null) _publish(null);
        await carrier?.close();
        if (identical(_liveCarrier, carrier)) _liveCarrier = null;
      }
      if (!live()) return;
      _setState(ConnectionState.connecting);
      await Future<void>.delayed(reconnectDelay(attempt++, _random));
    }
  }

  /// Open `$events`, wait for `ready` (docs: only a ready item publishes
  /// `connected`), then pump the rest into [hostEvents].
  Future<ConnectionGeneration> _establish(
    PairedCredential credential,
    MuxCarrier carrier,
  ) async {
    final id = ++_generationCounter;
    final caller = HttpRemoteCaller(credential);
    if (interactions == Interactions.none) {
      return ConnectionGeneration._(
        id: id,
        clientId: '',
        hostHome: '',
        credential: credential,
        carrier: carrier,
        caller: caller,
      );
    }
    final stream = carrier.open(r'$events', {'args': <String, Object?>{}});
    final ready = Completer<Map<String, Object?>>();
    stream.items.listen(
      (item) {
        if (!ready.isCompleted) {
          if (item is Map<String, Object?> && item['type'] == 'ready') {
            ready.complete(item);
          } else {
            ready.completeError(
              RemoteException(
                'connection/bad-ready',
                'first \$events item was not ready',
              ),
            );
          }
          return;
        }
        final event = HostEvent.tryParse(id, item);
        if (event != null && !_events.isClosed) _events.add(event);
      },
      onError: (Object e) {
        if (!ready.isCompleted) ready.completeError(e);
      },
      onDone: () {
        // An ended `$events` stream invalidates the generation (dsh rule).
        if (!ready.isCompleted) {
          ready.completeError(CarrierLost(r'$events ended before ready'));
        }
        unawaited(carrier.close());
      },
    );
    final item = await ready.future.timeout(readyTimeout);
    final host = item['host'];
    return ConnectionGeneration._(
      id: id,
      clientId: '${item['clientId']}',
      hostHome: host is Map<String, Object?> ? '${host['home']}' : '',
      credential: credential,
      carrier: carrier,
      caller: caller,
    );
  }

  /// Answer a pending waterfall: `POST /api/$events/result`
  /// `{args: {clientId, eventId, outcome}}`. Only valid on the generation that
  /// delivered it.
  Future<void> answer(WaterfallEvent event, WaterfallOutcome outcome) async {
    final g = _generation;
    if (g == null || g.id != event.generation) throw NotConnected();
    await g.caller.call(r'$events', 'result', {
      'clientId': g.clientId,
      'eventId': event.eventId,
      'outcome': outcome.toJson(),
    });
  }

  /// Open a logical stream that follows generations: it opens on the live
  /// generation (and on every later one), emits [StreamOpened] first, then
  /// items, then [StreamEnded]. [args] is evaluated per generation so a
  /// consumer can resume from its latest cursor.
  Stream<GenerationFrame> openStream(
    String endpoint,
    Map<String, Object?> Function() args,
  ) {
    late StreamController<GenerationFrame> out;
    StreamSubscription<ConnectionGeneration?>? genSub;
    StreamSubscription<Object?>? itemSub;
    MuxStream? mux;
    int? openOn;

    Future<void> closeCurrent({Object? error, bool clean = false}) async {
      final on = openOn;
      openOn = null;
      final sub = itemSub;
      itemSub = null;
      final m = mux;
      mux = null;
      await sub?.cancel();
      if (m != null) await m.cancel();
      if (on != null && !out.isClosed) out.add(StreamEnded(on, error));
    }

    void attach(ConnectionGeneration g) {
      final MuxStream m;
      try {
        m = g.carrier.open(endpoint, {'args': args()});
      } on CarrierLost {
        return;
      }
      mux = m;
      openOn = g.id;
      out.add(StreamOpened(g.id));
      itemSub = m.items.listen(
        (v) => out.add(StreamItem(g.id, v)),
        onError: (Object e) => unawaited(closeCurrent(error: e)),
        onDone: () => unawaited(closeCurrent()),
      );
    }

    out = StreamController<GenerationFrame>(
      onListen: () {
        final current = _generation;
        if (current != null) attach(current);
        genSub = generations.listen((g) async {
          await closeCurrent(error: CarrierLost('generation ended'));
          if (g != null && !out.isClosed) attach(g);
        });
      },
      onCancel: () async {
        await genSub?.cancel();
        final sub = itemSub;
        itemSub = null;
        openOn = null;
        await sub?.cancel();
        await mux?.cancel();
      },
    );
    return out.stream;
  }
}

class _GenerationCaller implements RemoteCaller {
  _GenerationCaller(this._connection);
  final DshConnection _connection;

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) {
    final g = _connection.generation;
    if (g == null) throw NotConnected();
    return g.caller.call(namespace, method, args);
  }
}
