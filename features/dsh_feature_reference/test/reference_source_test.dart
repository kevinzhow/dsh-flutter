import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart' show RemoteCaller, RemoteException;
import 'package:dsh_client/generated_file_references.dart'
    show FileReferencesRemote;
import 'package:dsh_client/generated_session_reference_resolver.dart'
    show SessionReferenceResolverRemote;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_reference/dsh_feature_reference.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart' show SessionSummary;
import 'package:flutter_test/flutter_test.dart';

class _Host implements RemoteCaller {
  List<Map<String, Object?>> files = [];
  List<Map<String, Object?>> sessions = [];
  Object? fileError;
  Object? sessionError;
  final List<String> calls = [];

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add('$namespace/$method ${args['query']}');
    if (namespace == 'fileReferences') {
      if (fileError != null) throw fileError!;
      return files;
    }
    if (sessionError != null) throw sessionError!;
    return sessions;
  }
}

class _Sessions implements InputSessionPort {
  final Map<String, SessionSummary> summaries = {};
  final List<(String, String)> opened = [];
  Object? openError;
  @override
  String hostHome = '/home/user';

  @override
  Future<void> ensureOpen(String sessionId, AbortSignal signal) async {
    if (openError != null) throw openError!;
    if (sessionId == 'ghost') throw StateError('not held');
  }

  @override
  bool isSubagentTranscript(String sessionId) => false;
  @override
  SessionSummary? summary(String sessionId) => summaries[sessionId];
  @override
  void openFile(String sessionId, String path) => opened.add((sessionId, path));
}

Map<String, Object?> file(String path, [String kind = 'file']) => {
  'path': path,
  'kind': kind,
};

Map<String, Object?> session(
  String id,
  String label, {
  String? displayTitle,
  String? cwd,
  bool same = true,
  int created = 1000,
}) => {
  'sessionId': id,
  'label': label,
  'displayTitle': ?displayTitle,
  'cwd': ?cwd,
  'sameWorkspace': same,
  'createdAt': created,
  'mention': '@[${displayTitle ?? label}](dsh-session:$id)',
};

CandidateRequest req(
  String query, {
  bool quoted = false,
  bool drilled = false,
}) => CandidateRequest(
  query: query,
  quoted: quoted,
  position: TriggerPosition.inline,
  drilled: drilled,
  signal: AbortSignal.never,
);

InputTriggerPick pickOf(
  InputTriggerCandidate c, {
  PickAction action = PickAction.pick,
}) => InputTriggerPick(
  candidate: c,
  sessionId: 's1',
  position: TriggerPosition.inline,
  via: PickVia.menu,
  action: action,
  span: TokenSpan(2, 5, 3),
);

void main() {
  late _Host host;
  late _Sessions sessions;
  late ReferenceSource source;
  var locale = DshLocale.en;
  const now = 10 * 86400000;

  setUp(() {
    host = _Host();
    sessions = _Sessions();
    locale = DshLocale.en;
    source = ReferenceSource(
      files: FileReferencesRemote(host),
      sessionReferences: SessionReferenceResolverRemote(host),
      sessions: sessions,
      i18n: () => DshI18n(locale),
      now: () => DateTime.fromMillisecondsSinceEpoch(now),
    );
  });

  group('candidates', () {
    test('files come first, then direct subagents, then other sessions, each under its heading', () async {
      host.files = [file('src', 'directory'), file('README.md')];
      host.sessions = [
        session(
          'other',
          'Other chat',
          cwd: '/home/user/proj',
          same: false,
          created: now - 3 * 3600000,
        ),
        session(
          'child',
          'Child',
          displayTitle: 'Research subagent',
          created: now - 120000,
        ),
      ];
      sessions.summaries['child'] = const SessionSummary(
        sessionId: 'child',
        updatedAt: now - 120000,
        running: false,
        blank: false,
        agentAvailable: true,
        origin: 'subagent',
        parentSessionId: 's1',
      );
      sessions.summaries['other'] = const SessionSummary(
        sessionId: 'other',
        updatedAt: now - 3 * 3600000,
        running: false,
        blank: false,
        agentAvailable: true,
      );
      final rows = await source.candidates('s1', req(''));
      expect(rows.map((r) => r.name), [
        'src/',
        'README.md',
        'Research subagent',
        'Other chat',
      ]);
      expect(rows.map((r) => r.section), [
        'Files & folders',
        'Files & folders',
        'Subagents',
        'Sessions',
      ]);
      expect(rows[0].drill, isTrue);
      expect(rows[0].icon, 'folder');
      expect(rows[1].icon, 'file');
      // A session in the current workspace is dated alone; another shows its home-relative location.
      expect(rows[2].description, '2min');
      expect(rows[3].description, '~/proj · 3h');
      expect(rows[3].icon, 'session');
    });

    test(
      'a file row names its parent directory, a root entry names nothing',
      () async {
        host.files = [file('a/b/c.txt'), file('root.txt')];
        final rows = await source.candidates('s1', req('c'));
        expect(rows.map((r) => r.description), ['a/b', null]);
        expect(rows.map((r) => r.name), ['c.txt', 'root.txt']);
      },
    );

    test('a drilled listing owes its header the location', () async {
      host.files = [file('src/util/a.dart')];
      final rows = await source.candidates('s1', req('src/', drilled: true));
      expect(rows.single.description, isNull);
    });

    test('a quoted token searches files only', () async {
      host.files = [file('my docs/read me.md')];
      host.sessions = [session('x', 'X')];
      final rows = await source.candidates('s1', req('my docs/', quoted: true));
      expect(
        host.calls.where((c) => c.startsWith('sessionReferenceResolver')),
        isEmpty,
      );
      expect(rows.single.name, 'read me.md');
      expect(
        jsonDecode(rows.single.value!)['mention'],
        '@"my docs/read me.md"',
      );
    });

    test(
      'one failing domain yields no rows for it while the other still lists',
      () async {
        host.fileError = RemoteException('gateway/internal', 'boom');
        host.sessions = [session('x', 'Planning')];
        expect((await source.candidates('s1', req(''))).map((r) => r.name), [
          'Planning',
        ]);
        host.fileError = null;
        host.files = [file('a.txt')];
        host.sessionError = RemoteException('gateway/internal', 'boom');
        expect((await source.candidates('s1', req(''))).map((r) => r.name), [
          'a.txt',
        ]);
      },
    );

    test('a path the grammar cannot write is skipped', () async {
      host.files = [file('bad"name.txt'), file('ok.txt')];
      expect((await source.candidates('s1', req(''))).map((r) => r.name), [
        'ok.txt',
      ]);
    });

    test(
      'a session that is not open or not held asks nothing of the host',
      () async {
        await expectLater(
          source.candidates('ghost', req('')),
          throwsStateError,
        );
        sessions.openError = StateError('open failed');
        await expectLater(source.candidates('s1', req('')), throwsStateError);
        expect(host.calls, isEmpty);
      },
    );

    test('an aborted request stops before asking the host', () async {
      final abort = AbortController();
      host.files = [file('a.txt')];
      final pending = source.candidates(
        's1',
        CandidateRequest(
          query: '',
          quoted: false,
          position: TriggerPosition.inline,
          drilled: false,
          signal: abort.signal,
        ),
      );
      abort.abort();
      await expectLater(pending, throwsA(anything));
      expect(host.calls, isEmpty);
    });

    test('the zh copy localizes headings and ages', () async {
      locale = DshLocale.zh;
      host.files = [file('a.txt')];
      host.sessions = [session('x', '规划', created: now - 2 * 86400000)];
      final rows = await source.candidates('s1', req(''));
      expect(rows.map((r) => r.section), ['文件与文件夹', '对话']);
      expect(rows.last.description, '2天');
    });

    test('a session without a recorded directory says so', () async {
      host.sessions = [session('x', 'Loose', same: false)];
      final rows = await source.candidates('s1', req(''));
      expect(rows.single.description, startsWith('(no cwd) · '));
    });
  });

  group('picks', () {
    InputTriggerCandidate row(Map<String, Object?> m) =>
        InputTriggerCandidate(name: 'x', value: jsonEncode(m));

    test('a file inserts an atomic chip whose reference and clipboard text is the mention', () {
      final out =
          source.onPick(
                pickOf(
                  row({
                    'kind': 'file',
                    'fileKind': 'file',
                    'label': 'main.dart',
                    'mention': '@src/main.dart',
                  }),
                ),
              )!
              as PickInsertReference;
      expect(out.reference.source, 'reference');
      expect(out.reference.ref, '@src/main.dart');
      expect(out.reference.clipboardText, '@src/main.dart');
      expect(out.reference.label, 'main.dart');
      expect(out.reference.appearance, 'file');
    });

    test('a directory settles as a folder chip with a trailing slash and drills as plain text', () {
      final value = {
        'kind': 'file',
        'fileKind': 'directory',
        'label': 'src',
        'mention': '@src/',
      };
      final settled = source.onPick(pickOf(row(value)))! as PickInsertReference;
      expect(settled.reference.label, 'src/');
      expect(settled.reference.appearance, 'folder');
      final drilled =
          source.onPick(pickOf(row(value), action: PickAction.drill))!
              as PickInsertText;
      expect(drilled.text, '@src/');
      expect(drilled.keepCompleting, isTrue);
    });

    test('a session inserts the canonical mention the host returned, never rebuilt from the title', () {
      final out =
          source.onPick(
                pickOf(
                  row({
                    'kind': 'session',
                    'label': 'Planning',
                    'mention': '@[Planning](dsh-session:abc)',
                  }),
                ),
              )!
              as PickInsertReference;
      expect(out.reference.ref, '@[Planning](dsh-session:abc)');
      expect(out.reference.appearance, 'session');
      expect(out.reference.label, 'Planning');
    });

    test('a candidate with no payload is not ours', () {
      expect(
        source.onPick(pickOf(const InputTriggerCandidate(name: 'x'))),
        isNull,
      );
    });

    test('the codec serializes a reference to itself', () async {
      expect(source.codec.clipboardText('@a b'), '@a b');
      expect(
        await source.codec.serialize('@"a b"', AbortSignal.never),
        '@"a b"',
      );
    });
  });

  group('header', () {
    test('only a drill publishes a trail from the workspace root', () {
      expect(
        source.header(
          's1',
          const HeaderRequest(
            query: 'src/util/',
            quoted: false,
            drilled: false,
          ),
        ),
        isNull,
      );
      final trail = source.header(
        's1',
        const HeaderRequest(query: 'src/util/', quoted: false, drilled: true),
      )!;
      expect(trail.map((c) => c.label), ['Workspace', 'src', 'util']);
      expect(trail.map((c) => c.current), [false, false, true]);
      expect(jsonDecode(trail[1].value)['mention'], '@src/');
      expect(jsonDecode(trail[2].value)['mention'], '@src/util/');
      expect(jsonDecode(trail[0].value)['mention'], '@');
    });

    test('a quoted trail keeps the quote open', () {
      final trail = source.header(
        's1',
        const HeaderRequest(query: 'my docs/sub/', quoted: true, drilled: true),
      )!;
      expect(jsonDecode(trail[0].value)['mention'], '@"');
      expect(jsonDecode(trail[1].value)['mention'], '@"my docs/');
    });

    test('no slash, no trail; an unwritable step drops the whole trail', () {
      expect(
        source.header(
          's1',
          const HeaderRequest(query: 'src', quoted: false, drilled: true),
        ),
        isNull,
      );
      expect(
        source.header(
          's1',
          const HeaderRequest(query: 'a"b/c/', quoted: false, drilled: true),
        ),
        isNull,
      );
    });

    test('a crumb pick drills to its directory', () {
      final trail = source.header(
        's1',
        const HeaderRequest(query: 'src/util/', quoted: false, drilled: true),
      )!;
      final out =
          source.onPick(
                pickOf(
                  InputTriggerCandidate(name: 'src', value: trail[1].value),
                  action: PickAction.drill,
                ),
              )!
              as PickInsertText;
      expect(out.text, '@src/');
    });
  });

  group('opening a chip', () {
    test('a file chip opens in the session sidebar, quoted or not', () {
      expect(source.openReference('s1', '@src/a.dart', 'file'), isTrue);
      expect(source.openReference('s1', '@"my docs/a b.md"', 'file'), isTrue);
      expect(sessions.opened, [('s1', 'src/a.dart'), ('s1', 'my docs/a b.md')]);
    });

    test('folders and sessions keep their editing behaviour', () {
      expect(source.openReference('s1', '@src/', 'folder'), isFalse);
      expect(
        source.openReference('s1', '@[x](dsh-session:1)', 'session'),
        isFalse,
      );
      expect(sessions.opened, isEmpty);
    });
  });

  group('against dsh', () {
    final fixture = jsonDecode(
      File('../../packages/dsh_conversation/test/fixtures/input_vector.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();

    test('the relative-time buckets match dsh at every boundary', () {
      final times = cases.where((c) => c['op'] == 'time').toList();
      expect(times, isNotEmpty);
      for (final c in times) {
        final got = relativeTimeBucket(c['at']! as num, c['now']! as num);
        expect(
          {'unit': got.unit, 'n': got.n},
          c['expect'],
          reason: '${c['at']}..${c['now']}',
        );
      }
    });
  });
}
