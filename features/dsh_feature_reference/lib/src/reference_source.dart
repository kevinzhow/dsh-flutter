import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/generated_file_references.dart'
    show FileReferenceCandidate, FileReferencesRemote;
import 'package:dsh_client/generated_session_reference_resolver.dart'
    show SessionReferenceMentionCandidate, SessionReferenceResolverRemote;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart' show abbreviateHome;

/// Compact relative time of a dated row (dsh `relativeTime`, ui-primitives):
/// the bucket and its magnitude.
({String unit, int n}) relativeTimeBucket(num at, num now) {
  const minute = 60000;
  const hour = 3600000;
  const day = 86400000;
  final diff = (now - at).clamp(0, double.infinity);
  if (diff < minute) return (unit: 'now', n: 0);
  if (diff < hour) return (unit: 'minutes', n: (diff / minute).floor());
  if (diff < day) return (unit: 'hours', n: (diff / hour).floor());
  if (diff < 30 * day) return (unit: 'days', n: (diff / day).floor());
  if (diff < 365 * day) return (unit: 'months', n: (diff / (30 * day)).floor());
  return (unit: 'years', n: (diff / (365 * day)).floor());
}

/// The `@` source (dsh `ui-reference`): files first, then direct subagents of
/// the current session, then other sessions. A file or session pick inserts an
/// atomic chip; a directory row also offers a drill that keeps the text
/// editable and the menu live.
class ReferenceSource extends InputTriggerSource {
  ReferenceSource({
    required this.files,
    required this.sessionReferences,
    required this.sessions,
    required DshI18n Function() i18n,
    DateTime Function()? now,
  }) : _i18n = i18n,
       _now = now ?? DateTime.now;

  final FileReferencesRemote files;
  final SessionReferenceResolverRemote sessionReferences;
  final InputSessionPort sessions;
  final DshI18n Function() _i18n;
  final DateTime Function() _now;

  @override
  TriggerChar get trigger => TriggerChar.at;

  @override
  String get name => 'reference';

  @override
  bool get showGroupTitle => false;

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      _i18n().t('reference', key, params: params);

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest req,
  ) async {
    // Candidate requests need the session's initial history open: an unheld
    // session or a failed open prevents both calls.
    await sessions.ensureOpen(sessionId, req.signal);
    req.signal.throwIfAborted();
    // One unavailable or failed domain yields no rows for that domain while the
    // other still lists.
    final fileLookup = files
        .list(sessionId, req.query)
        .catchError((Object _) => const <FileReferenceCandidate>[]);
    final sessionLookup = req.quoted
        ? Future.value(const <SessionReferenceMentionCandidate>[])
        : sessionReferences
              .candidates(sessionId, req.query)
              .catchError(
                (Object _) => const <SessionReferenceMentionCandidate>[],
              );
    final fileItems = await fileLookup;
    final sessionItems = await sessionLookup;
    if (req.signal.aborted) return const [];
    // The header already names the directory being listed; rows repeat it only
    // when there is no header to carry it.
    final withLocation =
        referenceCrumbs(req.query, req.quoted, req.drilled, _t('crumb.root')) ==
        null;
    final now = _now().millisecondsSinceEpoch;
    final home = sessions.hostHome;
    final rows = <({bool child, InputTriggerCandidate row})>[];
    for (final candidate in sessionItems) {
      final summary = sessions.summary(candidate.sessionId);
      final child =
          summary?.origin == 'subagent' &&
          summary?.parentSessionId == sessionId;
      rows.add((
        child: child,
        row: _sessionCandidate(
          candidate,
          candidate.displayTitle ?? candidate.label,
          summary?.updatedAt ?? candidate.createdAt,
          now,
          home,
          _t(child ? 'section.subagents' : 'section.sessions'),
        ),
      ));
    }
    return [
      for (final f in files0(fileItems))
        ..._fileCandidate(f, req.quoted, withLocation),
      for (final r in rows)
        if (r.child) r.row,
      for (final r in rows)
        if (!r.child) r.row,
    ];
  }

  List<FileCandidate> files0(List<FileReferenceCandidate> items) => [
    for (final c in items)
      FileCandidate(path: c.path, isDirectory: c.kind.value == 'directory'),
  ];

  @override
  List<InputTriggerCrumb>? header(String sessionId, HeaderRequest req) =>
      referenceCrumbs(req.query, req.quoted, req.drilled, _t('crumb.root'));

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    final value = _parse(pick.candidate.value);
    if (value == null) return null;
    if (value.kind == 'file') {
      // A directory row carries two verbs: the settling pick resolves the folder
      // itself as an atomic reference, while the drill action (Tab, the row's
      // chevron, a header crumb) keeps the literal descent text and the open
      // menu.
      if (value.directory && pick.action == PickAction.drill) {
        return PickInsertText(value.mention, keepCompleting: true);
      }
      return PickInsertReference(
        ReferenceInsert(
          source: 'reference',
          ref: value.mention,
          label: value.directory ? '${value.label}/' : value.label,
          appearance: value.directory ? 'folder' : 'file',
          clipboardText: value.mention,
        ),
      );
    }
    return PickInsertReference(
      ReferenceInsert(
        source: 'reference',
        ref: value.mention,
        label: value.label,
        appearance: 'session',
        clipboardText: value.mention,
      ),
    );
  }

  @override
  bool openReference(String sessionId, String ref, String? appearance) {
    if (appearance != 'file') return false;
    final path = ref.startsWith('@"')
        ? ref.substring(2, ref.length - 1)
        : ref.substring(1);
    sessions.openFile(sessionId, path);
    return true;
  }

  @override
  ReferenceCodec get codec => const _IdentityCodec();

  List<InputTriggerCandidate> _fileCandidate(
    FileCandidate candidate,
    bool preserveQuote,
    bool withLocation,
  ) {
    final mention = formatFileMention(candidate, preserveQuote);
    if (mention == null) return const [];
    final slash = candidate.path.lastIndexOf('/');
    final name = candidate.path.substring(slash + 1);
    final parent = slash < 0 ? '' : candidate.path.substring(0, slash);
    final value = jsonEncode({
      'kind': 'file',
      'fileKind': candidate.isDirectory ? 'directory' : 'file',
      'label': name,
      'mention': mention,
    });
    return [
      InputTriggerCandidate(
        name: '$name${candidate.isDirectory ? '/' : ''}',
        // The location is the parent alone: repeating the name the row already
        // shows says nothing, and a workspace-root entry has no parent to name.
        description: withLocation && parent != '' ? parent : null,
        icon: candidate.isDirectory ? 'folder' : 'file',
        section: _t('section.files'),
        value: value,
        drill: candidate.isDirectory,
      ),
    ];
  }

  InputTriggerCandidate _sessionCandidate(
    SessionReferenceMentionCandidate candidate,
    String label,
    num updatedAt,
    num now,
    String? home,
    String section,
  ) {
    final (:unit, :n) = relativeTimeBucket(updatedAt, now);
    final age = unit == 'now' ? _t('time.now') : _t('time.$unit', {'n': n});
    // Candidates are ranked by workspace affinity, so the location only tells
    // the user something when it is not the workspace they are already in.
    final location = candidate.sameWorkspace
        ? null
        : candidate.cwd == null
        ? _t('candidate.noCwd')
        : abbreviateHome(candidate.cwd!, home);
    return InputTriggerCandidate(
      name: label,
      description: location == null ? age : '$location · $age',
      icon: 'session',
      section: section,
      value: jsonEncode({
        'kind': 'session',
        'label': label,
        'mention': candidate.mention,
      }),
    );
  }
}

class _IdentityCodec implements ReferenceCodec {
  const _IdentityCodec();

  @override
  String clipboardText(String ref) => ref;

  /// A file pick keeps the natural text the shared grammar defines; a session
  /// pick carries the canonical mention. Serialization never rebuilds identity
  /// from the visible title.
  @override
  Future<String> serialize(String ref, AbortSignal signal) => Future.value(ref);
}

class _Value {
  const _Value(this.kind, this.label, this.mention, this.directory);
  final String kind;
  final String label;
  final String mention;
  final bool directory;
}

_Value? _parse(String? raw) {
  if (raw == null) return null;
  final m = jsonDecode(raw) as Map<String, Object?>;
  return _Value(
    m['kind']! as String,
    m['label']! as String,
    m['mention']! as String,
    m['fileKind'] == 'directory',
  );
}

String _directoryValue(String label, String mention) => jsonEncode({
  'kind': 'file',
  'fileKind': 'directory',
  'label': label,
  'mention': mention,
});

/// The breadcrumb of a drilled directory listing, from the workspace root down
/// to the directory being listed. Only a drill produces one: a path the user
/// typed carries its own context in the draft, while a drill replaced the text
/// they were reading with a deeper one and owes them the way back.
List<InputTriggerCrumb>? referenceCrumbs(
  String query,
  bool quoted,
  bool drilled,
  String rootLabel,
) {
  if (!drilled) return null;
  final slash = query.lastIndexOf('/');
  if (slash < 0) return null;
  final segments = query
      .substring(0, slash)
      .split('/')
      .where((s) => s != '')
      .toList();
  final crumbs = <InputTriggerCrumb>[
    InputTriggerCrumb(
      label: rootLabel,
      value: _directoryValue(rootLabel, quoted ? '@"' : '@'),
    ),
  ];
  for (final (index, segment) in segments.indexed) {
    final path = segments.sublist(0, index + 1).join('/');
    final mention = formatFileMention(
      FileCandidate(path: path, isDirectory: true),
      quoted,
    );
    // A trail whose steps cannot all be written back as mention text would send
    // the user somewhere they did not click: show no header instead.
    if (mention == null) return null;
    crumbs.add(
      InputTriggerCrumb(
        label: segment,
        value: _directoryValue(segment, mention),
        current: index == segments.length - 1,
      ),
    );
  }
  return crumbs;
}
