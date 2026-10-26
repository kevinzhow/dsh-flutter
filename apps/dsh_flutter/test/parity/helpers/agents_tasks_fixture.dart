import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_job.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';

/// Only synthetic data. These Host handlers drive real generated Remote calls.
class SyntheticAgentsTasks {
  SyntheticAgentsTasks() {
    host.handlers['agentPresets/list'] = (_) => {
      'presets': [
        {'id': 'standard', 'isDefault': true},
        {'id': 'ptc', 'isDefault': false},
        {'id': 'cordis', 'isDefault': false},
        {
          'id': 'reviewer',
          'name': 'Synthetic reviewer',
          'description': 'Synthetic review preset',
          'isDefault': false,
        },
        {
          'id': 'broken',
          'broken': 'Synthetic dependency missing',
          'isDefault': false,
        },
      ],
    };
    host.handlers['agentPresets/read'] = (args) => {
      'agentPreset': args['agentPreset'],
      'content': 'plugins:\n  - synthetic-reader\n  - synthetic-reviewer',
    };
    host.handlers['agentPresets/select'] = (args) {
      selected = args['agentPreset']! as String;
      notify();
      return selected;
    };
    presets = AgentPresetsModel(
      remotes: host.remotes,
      settings: settings,
      tools: tools,
      currentSession: () =>
          (id: 'synthetic-session', blank: true, preset: selected),
    );
    host.handlers['goals/get'] = (_) => liveGoal;
    for (final verb in ['pause', 'resume', 'edit', 'clear']) {
      host.handlers['goals/$verb'] = (args) {
        final expected = args['ref'] as Map;
        if (expected['id'] != goal['id'] ||
            expected['revision'] != goal['revision']) {
          throw RemoteException('goal/conflict', 'Synthetic conflict');
        }
        final id = goal['id'];
        final revision = (goal['revision']! as int) + 1;
        if (verb == 'clear') {
          session.projections.apply('goal', null, ++projectionSeq);
          notify();
          return {'id': id, 'revision': revision};
        }
        goal = {
          ...goal,
          'revision': revision,
          if (verb == 'pause') 'phase': 'paused',
          if (verb == 'resume') 'phase': 'active',
          if (verb == 'edit')
            'objective': (args['request'] as Map)['objective'],
        };
        session.projections.apply('goal', {'goal': goal}, ++projectionSeq);
        notify();
        return liveGoal;
      };
    }
    session.projections.apply('goal', {'goal': goal}, projectionSeq);
    goalModel = GoalModel(
      session: session,
      remotes: host.remotes,
      ensureOpen: () async {},
    );
    host.handlers['schedule/catalog'] = (_) => tasks;
    host.handlers['schedule/update'] = (args) {
      final request = args['request'] as Map;
      final index = tasks.indexWhere(
        (r) =>
            r['id'] == request['id'] && r['sessionId'] == request['sessionId'],
      );
      if (index < 0) {
        return {
          'id': request['id'],
          'updated': false,
          'code': 'schedule_not_found',
        };
      }
      final current = tasks[index],
          record = Map<String, Object?>.from(current)
            ..remove('sessionId')
            ..remove('status');
      if (jsonEncode(record) != jsonEncode(request['expected']) &&
          !_equal(record, request['expected'])) {
        return {
          'id': request['id'],
          'updated': false,
          'code': 'schedule_conflict',
        };
      }
      final next = {
        ...current,
        if (request['title'] != null) 'title': request['title'],
        if (request['prompt'] != null) 'prompt': request['prompt'],
      };
      if (request['change'] case final Map<Object?, Object?> change) {
        next.removeWhere(
          (k, _) => [
            'afterSeconds',
            'everySeconds',
            'time',
            'timeZone',
            'weekdays',
            'expression',
          ].contains(k),
        );
        next['kind'] = change['kind'];
        final kind = change['kind'];
        if (kind == 'every') next['everySeconds'] = change['every_seconds'];
        if (change[kind] case final Map<Object?, Object?> value) {
          next.addAll({
            for (final e in value.entries)
              switch (e.key) {
                'time_zone' => 'timeZone',
                _ => e.key as String,
              }: e.value,
          });
        }
      }
      tasks[index] = next;
      updates++;
      host.emit('schedule/changed');
      notify();
      return {
        'id': request['id'],
        'updated': true,
        'record': Map<String, Object?>.from(next)
          ..remove('sessionId')
          ..remove('status'),
      };
    };
    host.handlers['schedule/delete'] = (args) {
      final id = (args['request'] as Map)['id'];
      tasks.removeWhere((r) => r['id'] == id);
      deletions++;
      host.emit('schedule/changed');
      notify();
      return {'id': id, 'deleted': true};
    };
    host.handlers['schedule/history'] = (args) => {
      'id': (args['request'] as Map)['id'],
      'records': [
        {
          'messageId': 'synthetic-receipt',
          'scheduledAt': '2026-10-25T00:00:00.000Z',
          'deliveredAt': '2026-10-25T00:00:01.000Z',
          'prompt': 'Synthetic saved delivery instruction. This is retained history, not the current task draft.',
        },
      ],
      'earlierRecordsUnavailable': true,
      'earlierRecordsPruned': true,
      'retention': {'days': 30, 'records': 100},
    };
    schedules = ScheduleService(host.remotes);
    host.handlers['job/kill'] = (_) {
      stops++;
      jobStatus = 'stopping';
      roster.add(
        StreamItem(1, {
          'type': 'rows',
          'jobs': [job],
        }),
      );
      notify();
      return {'outcome': 'requested'};
    };
    jobs = JobsService(
      JobsHost(
        remote: JobRemote(host),
        list: (_) async* {
          yield const StreamOpened(1);
          yield StreamItem(1, {
            'type': 'rows',
            'jobs': [job],
          });
          yield* roster.stream;
        },
        follow: (_) async* {
          yield const StreamOpened(1);
          yield StreamItem(1, {'type': 'opened', 'job': job, 'from': 0});
          yield const StreamItem(1, {
            'type': 'output',
            'chunks': [
              {'at': 0, 'text': 'Synthetic native output\nBuild complete.'},
            ],
            'next': 39,
          });
          yield* output.stream;
        },
      ),
    );
  }
  final host = FakeHost();
  final session = Session('synthetic-session', FakeTransport());
  final settings = FakeConfigForm(
    const ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: {'selectedDefault': 'standard'},
      writable: true,
      revision: 1,
    ),
  );
  final tools = FakeConfigForm(
    const ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: {'enabled': true},
      writable: true,
      revision: 1,
    ),
  );
  late final AgentPresetsModel presets;
  late final GoalModel goalModel;
  late final ScheduleService schedules;
  late final JobsService jobs;
  final changed = Observable(0);
  final roster = StreamController<GenerationFrame>.broadcast(),
      output = StreamController<GenerationFrame>.broadcast();
  String selected = 'standard', jobStatus = 'running';
  int updates = 0, deletions = 0, stops = 0, projectionSeq = 1;
  Map<String, Object?> goal = {
    'id': 'synthetic-goal',
    'revision': 1,
    'objective': 'Synthetic objective',
    'phase': 'active',
    'maxGoalRounds': 12,
  };
  Map<String, Object?> get liveGoal => {
    ...goal,
    'roundsStarted': 1,
    'createdAt': 1000,
    'updatedAt': 1001,
    'activation': goal['phase'] == 'paused' ? 'disarmed' : 'armed',
  };
  Map<String, Object?> get job => {
    'id': 'synthetic-job',
    'kind': 'shell',
    'label': 'synthetic command',
    'status': jobStatus,
    'startedAt': DateTime.now().millisecondsSinceEpoch - 5000,
    'output': {'earliest': 0, 'total': 39},
  };
  final List<Map<String, Object?>> tasks = [
    {
      'id': 'synthetic-daily',
      'sessionId': 'synthetic-session',
      'title': 'Synthetic daily task',
      'prompt': 'Review the synthetic project each morning.',
      'kind': 'daily',
      'time': '09:00:00.123',
      'timeZone': 'Asia/Tokyo',
      'scheduledAt': '2026-10-27T00:00:00.123Z',
      'status': 'active',
    },
    {
      'id': 'synthetic-ended',
      'sessionId': 'second-session',
      'title': 'Synthetic ended task',
      'prompt': 'Retained inactive instruction',
      'kind': 'at',
      'scheduledAt': '2026-10-25T00:00:00.000Z',
      'status': 'inactive',
    },
  ];
  bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => _equal(a[i], b[i])).every((v) => v);
    }
    return a == b;
  }

  void notify() => changed.set(changed.value + 1);
  Future<void> dispose() async {
    await presets.dispose();
    await goalModel.dispose();
    await schedules.dispose();
    await jobs.dispose();
    await session.dispose();
    await roster.close();
    await output.close();
    await host.close();
    await changed.dispose();
  }
}
