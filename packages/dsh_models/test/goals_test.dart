import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> goal({
  String id = 'g',
  int revision = 1,
  String phase = 'active',
}) => {
  'id': id,
  'revision': revision,
  'objective': 'Synthetic objective',
  'phase': phase,
  'maxGoalRounds': 12,
};
Map<String, Object?> liveGoal({
  String id = 'g',
  int revision = 1,
  String activation = 'armed',
}) => {
  ...goal(id: id, revision: revision),
  'roundsStarted': 1,
  'createdAt': 1000,
  'updatedAt': 1001,
  'activation': activation,
};
Future<void> ticks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('live activation events supersede reads and unrelated projections do not refetch', () async {
    final host = FakeHost();
    final session = Session('s', FakeTransport());
    session.projections.apply('goal', {'goal': goal()}, 1);
    final old = Completer<Object?>();
    host.handlers['goals/get'] = (_) => old.future;
    final model = GoalModel(
      session: session,
      remotes: host.remotes,
      ensureOpen: () async {},
    );
    await ticks();
    expect(model.currentActivation, isNull);
    host.emit('goal/activation-changed', [
      {
        'sessionId': 's',
        'goal': {'id': 'g', 'revision': 1, 'activation': 'disarmed'},
      },
    ]);
    old.complete(liveGoal());
    await ticks();
    expect(model.currentActivation, 'disarmed');
    session.projections.apply('title', 'unrelated', 2);
    await ticks();
    expect(host.callsTo('goals/get'), hasLength(1));
    session.projections.apply('goal', {'goal': goal(revision: 2)}, 3);
    expect(model.currentActivation, isNull);
    host.handlers['goals/get'] = (_) => liveGoal(revision: 2);
    await ticks();
    expect(model.currentActivation, 'armed');
    session.projections.apply('goal', null, 4);
    expect(model.goal, isNull);
    expect(model.currentActivation, isNull);
    await model.dispose();
    await session.dispose();
    await host.close();
  });
  test('mutations use latest projected CAS and serialize rapid actions; replacement rejects an old editor', () async {
    final host = FakeHost();
    final session = Session('s', FakeTransport());
    session.projections.apply('goal', {'goal': goal(phase: 'paused')}, 1);
    final gate = Completer<Object?>();
    host.handlers['goals/edit'] = (_) => gate.future;
    final model = GoalModel(
      session: session,
      remotes: host.remotes,
      ensureOpen: () async {},
    );
    session.projections.apply('goal', {
      'goal': goal(revision: 2, phase: 'paused'),
    }, 2);
    final action = model.act('edit', objective: 'Updated', expectedId: 'g');
    expect(model.pending, true);
    expect(await model.act('clear'), false);
    expect(host.callsTo('goals/edit').single.args, {
      'agentId': 's',
      'ref': {'id': 'g', 'revision': 2},
      'request': {'objective': 'Updated'},
    });
    session.projections.apply('goal', {
      'goal': goal(id: 'new', revision: 1, phase: 'paused'),
    }, 3);
    gate.complete(liveGoal(revision: 3));
    await action;
    expect(model.goal!.id, 'new');
    expect(await model.act('edit', objective: 'Old', expectedId: 'g'), false);
    host.handlers['goals/clear'] = (_) =>
        throw RemoteException('goal/conflict', 'Changed elsewhere');
    expect(await model.act('clear'), false);
    expect(model.error, 'Changed elsewhere (goal/conflict)');
    expect(model.clearedId, isNull);
    host.handlers['goals/clear'] = (_) => {'id': 'new', 'revision': 2};
    expect(await model.act('clear'), true);
    expect(model.clearedId, 'new');
    await model.dispose();
    await session.dispose();
    await host.close();
  });
  test(
    'disposed activation owner and replaced projection exclude late live read',
    () async {
      final host = FakeHost();
      final session = Session('s', FakeTransport());
      session.projections.apply('goal', {'goal': goal()}, 1);
      final gate = Completer<Object?>();
      host.handlers['goals/get'] = (_) => gate.future;
      final model = GoalModel(
        session: session,
        remotes: host.remotes,
        ensureOpen: () async {},
      );
      await ticks();
      await model.dispose();
      gate.complete(liveGoal());
      await ticks();
      expect(model.currentActivation, isNull);
      await session.dispose();
      await host.close();
    },
  );
}
