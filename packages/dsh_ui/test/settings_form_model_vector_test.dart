// Replays the dsh-settings-vector/1 `form-model` fixture through the Dart
// SettingsFormModel. The expectations come from dsh's own TypeScript model
// (tool/vectors, gen_settings_expected.py): after every step of a scripted
// scope, the shell state, every field state, the projection the bound store
// holds, and the wire calls must be identical.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/settings_form_model_vector.json').readAsStringSync(),
  ) as Map<String, Object?>;
  if (fixture['format'] != 'dsh-settings-vector/1' ||
      fixture['kind'] != 'form-model') {
    throw StateError('not a dsh-settings-vector/1 form-model fixture');
  }
  final steps = (fixture['steps'] as List).cast<Map<String, Object?>>();
  final expected = (fixture['expected'] as List).cast<Map<String, Object?>>();

  test('every step leaves the model as the TypeScript model does', () async {
    expect(expected, hasLength(steps.length));
    _World? world;
    var name = '?';
    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];
      Object? error;
      if (step['op'] == 'start') {
        name = '${step['name']}';
        world = _World(step);
      } else {
        try {
          world!.apply(step);
        } on Object catch (caught) {
          error = caught is StateError ? caught.message : '$caught';
        }
      }
      await _settle();
      final actual = _normalize(world!.encode(error));
      final want = _normalize(expected[index]);
      if (jsonEncode(actual) != jsonEncode(want)) {
        fail(
          'step $index (${step['op']}, $name) differs\n'
          '  step: ${jsonEncode(step)}\n'
          '  ts:   ${jsonEncode(want)}\n'
          '  dart: ${jsonEncode(actual)}',
        );
      }
    }
  });
}

Object? _normalize(Object? value) => jsonDecode(jsonEncode(value));

Future<void> _settle() async {
  for (var round = 0; round < 25; round++) {
    await Future<void>.delayed(Duration.zero);
  }
}

SettingsFormScopeSnapshot _snapshot(Map<String, Object?> json) =>
    SettingsFormScopeSnapshot(
      status: SettingsScopeStatus.values.byName('${json['status']}'),
      value: json['value'],
      base: json['base'],
      user: json['user'],
      writable: json['writable'] == true,
      revision: json['revision'] as int?,
    );

/// The scripted scope: snapshots set by steps, writes parked until answered.
class _World implements SettingsFormScope {
  _World(Map<String, Object?> start) {
    snapshot = _snapshot((start['snapshot'] as Map).cast<String, Object?>());
    final specs = (start['specs'] as List).cast<Map<String, Object?>>();
    final secretFields = [
      for (final field in (start['secrets'] as List?) ?? const []) '$field',
    ];
    fieldNames = [
      for (final spec in specs) '${spec['field']}',
      ...secretFields,
    ];
    form = SettingsFormModel(
      this,
      [
        for (final spec in specs)
          spec['kind'] == 'number'
              ? settingsNumberField('${spec['field']}')
              : settingsTextField('${spec['field']}'),
      ],
      [
        for (final field in secretFields)
          SettingsSecretSpec(
            field: field,
            write: (text) => _park('secret:$field', {
              'call': 'secret',
              'field': field,
              'text': text,
            }),
          ),
      ],
    );
    store = form.bind(_project);
    actions = form.actions();
  }

  @override
  late SettingsFormScopeSnapshot snapshot;
  final List<void Function()> _listeners = [];
  final List<Map<String, Object?>> _calls = [];
  final Map<String, List<Object?>> _queued = {};
  final Map<String, List<Completer<bool>>> _waiting = {};
  late final List<String> fieldNames;
  late final SettingsFormModel form;
  late final SettingsFormStore<Map<String, Object?>> store;
  late final SettingsFormActions actions;

  @override
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  Future<bool> mutate(List<SettingsFormPathOp> ops, {int? expectedRevision}) =>
      _park('mutate', {
        'call': 'mutate',
        'ops': [
          for (final op in ops)
            switch (op) {
              SettingsFormSetOp() => {
                'op': 'set',
                'path': op.path,
                'value': op.value,
              },
              SettingsFormUnsetOp() => {'op': 'unset', 'path': op.path},
            },
        ],
        'expectedRevision': expectedRevision,
      });

  Future<bool> _park(String key, Map<String, Object?> call) {
    _calls.add(call);
    final completer = Completer<bool>();
    final queued = _queued[key] ?? const [];
    if (queued.isNotEmpty) {
      _deliver(completer, (_queued[key]!).removeAt(0));
    } else {
      (_waiting[key] ??= []).add(completer);
    }
    return completer.future;
  }

  void _deliver(Completer<bool> call, Object? result) {
    if (result is Map) {
      call.completeError(StateError('${result['throw']}'));
    } else {
      call.complete(result == true);
    }
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void apply(Map<String, Object?> step) {
    switch (step['op']) {
      case 'scope':
        snapshot = _snapshot((step['snapshot'] as Map).cast<String, Object?>());
        _notify();
      case 'edit':
        actions.edit('${step['field']}', '${step['text']}');
      case 'reset':
        actions.resetField('${step['field']}');
      case 'save':
        actions.save();
      case 'discard':
        actions.discard();
      case 'dispose':
        form.dispose();
      case 'answer':
        final key = '${step['method']}';
        final scope = step['scope'];
        if (scope != null) {
          snapshot = _snapshot((scope as Map).cast<String, Object?>());
          _notify();
        }
        final waiting = _waiting[key] ?? const [];
        if (waiting.isEmpty) {
          (_queued[key] ??= []).add(step['result']);
        } else {
          _deliver(_waiting[key]!.removeAt(0), step['result']);
        }
      default:
        throw ArgumentError('unknown op ${step['op']}');
    }
  }

  Map<String, Object?> _project() => {'shell': _shell(), 'fields': _fields()};

  Map<String, Object?> _shell() {
    final shell = form.shell();
    return {
      'available': shell.available,
      'writable': shell.writable,
      'dirty': shell.dirty,
      'invalid': shell.invalid,
      'saving': shell.saving,
      'failed': shell.failed,
    };
  }

  Map<String, Object?> _fields() => {
    for (final name in fieldNames)
      name: {
        'text': form.field(name).text,
        'overridden': form.field(name).overridden,
        'invalid': form.field(name).invalid,
      },
  };

  Map<String, Object?> encode(Object? error) {
    final out = <String, Object?>{
      'shell': _shell(),
      'fields': _fields(),
      'bound': store.value,
      'calls': List.of(_calls),
      'error': ?error,
    };
    _calls.clear();
    return out;
  }
}
