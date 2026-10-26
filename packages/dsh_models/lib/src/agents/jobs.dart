import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_job.dart';

import '../observable.dart';

class ObservedJob {
  const ObservedJob({
    required this.jobId,
    this.text = '',
    this.gapBefore = false,
    this.streaming = false,
    this.error,
    this.cursor,
  });
  final String jobId, text;
  final bool gapBefore, streaming;
  final String? error;

  /// Absolute UTF-8 byte offset, independent of the bounded UTF-16 render tail.
  final num? cursor;
}

/// The two generated logical stream openers. Re-evaluate the follow request on
/// every connection generation, so the latest accepted byte cursor is used.
class JobsHost {
  JobsHost({required this.remote, required this.list, required this.follow});
  factory JobsHost.over(DshConnection connection) => JobsHost(
    remote: JobRemote(connection.caller),
    list: (request) => connection.openStream(
      JobStreams.list.endpoint,
      () => JobStreams.list.encodeArgs(request),
    ),
    follow: (request) => connection.openStream(
      JobStreams.follow.endpoint,
      () => JobStreams.follow.encodeArgs(request()),
    ),
  );
  final JobRemote remote;
  final Stream<GenerationFrame> Function(JobListRequest) list;
  final Stream<GenerationFrame> Function(JobFollowRequest Function()) follow;
}

/// Pure job-state fold used by the stream service and pinned source vectors.
class JobsModel {
  final changed = Observable(0);
  final rows = <String, List<JobView>>{};
  final observed = <String, ObservedJob>{};
  void _notify() => changed.set(changed.value + 1);
  void replaceRows(String session, List<JobView> jobs) {
    if (jobs.isEmpty) {
      if (rows.remove(session) == null) return;
    } else {
      rows[session] = List.unmodifiable(jobs);
    }
    _notify();
  }

  void dropRows(String session) {
    if (rows.remove(session) != null) _notify();
  }

  void opened(String id, JobFollowFrameOpened frame) {
    final old = observed[id];
    observed[id] = ObservedJob(
      jobId: id,
      text: old?.text ?? '',
      gapBefore:
          (old?.gapBefore ?? false) ||
          frame.from < frame.job.output.earliest ||
          ((old == null || old.text.isEmpty) && frame.from > 0),
      streaming: true,
      cursor: frame.from,
    );
    _notify();
  }

  void output(String id, JobFollowFrameOutput frame) {
    final old = observed[id];
    if (old == null) return;
    var text = old.text + frame.chunks.map((c) => c.text).join();
    var gap =
        old.gapBefore ||
        frame.lossy == true ||
        frame.chunks.any((c) => c.gapBefore == true);
    const limit = 128 * 1024;
    if (text.length > limit) {
      var cut = text.length - limit;
      final unit = text.codeUnitAt(cut);
      if (unit >= 0xDC00 && unit <= 0xDFFF) cut++;
      text = text.substring(cut);
      gap = true;
    }
    observed[id] = ObservedJob(
      jobId: id,
      text: text,
      gapBefore: gap,
      streaming: old.streaming,
      error: old.error,
      cursor: frame.next,
    );
    _notify();
  }

  void settled(String id) {
    final old = observed[id];
    if (old == null) return;
    observed[id] = ObservedJob(
      jobId: id,
      text: old.text,
      gapBefore: old.gapBefore,
      error: old.error,
      cursor: old.cursor,
    );
    _notify();
  }

  void failed(String id, Object error) {
    final old = observed[id];
    observed[id] = ObservedJob(
      jobId: id,
      text: old?.text ?? '',
      gapBefore: old?.gapBefore ?? false,
      cursor: old?.cursor,
      error: error is RemoteException ? error.message : '$error',
    );
    _notify();
  }

  void stopped(String id) {
    if (observed.remove(id) != null) _notify();
  }

  Future<void> dispose() => changed.dispose();
}

class _Watch {
  int refs = 1;
  bool stopped = false, accepted = false;
  int? generation;
  StreamSubscription<GenerationFrame>? sub;
  Future<void> close() async {
    stopped = true;
    await sub?.cancel();
  }
}

/// One roster stream per watched Session and one output stream per observed
/// job. Release closures bind the exact entry to protect a newer replacement.
class JobsService {
  JobsService(this.host, {JobsModel? model}) : model = model ?? JobsModel();
  final JobsHost host;
  final JobsModel model;
  final _rows = <String, _Watch>{}, _observations = <String, _Watch>{};
  bool _disposed = false;

  Future<JobKillValue> kill(String session, String id) =>
      host.remote.kill(JobKillRequest(sessionId: session, jobId: id));
  void Function() watchRows(String session) => _acquire(
    _rows,
    session,
    () => _startRows(session),
    () => model.dropRows(session),
  );
  void Function() observe(String? session, String id) => _acquire(
    _observations,
    id,
    () => _startObservation(session, id),
    () => model.stopped(id),
  );
  void Function() _acquire(
    Map<String, _Watch> entries,
    String key,
    _Watch Function() start,
    void Function() clear,
  ) {
    if (_disposed) return () {};
    var entry = entries[key];
    if (entry == null || entry.stopped) {
      entry = start();
      entries[key] = entry;
    } else {
      entry.refs++;
    }
    final owned = entry;
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--owned.refs > 0) return;
      if (identical(entries[key], owned)) entries.remove(key);
      unawaited(
        owned.close().then((_) {
          if (!entries.containsKey(key) && !_disposed) clear();
        }),
      );
    };
  }

  bool _retryable(_Watch watch, Object? error) =>
      error is CarrierLost ||
      error is NotConnected ||
      (error == null && watch.accepted);
  _Watch _startRows(String session) {
    final watch = _Watch();
    void fail(Object error) {
      if (watch.stopped) return;
      model.dropRows(session);
      unawaited(watch.close());
    }

    Stream<GenerationFrame> stream;
    try {
      stream = host.list(JobListRequest(sessionId: session));
    } on Object catch (error) {
      scheduleMicrotask(() => fail(error));
      return watch;
    }
    watch.sub = stream.listen(
      (frame) {
        if (watch.stopped) return;
        switch (frame) {
          case StreamOpened():
            watch.generation = frame.generation;
            watch.accepted = false;
          case StreamItem(:final value):
            if (frame.generation != watch.generation) return;
            try {
              final row = JobListFrame.fromJson(value);
              model.replaceRows(session, row.jobs);
              watch.accepted = true;
            } on Object catch (e) {
              fail(e);
            }
          case StreamEnded(:final error):
            if (!_retryable(watch, error)) {
              fail(error ?? StateError('Job roster ended before first frame'));
            }
        }
      },
      onError: (Object error) => fail(error),
      onDone: () => fail(StateError('Job roster stream ended')),
    );
    return watch;
  }

  _Watch _startObservation(String? session, String id) {
    final watch = _Watch();
    void fail(Object error) {
      if (watch.stopped) return;
      model.failed(id, error);
      unawaited(watch.close());
    }

    Stream<GenerationFrame> stream;
    try {
      stream = host.follow(
        () => JobFollowRequest(
          sessionId: session,
          jobId: id,
          from: model.observed[id]?.cursor,
        ),
      );
    } on Object catch (error) {
      scheduleMicrotask(() => fail(error));
      return watch;
    }
    watch.sub = stream.listen(
      (frame) {
        if (watch.stopped) return;
        switch (frame) {
          case StreamOpened():
            watch.generation = frame.generation;
            watch.accepted = false;
          case StreamItem(:final value):
            if (frame.generation != watch.generation) return;
            try {
              final item = JobFollowFrame.fromJson(value);
              if (item is JobFollowFrameUnrecognized) return;
              if (!watch.accepted && item is! JobFollowFrameOpened) {
                throw const FormatException('Job output is missing its anchor');
              }
              switch (item) {
                case JobFollowFrameOpened():
                  model.opened(id, item);
                  watch.accepted = true;
                case JobFollowFrameOutput():
                  model.output(id, item);
                case JobFollowFrameStatus():
                  model.settled(id);
                  unawaited(watch.close());
                case JobFollowFrameUnrecognized():
                  break;
              }
            } on Object catch (e) {
              fail(e);
            }
          case StreamEnded(:final error):
            if (!_retryable(watch, error)) {
              fail(error ?? StateError('Job output ended before anchor'));
            }
        }
      },
      onError: (Object error) => fail(error),
      onDone: () => fail(StateError('Job output ended before settlement')),
    );
    return watch;
  }

  Future<void> dispose() async {
    _disposed = true;
    final all = [..._rows.values, ..._observations.values];
    _rows.clear();
    _observations.clear();
    await Future.wait([for (final entry in all) entry.close()]);
    await model.dispose();
  }
}
