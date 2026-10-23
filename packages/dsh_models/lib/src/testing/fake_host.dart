import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import '../../dsh_models.dart';

/// One recorded unary call.
typedef Call = ({String ns, String method, Map<String, Object?> args});

/// A scriptable host: handlers answer unary calls by `namespace/method`, and
/// every call is recorded. A handler may throw a [RemoteException] (a Host
/// refusal) or any other error (a transport failure).
class FakeHost implements RemoteCaller {
  final List<Call> calls = [];
  final Map<String, FutureOr<Object?> Function(Map<String, Object?> args)>
  handlers = {};
  final StreamController<HostEvent> events = StreamController.broadcast(
    sync: true,
  );
  final StreamController<ConnectionGeneration?> gens =
      StreamController.broadcast(sync: true);

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add((ns: namespace, method: method, args: args));
    final handler = handlers['$namespace/$method'];
    if (handler == null) {
      throw StateError('no handler for $namespace/$method');
    }
    return handler(args);
  }

  List<Call> callsTo(String key) => [
    for (final c in calls)
      if ('${c.ns}/${c.method}' == key) c,
  ];

  HostRemotes get remotes => HostRemotes(
    caller: this,
    hostEvents: events.stream,
    generations: gens.stream,
  );

  void emit(String event, [List<Object?> args = const []]) =>
      events.add(EmitEvent(event, args));

  Future<void> close() async {
    await events.close();
    await gens.close();
  }
}

/// A serialized schemastery object schema: `{uid, refs}` over [fields]
/// (`name -> node`), nodes being `{type, meta, ...}` maps.
Map<String, Object?> objectSchema(Map<String, Map<String, Object?>> fields) {
  final refs = <String, Object?>{};
  final dict = <String, Object?>{};
  var uid = 1;
  for (final e in fields.entries) {
    refs['$uid'] = e.value;
    dict[e.key] = uid;
    uid++;
  }
  refs['$uid'] = {
    'type': 'object',
    'meta': {'default': <String, Object?>{}},
    'dict': dict,
  };
  return {'uid': uid, 'refs': refs};
}

Map<String, Object?> numberNode({
  num? min,
  num? max,
  num? step,
  num? defaultValue,
}) => {
  'type': 'number',
  'meta': {'step': ?step, 'min': ?min, 'max': ?max, 'default': ?defaultValue},
};

const Map<String, Object?> stringNode = {
  'type': 'string',
  'meta': <String, Object?>{},
};

/// One `settings.describe` namespace row.
Map<String, Object?> nsView(
  String ns, {
  required Map<String, Object?> schema,
  Map<String, Object?> value = const {},
  Map<String, Object?>? base,
  Map<String, Object?>? user,
  int revision = 0,
}) => {
  'applies': 'live',
  'autoGenerate': true,
  'ns': ns,
  'schema': schema,
  'value': value,
  'base': ?base,
  'user': ?user,
  'secrets': <Object?>[],
  'revision': revision,
};

Map<String, Object?> describeValue(
  List<Map<String, Object?>> namespaces, {
  bool writable = true,
}) => {'writable': writable, 'hasDocument': true, 'namespaces': namespaces};

/// Generations are only published, never inspected, by the settings services.
class FakeGeneration implements ConnectionGeneration {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A [ConfigForm] a test scripts directly: set [snapshot] and call [publish];
/// every write is recorded in [writes] and answers [answer].
class FakeConfigForm implements ConfigForm {
  FakeConfigForm([ConfigFormSnapshot? initial])
    : _snapshot = initial ?? const ConfigFormSnapshot();

  ConfigFormSnapshot _snapshot;
  final List<void Function()> _listeners = [];

  /// Every `mutate` call, in order.
  final List<({List<SettingsOp> ops, int? expectedRevision})> writes = [];

  /// What a write resolves to (false: refused).
  bool answer = true;

  /// Whether an accepted write is folded into [snapshot] (and published) the
  /// way the real form folds the Host's answer into the mirror.
  bool foldWrites = true;

  /// When set, a write waits for it before answering.
  Future<void>? gate;

  @override
  ConfigFormSnapshot get snapshot => _snapshot;

  /// Replace the snapshot and notify, as the mirror deriving a new view does.
  void publish(ConfigFormSnapshot next) {
    _snapshot = next;
    for (final l in [..._listeners]) {
      l();
    }
  }

  @override
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  Future<bool> mutate(List<SettingsOp> ops, {int? expectedRevision}) async {
    writes.add((ops: ops, expectedRevision: expectedRevision));
    await gate;
    if (answer && foldWrites) _fold(ops);
    return answer;
  }

  void _fold(List<SettingsOp> ops) {
    final value = {...?_snapshot.value};
    final user = <String, Object?>{
      if (_snapshot.user is Map) ...(_snapshot.user! as Map).cast(),
    };
    final base = _snapshot.base is Map
        ? (_snapshot.base! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    for (final op in ops) {
      final key = op.path.single;
      switch (op) {
        case SetOp():
          value[key] = op.value;
          user[key] = op.value;
        case UnsetOp():
          user.remove(key);
          if (base.containsKey(key)) {
            value[key] = base[key];
          } else {
            value.remove(key);
          }
      }
    }
    publish(
      ConfigFormSnapshot(
        status: ConfigFormStatus.ready,
        value: value,
        base: _snapshot.base,
        user: user,
        revision: (_snapshot.revision ?? 0) + 1,
        writable: _snapshot.writable,
      ),
    );
  }

  @override
  Future<bool> set(String field, Object? value) => mutate([
    SetOp([field], value),
  ]);

  @override
  Future<bool> unset(String field) => mutate([
    UnsetOp([field]),
  ]);

  /// The values written so far as `{field: value}` (unset fields map to null).
  Map<String, Object?> get written => {
    for (final w in writes)
      for (final op in w.ops) op.path.join('.'): op is SetOp ? op.value : null,
  };
}
