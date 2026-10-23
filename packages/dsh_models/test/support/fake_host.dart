import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

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
