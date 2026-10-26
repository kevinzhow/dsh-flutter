import 'package:dsh_models/dsh_models.dart';

class ScriptForm implements ConfigForm {
  ScriptForm(this.ns, Map<String, Object?> initial, this.calls)
    : _snapshot = ConfigFormSnapshot(
        status: ConfigFormStatus.ready,
        value: initial,
        base: Map.of(initial),
        user: {},
        writable: true,
        revision: 3,
      );
  final String ns;
  final List<Map<String, Object?>> calls;
  ConfigFormSnapshot _snapshot;
  final listeners = <void Function()>[];
  bool refuse = false;
  @override
  ConfigFormSnapshot get snapshot => _snapshot;
  @override
  void Function() subscribe(void Function() fn) {
    listeners.add(fn);
    return () => listeners.remove(fn);
  }

  void publish() {
    for (final fn in List.of(listeners)) {
      fn();
    }
  }

  void replace(Map<String, Object?> value) {
    _snapshot = ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: value,
      base: snapshot.base,
      user: snapshot.user,
      writable: true,
      revision: snapshot.revision! + 1,
    );
    publish();
  }

  @override
  Future<bool> mutate(List<SettingsOp> ops, {int? expectedRevision}) async {
    calls.add({
      'ns': ns,
      'ops': [
        for (final op in ops)
          switch (op) {
            SetOp() => {'op': 'set', 'path': op.path, 'value': op.value},
            UnsetOp() => {'op': 'unset', 'path': op.path},
          },
      ],
      'revision': expectedRevision,
    });
    if (refuse) {
      refuse = false;
      return false;
    }
    final user = Map<String, Object?>.from(snapshot.user as Map);
    for (final op in ops) {
      switch (op) {
        case SetOp():
          user[op.path.single] = op.value;
        case UnsetOp():
          user.remove(op.path.single);
      }
    }
    _snapshot = ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: {...(snapshot.base as Map).cast<String, Object?>(), ...user},
      base: snapshot.base,
      user: user,
      writable: true,
      revision: snapshot.revision! + 1,
    );
    publish();
    return true;
  }

  @override
  Future<bool> set(String field, Object? value) => mutate([
    SetOp([field], value),
  ]);
  @override
  Future<bool> unset(String field) => mutate([
    UnsetOp([field]),
  ]);
}
