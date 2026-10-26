import 'dart:async';
import 'dart:math';

import 'events.dart';
import 'mux.dart';
import 'pairing.dart';
import 'remote_caller.dart';
import 'trust.dart';
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

  /// A generation was lost or an attempt failed; the loop sleeps its backoff
  /// delay ([ConnectionStatus.retryAt]) before the next attempt. dsh web calls
  /// this `disconnected`: the outage is visible, the retry is scheduled.
  waiting,

  /// The host refused the launch token (typically: host restarted and minted a
  /// new one). The loop is halted until [DshConnection.start] gets a new token.
  needsPairing,

  /// The TLS handshake was refused by the trust policy: the host shows a
  /// certificate nobody confirmed, or a different one than the user pinned.
  /// The loop is halted (retrying would not change the answer) until the user
  /// decides: [DshConnection.start] again, after pinning or forgetting.
  certificateRefused,

  /// Stopped by the app.
  stopped,
}

/// A snapshot of the connection for display: what it is doing, which retry it
/// is on, when the next one starts, and why the last attempt failed.
class ConnectionStatus {
  const ConnectionStatus({
    required this.state,
    this.attempt = 0,
    this.retryAt,
    this.error,
    this.refusal,
  });

  final ConnectionState state;

  /// 0 until something failed; then the number of the retry that is waiting
  /// ([ConnectionState.waiting]) or in flight (`pairing` / `connecting`), dsh's
  /// `retry #N`. It restarts from 0 once a generation is up.
  final int attempt;

  /// When the sleeping loop wakes ([ConnectionState.waiting] only).
  final DateTime? retryAt;

  /// The last pairing or transport failure.
  final Object? error;

  /// Set with [ConnectionState.certificateRefused].
  final CertificateRefusal? refusal;

  /// Attempts failed this often in a row: the host is probably not reachable
  /// from here at all (off, wrong network), not just blinking.
  static const unreachableAfter = 3;

  /// The outage has lasted [unreachableAfter] retries and still goes on.
  bool get unreachable =>
      attempt >= unreachableAfter &&
      (state == ConnectionState.waiting ||
          state == ConnectionState.pairing ||
          state == ConnectionState.connecting);
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
    this.trust,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
    this.pingInterval = const Duration(seconds: 6),
  }) : _random = random ?? Random(),
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now,
       _pairing = pairing ?? Pairing();

  final Uri origin;
  final Interactions interactions;
  final Duration readyTimeout;

  /// Certificate trust of an https [origin]; null means the platform defaults.
  final HostTrust? trust;

  /// Keep-alive ping of the mux socket (see [MuxCarrier.connect]).
  final Duration pingInterval;
  final Random _random;
  final Pairing _pairing;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;

  ConnectionState _state = ConnectionState.idle;
  int _attempt = 0;
  DateTime? _retryAt;
  CertificateRefusal? _refusal;
  ConnectionGeneration? _generation;
  Object? _lastError;
  String? _token;
  int _generationCounter = 0;
  int _loopId = 0;
  bool _stopped = false;
  MuxCarrier? _liveCarrier;

  final _states = StreamController<ConnectionState>.broadcast();
  final _statuses = StreamController<ConnectionStatus>.broadcast();
  final _generations = StreamController<ConnectionGeneration?>.broadcast();
  final _events = StreamController<HostEvent>.broadcast();

  ConnectionState get state => _state;
  Stream<ConnectionState> get states => _states.stream;

  /// State plus retry number, next retry time and failure, for display.
  ConnectionStatus get status => ConnectionStatus(
    state: _state,
    attempt: _attempt,
    retryAt: _state == ConnectionState.waiting ? _retryAt : null,
    error: _lastError,
    refusal: _state == ConnectionState.certificateRefused ? _refusal : null,
  );

  /// Every change of [status] (state, retry number, next retry).
  Stream<ConnectionStatus> get statuses => _statuses.stream;

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

  /// Retry now instead of waiting out the backoff, or replace an attempt that
  /// is still in flight (dsh `ctx.connection.reconnect()`): the retry number
  /// starts over. Does nothing while connected, without a token, or once
  /// stopped; a halted connection (token refused, certificate refused) needs
  /// [start] with the user's decision instead.
  void reconnectNow() {
    final token = _token;
    if (token == null || _stopped) return;
    switch (_state) {
      case ConnectionState.waiting ||
          ConnectionState.pairing ||
          ConnectionState.connecting:
        start(token);
      case ConnectionState.idle ||
          ConnectionState.connected ||
          ConnectionState.needsPairing ||
          ConnectionState.certificateRefused ||
          ConnectionState.stopped:
        break;
    }
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
    final changed = _state != s;
    _state = s;
    if (changed && !_states.isClosed) _states.add(s);
    _emitStatus();
  }

  ConnectionStatus? _lastStatus;

  void _emitStatus() {
    final next = status;
    final last = _lastStatus;
    if (last != null &&
        last.state == next.state &&
        last.attempt == next.attempt &&
        last.retryAt == next.retryAt) {
      return;
    }
    _lastStatus = next;
    if (!_statuses.isClosed) _statuses.add(next);
  }

  void _publish(ConnectionGeneration? g) {
    _generation = g;
    if (!_generations.isClosed) _generations.add(g);
  }

  Future<void> _run(int loopId) async {
    var attempt = 0;
    _attempt = 0;
    _retryAt = null;
    bool live() => !_stopped && loopId == _loopId;
    while (live()) {
      MuxCarrier? carrier;
      trust?.clearRefusal(origin);
      try {
        _setState(ConnectionState.pairing);
        final credential = await _pairing.pair(
          origin,
          _token!,
          interactions: interactions,
          client: trust?.clientFor(origin),
        );
        if (!live()) return;
        _setState(ConnectionState.connecting);
        carrier = await MuxCarrier.connect(
          credential,
          timeout: readyTimeout,
          client: trust?.clientFor(origin),
          pingInterval: pingInterval,
        );
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
        _attempt = 0;
        _retryAt = null;
        _lastError = null;
        _publish(generation);
        _setState(ConnectionState.connected);
        await generation.carrier.closed;
      } on PairingRejected catch (e) {
        if (!live()) return;
        _lastError = e;
        _publish(null);
        _setState(ConnectionState.needsPairing);
        return;
      } on Object catch (e) {
        _lastError = e;
        final refusal = trust?.refusalBehind(origin, e);
        if (refusal != null && live()) {
          _refusal = refusal;
          _publish(null);
          _setState(ConnectionState.certificateRefused);
          return;
        }
      } finally {
        if (loopId == _loopId && _generation != null) _publish(null);
        await carrier?.close();
        if (identical(_liveCarrier, carrier)) _liveCarrier = null;
      }
      if (!live()) return;
      final delay = reconnectDelay(attempt, _random);
      _attempt = ++attempt;
      _retryAt = _clock().add(delay);
      _setState(ConnectionState.waiting);
      await _sleep(delay);
      if (!live()) return;
    }
  }

  /// Open `$events`, wait for `ready` (docs: only a ready item publishes
  /// `connected`), then pump the rest into [hostEvents].
  Future<ConnectionGeneration> _establish(
    PairedCredential credential,
    MuxCarrier carrier,
  ) async {
    final id = ++_generationCounter;
    final caller = HttpRemoteCaller(
      credential,
      httpClient: trust?.clientFor(origin),
    );
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
  ) => openDuplex(endpoint, args).frames;

  /// [openStream] with the uplink of the same logical stream (dsh `RemoteStream`
  /// with an `In` type): the returned handle sends items to the stream that is
  /// open on the live generation. Nothing is queued or replayed across
  /// generations: an item sent while no stream is open throws [NotConnected].
  GenerationStream openDuplex(
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
    return GenerationStream(
      out.stream,
      send: (value) {
        final m = mux;
        if (m == null) throw NotConnected();
        m.send(value);
      },
      end: () => mux?.end(),
    );
  }
}

/// A logical stream that reopens on every connection generation, plus the
/// uplink of whichever instance is open (see [DshConnection.openDuplex]).
class GenerationStream {
  GenerationStream(
    this.frames, {
    required void Function(Object?) send,
    required void Function() end,
  }) : _send = send,
       _end = end;

  /// Downlink: [StreamOpened], [StreamItem]s and [StreamEnded] per generation.
  final Stream<GenerationFrame> frames;
  final void Function(Object?) _send;
  final void Function() _end;

  /// Send one uplink item to the open instance. Throws [NotConnected] when the
  /// stream is not open on a live generation, or [CarrierLost] when the socket
  /// went away in the meantime; the item is not retained.
  void send(Object? item) => _send(item);

  /// Half-close the uplink of the open instance (no-op when none is open).
  void end() => _end();
}

class _GenerationCaller implements CancellableRemoteCaller {
  _GenerationCaller(this._connection);
  final DshConnection _connection;

  @override
  Future<Object?> callWithCancellation(
    String namespace,
    String method,
    Map<String, Object?> args,
    RemoteCancellation cancellation,
  ) {
    final g = _connection.generation;
    if (g == null) throw NotConnected();
    return ScopedRemoteCaller(
      g.caller,
      cancellation,
    ).call(namespace, method, args);
  }

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
