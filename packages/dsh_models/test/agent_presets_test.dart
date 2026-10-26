import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

ConfigFormSnapshot view(Map<String, Object?> value, {int revision = 4}) =>
    ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: value,
      writable: true,
      revision: revision,
    );

void main() {
  late FakeHost host;
  late FakeConfigForm settings, tools;
  late AgentPresetsModel model;
  PresetSession? session;
  List<Map<String, Object?>> roster = [];
  setUp(() {
    host = FakeHost();
    session = null;
    settings = FakeConfigForm(view({'selectedDefault': 'standard'}));
    tools = FakeConfigForm(view({'enabled': true}));
    roster = [
      {'id': 'standard', 'isDefault': true},
      {'id': 'ptc', 'isDefault': false},
      {'id': 'minimal', 'name': 'My Minimal', 'isDefault': false},
      {'id': 'broken', 'broken': 'missing dependency', 'isDefault': false},
    ];
    host.handlers['agentPresets/list'] = (_) => {'presets': roster};
    host.handlers['agentPresets/select'] = (args) => args['agentPreset'];
    model = AgentPresetsModel(
      remotes: host.remotes,
      settings: settings,
      tools: tools,
      currentSession: () => session,
    );
  });
  tearDown(() async {
    await model.dispose();
    await host.close();
  });

  test('staged choice waits for blank session and running composition stays immutable', () async {
    await model.load();
    expect(model.options.map((r) => r.id), ['standard', 'ptc', 'minimal']);
    await model.select('ptc');
    expect(host.callsTo('agentPresets/select'), isEmpty);
    session = (id: 'blank', blank: true, preset: 'standard');
    await model.apply();
    expect(host.callsTo('agentPresets/select').single.args, {
      'agentId': 'blank',
      'agentPreset': 'ptc',
    });
    expect(model.staged, isNull);
    session = (id: 'started', blank: false, preset: 'standard');
    await model.select('ptc');
    expect(host.callsTo('agentPresets/select'), hasLength(1));
    tools.publish(view({'enabled': false}));
    expect(model.visibleRows.map((r) => r.id), [
      'standard',
      'minimal',
      'broken',
    ]);
    expect(model.staged, isNull);
  });

  test(
    'only latest roster and composition viewer survive late answers or closure',
    () async {
      final old = Completer<Object?>();
      var calls = 0;
      host.handlers['agentPresets/list'] = (_) =>
          ++calls == 1 ? old.future : {'presets': roster};
      final first = model.load();
      await model.load();
      old.complete({'presets': <Object?>[]});
      await first;
      expect(model.rows, hasLength(4));
      final slow = Completer<Object?>();
      host.handlers['agentPresets/read'] = (_) => slow.future;
      final reading = model.view('ptc');
      model.closeView();
      slow.complete({'agentPreset': 'ptc', 'content': 'plugins: []'});
      await reading;
      expect(model.document, isNull);
      host.handlers['agentPresets/list'] = (_) =>
          throw RemoteException('gateway/invocation-unavailable', 'no presets');
      await model.load();
      expect(model.rows, isEmpty);
      expect(model.error, isNull);
    },
  );

  test(
    'settings default does not sync a blank session abandoned during save',
    () async {
      await model.load();
      session = (id: 'a', blank: true, preset: 'standard');
      final gate = Completer<void>();
      settings.gate = gate.future;
      final saving = model.makeDefault('ptc');
      await Future<void>.delayed(Duration.zero);
      session = (id: 'b', blank: true, preset: 'standard');
      roster = [
        {'id': 'ptc', 'isDefault': true},
      ];
      gate.complete();
      await saving;
      expect(host.callsTo('agentPresets/select'), isEmpty);
      expect((settings.writes.single.ops.single as SetOp).value, 'ptc');
      expect(settings.snapshot.value?['selectedDefault'], 'ptc');
    },
  );

  test('turning tools off corrects only built-in hidden default using captured revision', () async {
    roster = [
      {'id': 'standard', 'isDefault': false},
      {'id': 'ptc', 'isDefault': true},
    ];
    host.handlers['agentPresets/list'] = (_) => {
      'presets': [
        for (final r in roster)
          {
            ...r,
            'isDefault': r['id'] == settings.snapshot.value?['selectedDefault'],
          },
      ],
    };
    settings.publish(view({'selectedDefault': 'ptc'}, revision: 9));
    tools.publish(view({'enabled': false}));
    for (var i = 0; i < 12 && settings.writes.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(settings.writes.single.expectedRevision, 9);
    expect((settings.writes.single.ops.single as SetOp).value, 'standard');
    await Future<void>.delayed(Duration.zero);
    expect(settings.snapshot.value?['selectedDefault'], 'standard');
  });

  test('selection refusal exposes bare cause and disposed owner ignores pending response', () async {
    session = (id: 'a', blank: true, preset: 'standard');
    await model.load();
    host.handlers['agentPresets/select'] = (_) => throw RemoteException(
      'agent-preset/invalid',
      'wrapper',
      {'reason': 'no plugin'},
    );
    await model.select('ptc');
    expect(model.selectionError, 'no plugin');
    expect(model.current, 'standard');
    final gate = Completer<Object?>();
    host.handlers['agentPresets/select'] = (_) => gate.future;
    final pending = model.select('ptc');
    await model.dispose();
    gate.complete('ptc');
    await pending;
    expect(model.current, 'ptc');
    // Stage itself was visible before disposal; the reply may not publish more state.
    expect(model.selectionError, isNull);
  });
}
