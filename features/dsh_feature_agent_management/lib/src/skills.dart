import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_client/dsh_client.dart' show EmitEvent;
import 'package:dsh_client/generated_skills.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart' show rankByName;

class _Catalog {
  final abort = AbortController();
  late Future<List<SkillEntry>> promise;
  List<SkillEntry>? value;
  List<String>? names;
}

/// Shared Session-keyed skill metadata, never skill bodies. A menu request's
/// abort abandons only that request; invalidation owns the shared fetch abort.
class SkillSource extends InputTriggerSource {
  SkillSource({
    required this.remotes,
    required this.sessions,
    required this.i18n,
  }) {
    _events = remotes.hostEvents.listen((event) {
      if (event is! EmitEvent) return;
      if (event.event == 'agent-preset/selected') {
        final id = event.args.firstOrNull;
        if (id is String) invalidate(id);
      } else if (event.event == 'plugin-manager/changed') {
        clear();
      }
    });
    _generations = remotes.generations.listen((_) => clear());
  }
  final HostRemotes remotes;
  final InputSessionPort sessions;
  final DshI18n Function() i18n;
  final changed = Observable(0);
  final _catalogs = <String, _Catalog>{};
  StreamSubscription<Object?>? _events, _generations;
  bool _disposed = false;
  @override
  TriggerChar get trigger => TriggerChar.slash;
  @override
  String get name => 'skill';
  @override
  int get order => 2;
  @override
  Stream<Object?> get lexiconChanges => changed.changes;
  @override
  List<InputLexiconEntry> lexicon(String sessionId) => [
    for (final name in names(sessionId) ?? const <String>[])
      InputLexiconEntry('/$name', '/$name', appearance: 'skill'),
  ];
  List<String>? names(String id) => _catalogs[id]?.names;
  void _notify() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  _Catalog _fetch(String id) {
    if (_disposed) throw StateError('Skill source disposed');
    final held = _catalogs[id];
    if (held != null) return held;
    final entry = _Catalog();
    _catalogs[id] = entry;
    entry.promise = Future<List<SkillEntry>>.microtask(() async {
      await sessions.ensureOpen(id, entry.abort.signal);
      entry.abort.signal.throwIfAborted();
      final result = await remotes.skills.list(SkillListRequest(sessionId: id));
      entry.abort.signal.throwIfAborted();
      if (_disposed || !identical(_catalogs[id], entry)) {
        throw StateError('Skill catalog superseded');
      }
      entry.value = List.unmodifiable(result.skills);
      entry.names = List.unmodifiable(result.skills.map((row) => row.name));
      _notify();
      return entry.value!;
    });
    unawaited(
      entry.promise.then<void>(
        (_) {},
        onError: (Object e) {
          if (identical(_catalogs[id], entry)) _catalogs.remove(id);
        },
      ),
    );
    return entry;
  }

  @override
  void warm(String sessionId) {
    if (sessions.isSubagentTranscript(sessionId) || _disposed) return;
    unawaited(
      _fetch(sessionId).promise.then<void>((_) {}, onError: (Object e) {}),
    );
  }

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest req,
  ) async {
    if (sessions.isSubagentTranscript(sessionId)) return const [];
    final rows = await _fetch(sessionId).promise;
    if (req.signal.aborted || _disposed) return const [];
    return [
      for (final row in rankByName(rows, req.query, name: (r) => r.name))
        InputTriggerCandidate(
          name: row.name,
          description: row.modelInvocable
              ? row.description
              : '${i18n().t('skill', 'menu.userOnly')} · ${row.description}',
        ),
    ];
  }

  @override
  PickOutcome onPick(InputTriggerPick pick) =>
      PickInsertText('/${pick.candidate.name} ');
  @override
  bool openReference(String sessionId, String ref, String? appearance) {
    if (sessions.isSubagentTranscript(sessionId) || _disposed) return false;
    bool open(List<SkillEntry> rows) {
      final path = rows.where((row) => '/${row.name}' == ref).firstOrNull?.path;
      if (path == null) return false;
      sessions.openFile(sessionId, path);
      return true;
    }

    final held = _catalogs[sessionId]?.value;
    if (held != null) return open(held);
    final entry = _fetch(sessionId);
    unawaited(
      entry.promise.then<void>((rows) {
        if (!entry.abort.signal.aborted && !_disposed) open(rows);
      }, onError: (Object e) {}),
    );
    return true;
  }

  void invalidate(String id) {
    final old = _catalogs.remove(id);
    if (old == null) return;
    old.abort.abort();
    _notify();
  }

  void clear() {
    for (final id in _catalogs.keys.toList()) {
      invalidate(id);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    clear();
    await _events?.cancel();
    await _generations?.cancel();
    await changed.dispose();
  }
}
