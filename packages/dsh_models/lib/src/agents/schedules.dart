import 'dart:async';

import 'package:dsh_client/generated_schedule.dart';

import '../observable.dart';
import '../settings/host_remotes.dart';

class TaskEntry {
  TaskEntry(this.wire) : raw = Map.unmodifiable(wire.toJson());
  final ScheduleCatalogEntry wire;
  final Map<String, Object?> raw;
  String get id => raw['id'] as String;
  String get sessionId => raw['sessionId'] as String;
  String get title => raw['title'] as String;
  String get prompt => raw['prompt'] as String;
  String get kind => raw['kind'] as String;
  String get status => raw['status'] as String;
  String get scheduledAt => raw['scheduledAt'] as String;
  Map<String, Object?> get expectedJson => {
    for (final key in [
      'id',
      'title',
      'prompt',
      'scheduledAt',
      'kind',
      switch (kind) {
        'after' => 'afterSeconds',
        'every' => 'everySeconds',
        'daily' || 'weekly' => 'time',
        'cron' => 'expression',
        _ => '',
      },
      if (const ['daily', 'weekly', 'cron'].contains(kind)) 'timeZone',
      if (kind == 'weekly') 'weekdays',
    ])
      if (key.isNotEmpty && raw.containsKey(key)) key: raw[key],
  };
  ScheduleRecord get expected => ScheduleRecord.fromJson(expectedJson);
  String? get latestMessageId =>
      (raw['lastDelivery'] as Map?)?['messageId'] as String?;
}

class CatalogSnapshot<T> {
  const CatalogSnapshot({
    this.records = const [],
    this.status = 'loading',
    this.deleting = const [],
    this.settled = false,
    this.readRequest = 0,
    this.readSettled = 0,
  });
  final List<T> records;
  final String status;
  final List<String> deleting;
  final bool settled;
  final int readRequest, readSettled;
}

/// Shared authoritative catalog with subscription-owned invalidations. Query
/// ordinals distinguish a fresh post-write read from an earlier in-flight one.
class TaskCatalog<T> {
  TaskCatalog({
    required this.list,
    required this.remove,
    required this.changes,
    required this.resets,
  });
  final Future<List<T>> Function() list;
  final Future<void> Function(String) remove;
  final Stream<Object?> changes, resets;
  final state = Observable<CatalogSnapshot<T>>(CatalogSnapshot<T>());
  StreamSubscription<Object?>? _changes, _resets;
  int _subscribers = 0, _epoch = 0, _lifecycle = 0, _flightRequest = 0;
  bool _batching = false, _disposed = false;
  Future<void>? _flight;
  CatalogSnapshot<T> get snapshot => state.value;
  void _publish({
    List<T>? records,
    String? status,
    List<String>? deleting,
    bool? settled,
    int? readRequest,
    int? readSettled,
  }) {
    if (_disposed) return;
    final old = snapshot;
    state.set(
      CatalogSnapshot(
        records: records ?? old.records,
        status: status ?? old.status,
        deleting: deleting ?? old.deleting,
        settled: settled ?? old.settled,
        readRequest: readRequest ?? old.readRequest,
        readSettled: readSettled ?? old.readSettled,
      ),
    );
  }

  void Function() watch(void Function() listener) {
    if (_disposed) return () {};
    final sub = state.changes.listen((_) => listener());
    if (_subscribers++ == 0) {
      _lifecycle++;
      _changes = changes.listen((_) => unawaited(refresh(supersede: true)));
      _resets = resets.listen((_) => unawaited(refresh(supersede: true)));
      unawaited(refresh(supersede: true));
    }
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      unawaited(sub.cancel());
      if (--_subscribers != 0) return;
      unawaited(_changes?.cancel());
      unawaited(_resets?.cancel());
      _changes = null;
      _resets = null;
      _epoch++;
      _lifecycle++;
      _publish(deleting: const []);
    };
  }

  Future<void> refresh({bool supersede = false, int since = 0}) {
    if (_disposed) return Future.value();
    final request = snapshot.readRequest + 1;
    _publish(status: 'loading', readRequest: request);
    if (!supersede && _batching && _flight != null && _flightRequest > since) {
      return _flight!;
    }
    if (!_batching) {
      _batching = true;
      scheduleMicrotask(() => _batching = false);
    }
    final epoch = ++_epoch;
    final done = Completer<void>();
    final pending = done.future;
    _flight = pending;
    _flightRequest = request;
    unawaited(
      Future<void>.sync(() async {
        try {
          final records = await list();
          if (!_disposed && epoch == _epoch) {
            _publish(
              records: List.unmodifiable(records),
              status: 'ready',
              settled: true,
              readSettled: request,
            );
          }
        } on Object {
          if (!_disposed && epoch == _epoch) _publish(status: 'error');
        } finally {
          if (identical(_flight, pending)) _flight = null;
          done.complete();
        }
      }),
    );
    return pending;
  }

  Future<String> delete(String id) async {
    if (_disposed) return 'failed';
    if (snapshot.deleting.contains(id)) return 'pending';
    final lifecycle = _lifecycle;
    _publish(deleting: [...snapshot.deleting, id]);
    try {
      await remove(id);
    } on Object {
      if (!_disposed && lifecycle == _lifecycle) {
        _publish(deleting: snapshot.deleting.where((x) => x != id).toList());
      }
      return 'failed';
    }
    if (_disposed || lifecycle != _lifecycle) return 'deleted';
    _publish(deleting: snapshot.deleting.where((x) => x != id).toList());
    await refresh(supersede: true);
    return 'deleted';
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    _lifecycle++;
    await _changes?.cancel();
    await _resets?.cancel();
    await state.dispose();
  }
}

class ScheduleService {
  ScheduleService(this.remotes) {
    catalog = TaskCatalog(
      list: () async => [
        for (final row in await remotes.schedule.catalog())
          if (row is! ScheduleCatalogEntryUnrecognized) TaskEntry(row),
      ],
      remove: (id) async {
        final row = catalog.snapshot.records
            .where((r) => r.id == id)
            .firstOrNull;
        if (row != null) {
          await remotes.schedule.delete(
            ScheduleDeleteRequest(sessionId: row.sessionId, id: id),
          );
        }
      },
      changes: remotes.emitted('schedule/changed'),
      resets: remotes.generations,
    );
  }
  final HostRemotes remotes;
  late final TaskCatalog<TaskEntry> catalog;
  final notice = Observable<({int revision, String outcome})?>(null);
  int _noticeRevision = 0;
  bool _disposed = false;
  void report(String outcome) {
    if (!_disposed && outcome != 'pending') {
      notice.set((revision: ++_noticeRevision, outcome: outcome));
    }
  }

  void dismissNotice(int revision) {
    if (notice.value?.revision == revision) notice.set(null);
  }

  Future<String> delete(String id) async {
    final result = await catalog.delete(id);
    report(result);
    return result;
  }

  TaskCatalog<TaskEntry> sessionCatalog(String sessionId) => TaskCatalog(
    list: () async => [
      for (final row in await remotes.schedule.list(
        ScheduleListRequest(sessionId: sessionId),
      ))
        if (row is! ScheduleRecordUnrecognized)
          TaskEntry(
            ScheduleCatalogEntry.fromJson({
              ...row.toJson(),
              'sessionId': sessionId,
              'status': 'active',
            }),
          ),
    ],
    remove: (id) async {
      await remotes.schedule.delete(
        ScheduleDeleteRequest(sessionId: sessionId, id: id),
      );
    },
    changes: remotes.emitted('schedule/changed'),
    resets: remotes.generations,
  );
  Future<ScheduleUpdateResult> update(ScheduleUpdateRequest request) async {
    final result = await remotes.schedule.update(request);
    if (result.record != null ||
        const [
          'schedule_conflict',
          'schedule_ended',
          'schedule_not_found',
        ].contains(result.code)) {
      await catalog.refresh(since: catalog.snapshot.readRequest);
    }
    return result;
  }

  Future<void> dispose() async {
    _disposed = true;
    await catalog.dispose();
    await notice.dispose();
  }
}

/// Selected-task history pages use their original Session binding. A fresh
/// latest receipt supersedes pending older pages and never fabricates prompts.
class TaskDeliveryModel {
  TaskDeliveryModel(this.remotes, this.sessionId, this.id);
  final HostRemotes remotes;
  final String sessionId, id;
  final changed = Observable(0);
  List<ScheduleDeliveryRecord> records = const [];
  String? nextBefore, failure, retryBefore;
  DeliveryRetentionBounds? retention;
  bool loading = false,
      settled = false,
      earlierUnavailable = false,
      earlierPruned = false,
      _disposed = false;
  int _epoch = 0;
  void _notify() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  Future<void> load({String? before, bool refresh = false}) async {
    if (_disposed || (loading && !refresh)) return;
    final epoch = ++_epoch;
    loading = true;
    failure = null;
    _notify();
    try {
      final result = await remotes.schedule.history(
        ScheduleDeliveryHistoryRequest(
          sessionId: sessionId,
          id: id,
          limit: 20,
          before: before,
        ),
      );
      if (_disposed || epoch != _epoch) return;
      if (result.code != null) {
        failure = result.code!.value == 'schedule_not_found'
            ? 'delivery.notFound'
            : 'delivery.cursorError';
        retryBefore = null;
        return;
      }
      if (result.records == null) {
        throw const FormatException('Missing delivery records');
      }
      final incoming = result.records!;
      final seen = <String>{};
      records = List.unmodifiable([
        for (final row in [if (before != null) ...records, ...incoming])
          if (seen.add(row.messageId)) row,
      ]);
      nextBefore = result.nextBefore;
      retention = result.retention;
      earlierUnavailable = result.earlierRecordsUnavailable == true;
      earlierPruned = result.earlierRecordsPruned == true;
      settled = true;
    } on Object {
      if (!_disposed && epoch == _epoch) {
        failure = 'delivery.error';
        retryBefore = before;
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    await changed.dispose();
  }
}
