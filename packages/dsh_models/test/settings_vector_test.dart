// Replays the dsh-settings-vector/1 fixtures through the Dart settings models.
// The expectations come from dsh's own TypeScript code (tool/vectors,
// gen_settings_expected.py): the schema vector compares the verdict and, unless
// a case says `messageExact: false`, the failure text of every case; the form
// vector compares the describe mirror and every watched configuration form
// after each step of a scripted trace.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_settings.dart' as wire;
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

Map<String, Object?> loadFixture(String name, String kind) {
  final fixture = jsonDecode(
    File('test/fixtures/$name').readAsStringSync(),
  ) as Map<String, Object?>;
  if (fixture['format'] != 'dsh-settings-vector/1' || fixture['kind'] != kind) {
    throw StateError('$name is not a dsh-settings-vector/1 $kind fixture');
  }
  return fixture;
}

void main() {
  group('schema vector', () {
    final fixture = loadFixture('settings_schema_vector.json', 'schema');
    final schemas = (fixture['schemas'] as Map).cast<String, Object?>();
    final cases = (fixture['cases'] as List).cast<Map<String, Object?>>();

    test('every case gets the verdict and message of the TypeScript client', () {
      final mismatches = <String>[];
      for (final entry in cases) {
        final ref = entry['schemaRef'];
        final envelope = ref is String ? schemas[ref] : entry['schema'];
        final expected = entry['expect'] as String?;
        final exact = entry['messageExact'] != false;
        // Each case validates its own copy: validation must not depend on state
        // left by an earlier case.
        final actual = SettingsSchema.rehydrate(
          jsonDecode(jsonEncode(envelope)),
        ).validate(jsonDecode(jsonEncode(entry['value'])));
        final same = (expected == null || actual == null)
            ? expected == actual
            : (!exact || expected == actual);
        if (!same) {
          mismatches.add(
            '${entry['name']}\n    ts:   ${jsonEncode(expected)}\n    dart: ${jsonEncode(actual)}',
          );
        }
      }
      if (mismatches.isNotEmpty) {
        fail(
          '${mismatches.length} of ${cases.length} cases differ:\n'
          '${mismatches.take(40).join('\n')}',
        );
      }
    });

    test('the fixture covers accepted and refused values of every schema', () {
      final accepted = cases.where((c) => c['expect'] == null).length;
      expect(cases.length, greaterThan(3000));
      expect(accepted, greaterThan(500));
      expect(cases.length - accepted, greaterThan(500));
    });
  });

  group('form vector', () {
    final fixture = loadFixture('settings_form_vector.json', 'form');
    final steps = (fixture['steps'] as List).cast<Map<String, Object?>>();
    final expected = (fixture['expected'] as List).cast<Map<String, Object?>>();

    test('every step leaves the mirror and the forms as the TypeScript client does', () async {
      expect(expected, hasLength(steps.length));
      _FormWorld? world;
      for (var index = 0; index < steps.length; index++) {
        final step = steps[index];
        if (step['op'] == 'start') {
          world = _FormWorld();
        } else {
          world!.apply(step);
        }
        await _settle();
        final actual = _normalize(world.encode());
        final want = _normalize(expected[index]);
        if (jsonEncode(actual) != jsonEncode(want)) {
          fail(
            'step $index (${step['op']}, ${_world(steps, index)}) differs\n'
            '  step:     ${jsonEncode(step)}\n'
            '  ts:       ${jsonEncode(want)}\n'
            '  dart:     ${jsonEncode(actual)}',
          );
        }
      }
    });
  });
}

String _world(List<Map<String, Object?>> steps, int index) {
  for (var i = index; i >= 0; i--) {
    if (steps[i]['op'] == 'start') return '${steps[i]['name']}';
  }
  return '?';
}

/// Round trip through JSON so numbers and maps compare as the fixture does.
Object? _normalize(Object? value) => jsonDecode(jsonEncode(value));

Future<void> _settle() async {
  for (var round = 0; round < 25; round++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _errorText(Object error) =>
    error is RemoteException ? error.message : '$error';

/// One scripted host: `settings.describe` / `settings.mutate` calls park until a
/// step answers them (an answer that comes first waits for its call).
class _FormWorld {
  _FormWorld() {
    for (final method in _methods) {
      host.handlers['settings/$method'] = (args) => _park(method, args);
    }
    forms = ConfigForms(host.remotes);
  }

  static const _methods = ['describe', 'mutate'];

  final FakeHost host = FakeHost();
  late final ConfigForms forms;
  final Map<String, List<Map<String, Object?>>> _queued = {
    for (final m in _methods) m: [],
  };
  final Map<String, List<Completer<Object?>>> _waiting = {
    for (final m in _methods) m: [],
  };
  final List<Map<String, Object?>> _calls = [];
  final List<Map<String, Object?>> _effects = [];
  final Map<String, String> _writes = {};
  final Map<String, ConfigFormController> _watched = {};
  final Map<String, void Function()> _served = {};

  Future<Object?> _park(String method, Map<String, Object?> args) {
    _calls.add(
      method == 'describe'
          ? {'call': 'describe'}
          : {
              'call': 'mutate',
              'ns': args['ns'],
              'ops': _normalize(args['ops']),
              'expectedRevision': args['expectedRevision'],
            },
    );
    final completer = Completer<Object?>();
    final queued = _queued[method]!;
    if (queued.isNotEmpty) {
      _deliver(completer, queued.removeAt(0));
    } else {
      _waiting[method]!.add(completer);
    }
    return completer.future;
  }

  void _deliver(Completer<Object?> call, Map<String, Object?> result) {
    if (result.containsKey('throw')) {
      call.completeError(
        RemoteException('transport/failed', '${result['throw']}'),
      );
    } else if (result['ok'] == false) {
      final error = (result['error'] as Map).cast<String, Object?>();
      call.completeError(
        RemoteException('${error['code']}', '${error['message']}'),
      );
    } else {
      call.complete(_normalize(result['value']));
    }
  }

  void _track(String id, Future<bool> write) {
    _writes[id] = 'pending';
    write.then(
      (accepted) => _writes[id] = '$accepted',
      onError: (Object error) => _writes[id] = 'rejected: ${_errorText(error)}',
    );
  }

  void apply(Map<String, Object?> step) {
    switch (step['op']) {
      case 'answer':
        final method = '${step['method']}';
        final result = (step['result'] as Map).cast<String, Object?>();
        final waiting = _waiting[method]!;
        if (waiting.isEmpty) {
          _queued[method]!.add(result);
        } else {
          _deliver(waiting.removeAt(0), result);
        }
      case 'emit':
        host.emit('${step['event']}', (step['args'] as List?) ?? const []);
      case 'reset':
        final generation = FakeGeneration();
        host.generation = generation;
        host.gens.add(generation);
      case 'watch':
        _watched['${step['ns']}'] = forms.get('${step['ns']}');
      case 'set':
        _track(
          '${step['id']}',
          _form(step).set('${step['field']}', step['value']),
        );
      case 'unset':
        _track('${step['id']}', _form(step).unset('${step['field']}'));
      case 'mutate':
        _track(
          '${step['id']}',
          _form(step).mutate([
            for (final raw
                in (step['ops'] as List).cast<Map<String, Object?>>())
              raw['op'] == 'set'
                  ? SetOp(List<String>.from(raw['path'] as List), raw['value'])
                  : UnsetOp(List<String>.from(raw['path'] as List)),
          ], expectedRevision: step['expectedRevision'] as int?),
        );
      case 'ensure':
        unawaited(forms.mirror.ensure());
      case 'acceptView':
        forms.mirror.acceptView(
          wire.SettingsNamespaceView.fromJson(step['view'], 'step.view'),
        );
      case 'whileServed':
        final id = '${step['id']}';
        _served[id] = forms.whileServed(
          [for (final ns in step['namespaces'] as List) '$ns'],
          (served) {
            _effects.add({
              'effect': 'register',
              'id': id,
              'served': served.toList()..sort(),
            });
            return () => _effects.add({'effect': 'off', 'id': id});
          },
        );
      case 'stopWhileServed':
        _served['${step['id']}']!();
      case 'dispose':
        unawaited(forms.dispose());
      default:
        throw StateError('unknown op ${step['op']}');
    }
  }

  ConfigFormController _form(Map<String, Object?> step) =>
      _watched['${step['ns']}'] ??
      (throw StateError('namespace ${step['ns']} is not watched'));

  Map<String, Object?> encode() {
    final mirror = forms.mirror.snapshot;
    final view = mirror.view;
    final out = <String, Object?>{
      'mirror': {
        'status': mirror.status.name,
        'error': mirror.error,
        if (view != null)
          'view': {
            'writable': view.writable,
            'hasDocument': view.hasDocument,
            'revisions': {
              for (final row in view.namespaces) row.ns: row.revision,
            },
          },
      },
      'forms': {
        for (final entry in _watched.entries)
          entry.key: {
            'status': entry.value.snapshot.status.name,
            if (entry.value.snapshot.value != null)
              'value': entry.value.snapshot.value,
            if (entry.value.snapshot.base != null)
              'base': entry.value.snapshot.base,
            if (entry.value.snapshot.user != null)
              'user': entry.value.snapshot.user,
            if (entry.value.snapshot.revision != null)
              'revision': entry.value.snapshot.revision,
            'writable': entry.value.snapshot.writable,
          },
      },
      'calls': List.of(_calls),
      'effects': List.of(_effects),
      'writes': Map.of(_writes),
    };
    _calls.clear();
    _effects.clear();
    return out;
  }
}
