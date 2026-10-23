import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_tool/dsh_feature_tool.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart' hide isAbsoluteWorkspacePath;
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);
const zh = DshI18n(DshLocale.zh);

String t(String key, [Map<String, Object?> params = const {}]) =>
    en.t('conversation', key, params: params);

ToolResult done(
  String name,
  Map<String, Object?> args, {
  String? text = 'ok',
  List<Object?>? content,
  bool error = false,
  Map<String, Object?>? errorBody,
  Object? meta,
  String id = 'c1',
  String? parent,
}) {
  final raw = jsonEncode(args);
  return ToolResult(
    callId: id,
    name: name,
    args: PartialArguments.fromText(raw),
    subCalls: const [],
    seq: 9,
    time: 1,
    callArgsRaw: raw,
    content:
        content ??
        [
          if (text != null) {'type': 'text', 'text': text},
        ],
    isError: error,
    error: errorBody,
    meta: meta,
    parentCallId: parent,
  );
}

StartedToolCall started(
  String name,
  Map<String, Object?> args, {
  String id = 'c1',
}) {
  final raw = jsonEncode(args);
  return StartedToolCall(
    callId: id,
    name: name,
    args: PartialArguments.fromText(raw),
    subCalls: const [],
    argsRaw: raw,
    turn: 1,
    step: 1,
    time: 1,
  );
}

PreparingToolCall preparing(String name, String partial, {String id = 'c1'}) =>
    PreparingToolCall(
      callId: id,
      name: name,
      args: PartialArguments()..append(partial),
      subCalls: const [],
      turn: 1,
      step: 1,
      time: 1,
    );

class Harness {
  Harness({
    this.i18n = en,
    ToolHostActions actions = const ToolHostActions(),
    this.cwd,
    this.home = '',
    bool Function(String)? expanded,
  }) {
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerToolFeature(
      slots,
      i18n: () => i18n,
      actions: actions,
      expandedByDefault: expanded,
    );
    final base = testSessionOwner('s1');
    owner = SessionOwner(
      session: base.session,
      conversation: base.conversation,
      actions: base.actions,
      cwdReader: () => cwd,
      hostHome: home,
    );
  }
  final DshI18n i18n;
  final String? cwd;
  final String home;
  final SlotRegistry slots = SlotRegistry();
  late final SessionOwner owner;

  Widget widget(ToolCall call) => dshTestApp(
    SingleChildScrollView(
      child: slots.renderKeyed<ChatNodeOwner, Widget>(
        chatNodeSlot,
        'tool-call',
        ChatNodeOwner(
          session: owner,
          node: ViewNode(
            key: 'k',
            kind: 'tool-call',
            id: call.callId,
            target: 'chat',
            anchorSeq: 1,
            location: const SessionLocation(),
            visible: true,
            data: ToolData(call),
          ),
          snapshot: ChatSnapshot.empty,
        ),
      )!,
    ),
  );
}

Map<String, Object?> shellArgs(
  String command, {
  String description = 'Run it',
  Map<String, Object?> extra = const {},
}) => {'command': command, 'description': description, ...extra};

void main() {
  group('row model', () {
    test('titles, variants and summaries', () {
      final m = toolRowModel('bash', done('bash', shellArgs('ls')));
      expect(m.titleKey, 'tool.title.bash');
      expect(m.summary, 'Run it');
      expect(m.state, ToolRowState.ok);
      final g = toolRowModel('mystery', done('mystery', {'a': 'b c'}));
      expect(g.titleKey, 'tool.title.generic');
      expect(g.summary, 'mystery · b c');
      expect(toolTitleKey('pwsh'), 'tool.title.pwsh');
      expect(toolTitleKey('todo_write'), 'todo.rowTitle');
      expect(classifyTool('web_fetch'), ToolRowVariant.read);
    });

    test('state follows the call and the result', () {
      expect(
        toolRowModel('bash', preparing('bash', '{"c')).state,
        ToolRowState.preparing,
      );
      expect(
        toolRowModel('bash', started('bash', {})).state,
        ToolRowState.running,
      );
      expect(
        toolRowModel(
          'bash',
          done('bash', {}, error: true, errorBody: {'code': 'interrupted'}),
        ).state,
        ToolRowState.stopped,
      );
      final failed = toolRowModel(
        'bash',
        done('bash', {}, error: true, text: 'boom\nmore'),
      );
      expect(failed.state, ToolRowState.error);
      expect(failed.errorSummary, 'boom');
    });

    test('file rows relativize to the cwd, abbreviate the home and prefer the recorded path', () {
      final call = done(
        'read',
        {'file_path': '/w/app/lib/a.dart'},
        meta: {'path': '/w/app/lib/a.dart'},
      );
      final m = toolRowModel('read', call, cwd: '/w/app', home: '/h');
      expect(m.summary, 'lib/a.dart');
      expect(m.filePath, '/w/app/lib/a.dart');
      expect(
        toolRowModel(
          'read',
          done('read', {'file_path': '/h/x.txt'}),
          home: '/h',
        ).summary,
        '~/x.txt',
      );
      // a relative path of a nested call stays unopenable
      expect(
        toolRowModel(
          'read',
          done('read', {'file_path': 'x'}, parent: 'p'),
        ).filePath,
        isNull,
      );
    });

    test('an auto-review denial is recognised and localized', () {
      final call = done(
        'bash',
        shellArgs('rm'),
        error: true,
        text: '',
        errorBody: {
          'name': 'AutoReviewDeniedError',
          'code': 'AUTO_REVIEW_DENIED',
          'reason': '  unsafe\ncommand ',
        },
      );
      final denial = toolRowModel('bash', call).autoReviewDenial!;
      final p = localizeAutoReviewDenial(denial, t);
      expect(p.summary, t('tool.autoReviewRejected'));
      expect(
        p.output,
        t('tool.autoReviewNotExecuted', {'reason': 'unsafe command'}),
      );
      expect(
        localizeAutoReviewDenial((reason: null), t).output,
        contains(t('tool.autoReviewReasonFallback')),
      );
    });

    test('paths: absolute, resolved, abbreviated', () {
      expect(isAbsoluteWorkspacePath(r'C:\x'), isTrue);
      expect(isAbsoluteWorkspacePath('x/y'), isFalse);
      expect(resolveWorkspacePath('/w/', 'a/b'), '/w/a/b');
      expect(resolveWorkspacePath(r'C:\w', 'a'), r'C:\w\a');
      expect(abbreviateHomePath('/h', '/h'), '~');
      expect(abbreviateHomePath('/home2/x', '/home'), '/home2/x');
      expect(normalizeSegments('/w/app/..'), '/w');
      expect(normalizeSegments('a/../../b'), '../b');
    });
  });

  group('terminal model', () {
    test('a clean command parses to output and exit 0', () {
      final m = terminalCardModel(
        done('bash', shellArgs('ls'), text: 'a\nb'),
        sessionCwd: '/w',
      )!;
      expect(m.output, 'a\nb');
      expect(m.exitCode, 0);
      expect(m.failed, isFalse);
      expect(m.cwd, '/w');
    });

    test('exit markers: code, null and signal', () {
      final bad = terminalCardModel(
        done('bash', shellArgs('x'), text: 'oops\n[exit code: 3]'),
      )!;
      expect((bad.output, bad.exitCode, bad.failed), ('oops', 3, true));
      final none = terminalCardModel(
        done('bash', shellArgs('x'), text: 'o\n[exit code: null]'),
      )!;
      expect((none.exitCodeMissing, none.failed), (true, true));
      final sig = terminalCardModel(
        done('bash', shellArgs('x'), text: 'o\n[killed by signal: SIGTERM]'),
      )!;
      expect((sig.signal, sig.failed), ('SIGTERM', true));
      expect(
        terminalExitLabel(sig, t),
        t('terminal.signal', {'signal': 'SIGTERM'}),
      );
      expect(terminalExitLabel(bad, t), t('terminal.exitCode', {'code': 3}));
      expect(terminalExitLabel(none, t), t('terminal.noExitCode'));
    });

    test('workdir joins the session cwd, an absolute one wins, the recorded cwd beats both', () {
      expect(
        terminalCardModel(
          done('bash', shellArgs('x', extra: {'workdir': 'sub/../pkg'})),
          sessionCwd: '/w',
        )!.cwd,
        '/w/pkg',
      );
      expect(
        terminalCardModel(
          done('bash', shellArgs('x', extra: {'workdir': '/abs'})),
          sessionCwd: '/w',
        )!.cwd,
        '/abs',
      );
      expect(
        terminalCardModel(
          done('bash', shellArgs('x'), meta: {'cwd': '/rec'}),
          sessionCwd: '/w',
        )!.cwd,
        '/rec',
      );
    });

    test('a running call is a banner without output', () {
      final m = terminalCardModel(started('bash', shellArgs('sleep 9')))!;
      expect((m.running, m.output), (true, null));
    });

    test('persistent shells, spill previews, errors and malformed input stay generic', () {
      expect(terminalCardModel(done('bash', {'command': 'ls'})), isNull);
      expect(
        isSettledPersistentShellCall(done('bash', {'command': 'ls'})),
        isTrue,
      );
      final spill =
          'out\n\n(Omitted 40 bytes. Full formatted result stored at: /tmp/x. Read it with read)';
      expect(
        isSpilledShellCall(done('bash', shellArgs('x'), text: spill)),
        isTrue,
      );
      expect(
        terminalCardModel(done('bash', shellArgs('x'), text: spill)),
        isNull,
      );
      expect(
        terminalCardModel(done('bash', shellArgs('x'), error: true)),
        isNull,
      );
      expect(
        terminalCardModel(done('bash', {'command': '', 'description': 'd'})),
        isNull,
      );
      expect(hasSpillNotice('plain text'), isFalse);
    });

    test('a background launch keeps its command only', () {
      final call = done(
        'bash',
        shellArgs('serve', extra: {'run_in_background': true}),
        text: 'started job 1',
      );
      expect(isBackgroundShellCall(call), isTrue);
      final m = terminalCardModel(call)!;
      expect((m.background, m.output), (true, null));
      expect(terminalExitLabel(m, t), isNull);
    });

    test('terminal_send is a card with the session in its description', () {
      final m = terminalCardModel(
        done('terminal_send', {'sessionId': 'tty1', 'text': 'q'}, text: 'bye'),
      )!;
      expect((m.command, m.sendSessionId, m.output), ('q', 'tty1', 'bye'));
      expect(
        terminalCardModel(
          done('terminal_send', {
            'sessionId': 'tty1',
            'text': 'q',
            'run_in_background': true,
          }),
        ),
        isNull,
      );
    });
  });

  group('diff, read, search and web models', () {
    test('edit uses the applied diffs, write falls back to its arguments', () {
      final edit = done(
        'edit',
        {'file_path': 'a.dart', 'old_string': 'x', 'new_string': 'y'},
        meta: {
          'path': '/w/a.dart',
          'diffs': [
            {'path': '/w/a.dart', 'oldText': 'x\n', 'newText': 'y\n'},
          ],
        },
      );
      final d = diffCardModel(edit)!;
      expect((d.single.path, d.single.newText), ('a.dart', 'y\n'));
      expect(
        diffCardModel(
          done('edit', {
            'file_path': 'a',
            'old_string': 'x',
            'new_string': 'y',
          }),
        ),
        isNull,
      );
      final write = diffCardModel(
        done('write', {'file_path': 'n.txt', 'content': 'hello\n'}),
      )!;
      expect((write.single.oldText, write.single.newText), (null, 'hello\n'));
      expect(
        diffCardModel(
          done('edit', {
            'file_path': 'a',
            'old_string': 'x',
            'new_string': 'y',
          }, error: true),
        ),
        isNull,
      );
      expect(
        diffCardModel(
          done('write', {'file_path': 'a', 'content': 'x'}, parent: 'p'),
        ),
        isNull,
      );
    });

    test('str_replace_editor shows its diff only while it runs', () {
      final args = {
        'command': 'str_replace',
        'path': 'a.py',
        'old_str': 'a',
        'new_str': 'b',
      };
      expect(
        diffCardModel(started('str_replace_editor', args))!.single.newText,
        'b',
      );
      expect(diffCardModel(done('str_replace_editor', args)), isNull);
      expect(
        diffCardModel(
          started('str_replace_editor', {
            'command': 'create',
            'path': 'n.py',
            'file_text': 't',
          }),
        )!.single.oldText,
        isNull,
      );
    });

    test('read validates its metadata and the model envelope', () {
      const envelope =
          '<path>/w/a.dart</path>\n<type>file</type>\n<content>\n1: a\n</content>';
      final ok = done(
        'read',
        {'file_path': '/w/a.dart', 'offset': 5},
        text: envelope,
        meta: {
          'path': '/w/a.dart',
          'offset': 5,
          'totalLines': 40,
          'lang': 'dart',
          'lines': [
            {'number': 5, 'text': 'a'},
            {'number': 6, 'text': 'b'},
          ],
        },
      );
      final m = readCardModel(ok, cwd: '/w')!;
      expect(
        (m.label, m.totalLines, m.lang, m.lines.length),
        ('a.dart', 40, 'dart', 2),
      );
      expect(readCallLine(ok), 5);
      expect(
        readCardModel(
          done(
            'read',
            {'file_path': '/w/a.dart'},
            text: 'no envelope',
            meta: {'path': 'p', 'offset': 1, 'totalLines': 0, 'lines': []},
          ),
        ),
        isNull,
      );
      expect(
        readCardModel(
          done('read', {'file_path': '/w/a.dart', 'offset': 0}, text: envelope),
        ),
        isNull,
      );
    });

    test('search cards come from grep and glob metadata', () {
      final grep = searchCardModel(
        done(
          'grep',
          {'pattern': 'foo'},
          meta: {
            'shape': 'matches',
            'truncated': false,
            'total': 2,
            'files': [
              {
                'path': 'a',
                'matches': [
                  {'lineNumber': 1, 'line': 'foo'},
                  {'lineNumber': 4, 'line': 'foo2'},
                ],
              },
            ],
          },
        ),
      )!;
      expect((grep.files!.single.matches.length, grep.total), (2, 2));
      final glob = searchCardModel(
        done(
          'glob',
          {'pattern': '*.dart'},
          text: 'Full result stored at /tmp/z',
          meta: {
            'shape': 'paths',
            'truncated': true,
            'total': 90,
            'paths': ['a.dart'],
          },
        ),
      )!;
      expect(glob.paths, ['a.dart']);
      expect(glob.recovery, 'Full result stored at /tmp/z');
      expect(
        searchCardModel(
          done(
            'grep',
            {'pattern': ''},
            meta: {
              'shape': 'matches',
              'truncated': false,
              'total': 0,
              'files': [],
            },
          ),
        ),
        isNull,
      );
      expect(
        searchCardModel(
          done('grep', {'pattern': 'x', 'include': '!x'}, meta: {}),
        ),
        isNull,
      );
    });

    test('web cards: search sources, fetch status, links', () {
      final search = webCardModel(
        done(
          'web_search',
          {
            'queries': ['dart'],
          },
          meta: {
            'truncated': true,
            'answer': 'An answer',
            'sources': [
              {'url': 'https://a.example', 'title': 'A'},
            ],
          },
        ),
      )!;
      expect(
        (search.answer, search.sources!.single.title, search.truncated),
        ('An answer', 'A', true),
      );
      final fetch = webCardModel(
        done(
          'web_fetch',
          {'url': 'https://a.example'},
          meta: {
            'truncated': false,
            'url': 'https://a.example',
            'statusCode': 200,
          },
        ),
      )!;
      expect(fetch.statusCode, 200);
      expect(
        webFetchHref(done('web_fetch', {'url': 'https://a.example/x'}))?.host,
        'a.example',
      );
      expect(
        webFetchHref(done('web_fetch', {'url': 'file:///etc/passwd'})),
        isNull,
      );
    });
  });

  group('todo and details models', () {
    final tr = (String key, [Map<String, Object?> p = const {}]) => t(key, p);
    ToolResult todoCall(List<List<String>> items) => done('todo_write', {
      'todos': [
        for (final i in items) {'content': i[0], 'status': i[1]},
      ],
    });

    test('the diff against the previous list names added, updated, removed and moved', () {
      final previous = TodoBaseline([
        const TodoItem('a', 'in_progress'),
        const TodoItem('b', 'pending'),
        const TodoItem('gone', 'pending'),
      ]);
      final d = todoDiffModel(
        todoCall([
          ['a', 'completed'],
          ['b', 'pending'],
          ['new', 'pending'],
        ]),
        previous,
        false,
        tr,
      )!;
      expect(
        d.summary,
        '${t('todo.diff.added', {'count': 1})} · ${t('todo.diff.updated', {'count': 1})} · ${t('todo.diff.removed', {'count': 1})}',
      );
      final byTitle = {for (final i in d.details.items) i.title: i};
      expect(byTitle['a']!.change!.value, 'updated');
      expect(byTitle['a']!.previousStatus, t('detail.todo.in_progress'));
      expect(byTitle['new']!.change!.value, 'added');
      expect(byTitle['gone']!.change!.value, 'removed');
      expect(d.details.unchanged!.items.single.title, 'b');
    });

    test('no baseline or an older unloaded list says the previous list is unavailable', () {
      final unknown = todoDiffModel(
        todoCall([
          ['a', 'pending'],
        ]),
        null,
        false,
        tr,
      )!;
      expect(unknown.summary, isNull);
      expect(unknown.details.caption, t('todo.diff.unavailable'));
      final hasMore = todoDiffModel(
        todoCall([
          ['a', 'pending'],
        ]),
        const TodoBaseline(null),
        true,
        tr,
      )!;
      expect(hasMore.details.caption, t('todo.diff.unavailable'));
      final first = todoDiffModel(
        todoCall([
          ['a', 'pending'],
        ]),
        const TodoBaseline(null),
        false,
        tr,
      )!;
      expect(first.details.caption, t('todo.diff.initial'));
    });

    test('an unchanged list is "no changes"; invalid lists are generic', () {
      final same = todoDiffModel(
        todoCall([
          ['a', 'pending'],
        ]),
        const TodoBaseline([TodoItem('a', 'pending')]),
        false,
        tr,
      )!;
      expect(same.summary, t('todo.diff.noChanges'));
      expect(
        todosDetail({
          'todos': [
            {'content': 'a', 'status': 'bogus'},
          ],
        }, tr),
        isNull,
      );
      expect(
        todosDetail({
          'todos': [
            {'content': 'a', 'status': 'pending'},
            {'content': 'a', 'status': 'pending'},
          ],
        }, tr),
        isNull,
      );
    });

    test('goal and schedule results become details; others stay generic', () {
      final goal = detailsCardModel(
        done(
          'get_goal',
          {},
          text: jsonEncode({
            'goal': {
              'id': 'g',
              'objective': 'Ship',
              'revision': 1,
              'roundsStarted': 2,
              'maxGoalRounds': 9,
              'phase': 'active',
            },
            'activation': 'armed',
          }),
        ),
        tr,
      )!;
      expect(goal.items.single.title, 'Ship');
      expect(goal.items.single.fields.last.value, '2 / 9');
      expect(
        detailsCardModel(
          done('get_goal', {}, text: jsonEncode({'goal': null})),
          tr,
        )!.empty,
        t('detail.goal.empty'),
      );
      final sched = detailsCardModel(
        done(
          'schedule_list',
          {},
          text: jsonEncode([
            {
              'id': 's',
              'prompt': 'p',
              'title': 'Daily check',
              'scheduledAt': '2026-10-24T08:00:00.000Z',
              'deliveryMode': 'host',
              'state': 'scheduled',
              'kind': 'daily',
              'time': '09:00:00.000',
              'timeZone': 'UTC',
            },
          ]),
        ),
        tr,
      )!;
      expect(sched.summary, t('detail.schedule.count', {'count': 1}));
      expect(
        sched.items.single.fields[1].value,
        t('detail.schedule.daily', {'time': '09:00', 'zone': 'UTC'}),
      );
      expect(detailsCardModel(done('job_list', {}, text: '[]'), tr), isNull);
      expect(detailsCardModel(done('get_goal', {}, error: true), tr), isNull);
    });

    test('ask questions pair answers by id and present each verdict', () {
      final args = {
        'questions': [
          {'id': 'q1', 'question': 'Colour?'},
          {'id': 'q2', 'question': 'Size?'},
        ],
      };
      final answered = done(
        'ask_user_question',
        args,
        text: jsonEncode({
          'answers': [
            {
              'id': 'q1',
              'selected': ['Red'],
            },
            {'id': 'q2', 'selected': [], 'custom': 'XL'},
          ],
        }),
      );
      final model = toolRowModel('ask_user_question', answered);
      final p = presentAsk(
        answered,
        model,
        tr,
        answerable: false,
        settledAnswers: null,
      );
      expect(p.summary, t('ask.answered', {'answered': 2, 'total': 2}));
      final card = p.transcript as AnsweredAsk;
      expect(card.questions[1].answers, ['XL']);
      // ids that do not pair: the summary survives, the transcript does not
      final odd = done(
        'ask_user_question',
        args,
        text: jsonEncode({
          'answers': [
            {
              'id': 'zzz',
              'selected': ['x'],
            },
            {'id': 'q2', 'selected': []},
          ],
        }),
      );
      final q = presentAsk(
        odd,
        toolRowModel('ask_user_question', odd),
        tr,
        answerable: false,
        settledAnswers: null,
      );
      expect(q.transcript, isNull);
      expect(q.summary, t('ask.answered', {'answered': 1, 'total': 2}));
    });

    test('ask: cancelled, aborted, running, pending and closed', () {
      final args = {
        'questions': [
          {'id': 'q', 'question': 'Q?'},
        ],
      };
      AskPresentation of(
        ToolCall c, {
        bool answerable = false,
        List<AskAnswer>? settled,
      }) => presentAsk(
        c,
        toolRowModel('ask_user_question', c),
        tr,
        answerable: answerable,
        settledAnswers: settled,
      );
      expect(
        of(
          done(
            'ask_user_question',
            args,
            error: true,
            errorBody: {'code': 'ASK_CANCELLED'},
          ),
        ).summary,
        t('ask.cancelled'),
      );
      final aborted = of(
        done(
          'ask_user_question',
          args,
          error: true,
          errorBody: {'code': 'ASK_ABORTED'},
        ),
      );
      expect(
        (aborted.summary, aborted.state),
        (t('ask.interrupted'), ToolRowState.stopped),
      );
      expect(of(started('ask_user_question', args)).summary, t('ask.waiting'));
      final pendingText = jsonEncode({'pending': true, 'callId': 'c1'});
      expect(
        of(
          done('ask_user_question', args, text: pendingText),
          answerable: true,
        ).summary,
        t('ask.pending'),
      );
      expect(
        of(done('ask_user_question', args, text: pendingText)).summary,
        t('ask.closed'),
      );
      final late = of(
        done('ask_user_question', args, text: pendingText),
        settled: const [
          AskAnswer('q', ['Yes'], null),
        ],
      );
      expect(late.summary, t('ask.answered', {'answered': 1, 'total': 1}));
    });
  });

  group('rows', () {
    testWidgets(
      'bash: a settled call is a collapsed row; tapping opens the terminal card',
      (tester) async {
        final h = Harness(cwd: '/w/app', home: '/w');
        await tester.pumpWidget(
          h.widget(
            done(
              'bash',
              shellArgs('ls -la src', description: 'List the source'),
              text: 'a.txt\nb.txt',
            ),
          ),
        );
        expect(find.text('Bash'), findsOneWidget);
        expect(find.text('List the source'), findsOneWidget);
        expect(find.text('a.txt'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('tool-row-bash')));
        await tester.pump();
        expect(find.text('ls -la src'), findsOneWidget);
        expect(find.text('a.txt'), findsOneWidget);
        expect(find.text('app'), findsOneWidget);
        await tester.tap(find.text('Bash'));
        await tester.pump();
        expect(find.text('a.txt'), findsNothing);
      },
    );

    testWidgets(
      'bash: a failing exit shows the capsule beside the description',
      (tester) async {
        final h = Harness();
        await tester.pumpWidget(
          h.widget(
            done(
              'bash',
              shellArgs('cat x', description: 'Print x'),
              text: 'no such file\n[exit code: 1]',
            ),
          ),
        );
        expect(find.text('Print x'), findsOneWidget);
        expect(find.text(t('terminal.exitCode', {'code': 1})), findsOneWidget);
      },
    );

    testWidgets(
      'bash: preparing shows the streamed description and cannot expand',
      (tester) async {
        final h = Harness();
        await tester.pumpWidget(
          h.widget(preparing('bash', '{"description":"Run the te')),
        );
        expect(find.text('Run the te'), findsWidgets);
        await tester.tap(find.byKey(const ValueKey('tool-row-bash')));
        await tester.pump();
        expect(find.byKey(const ValueKey('terminal-block')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('bash: running shows a prompt-only card when expanded', (
      tester,
    ) async {
      final h = Harness(expanded: (_) => true);
      await tester.pumpWidget(
        h.widget(started('bash', shellArgs('sleep 9', description: 'Wait'))),
      );
      expect(find.byKey(const ValueKey('terminal-block')), findsOneWidget);
      expect(find.text('sleep 9'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'bash: persistent output and errors use the input/output card',
      (tester) async {
        final h = Harness(expanded: (_) => true);
        await tester.pumpWidget(
          h.widget(done('bash', {'command': 'ls'}, text: 'files')),
        );
        expect(find.byKey(const ValueKey('io-card')), findsOneWidget);
        expect(find.text('files'), findsOneWidget);
        await tester.pumpWidget(
          h.widget(
            done(
              'bash',
              shellArgs('boom'),
              error: true,
              text: 'it broke\nsecond',
            ),
          ),
        );
        expect(find.text('it broke'), findsOneWidget);
        expect(find.byKey(const ValueKey('io-card')), findsOneWidget);
      },
    );

    testWidgets('pwsh uses the bash row with its own title', (tester) async {
      final h = Harness();
      await tester.pumpWidget(
        h.widget(done('pwsh', shellArgs('Get-Date', description: 'Date'))),
      );
      expect(find.text(t('tool.title.pwsh')), findsOneWidget);
    });

    testWidgets('edit: path link, +/- totals and the diff card', (
      tester,
    ) async {
      String? opened;
      final h = Harness(
        cwd: '/w',
        actions: ToolHostActions(openFile: (p, {line}) => opened = p),
        expanded: (_) => true,
      );
      await tester.pumpWidget(
        h.widget(
          done(
            'edit',
            {
              'file_path': '/w/src/a.dart',
              'old_string': 'x',
              'new_string': 'y',
            },
            meta: {
              'path': '/w/src/a.dart',
              'diffs': [
                {
                  'path': '/w/src/a.dart',
                  'oldText': 'k\nx\nm\n',
                  'newText': 'k\ny\nm\n',
                },
              ],
            },
          ),
        ),
      );
      expect(find.text('src/a.dart'), findsWidgets);
      expect(find.textContaining('+1', findRichText: true), findsOneWidget);
      expect(find.textContaining('-1', findRichText: true), findsOneWidget);
      expect(find.text('- x'), findsOneWidget);
      expect(find.text('+ y'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-link')));
      expect(opened, '/w/src/a.dart');
    });

    testWidgets('write: all-added diff; preparing shows the size', (
      tester,
    ) async {
      final h = Harness(expanded: (_) => true);
      await tester.pumpWidget(
        h.widget(done('write', {'file_path': 'n.txt', 'content': 'a\nb\n'})),
      );
      expect(find.text('+ a'), findsOneWidget);
      expect(find.textContaining('+2', findRichText: true), findsOneWidget);
      await tester.pumpWidget(
        h.widget(
          preparing('write', '{"file_path":"n.txt","content":"${'x' * 2500}'),
        ),
      );
      expect(find.text('3KB'), findsWidgets);
    });

    testWidgets('an errored edit shows its first error line and no totals', (
      tester,
    ) async {
      final h = Harness();
      await tester.pumpWidget(
        h.widget(
          done(
            'edit',
            {'file_path': 'a', 'old_string': 'x', 'new_string': 'y'},
            error: true,
            text: 'old_string not found\nhint',
          ),
        ),
      );
      expect(find.text('old_string not found'), findsOneWidget);
      expect(find.textContaining('+1', findRichText: true), findsNothing);
    });

    testWidgets('read: line-numbered card with the window note', (
      tester,
    ) async {
      final h = Harness(cwd: '/w', expanded: (_) => true);
      await tester.pumpWidget(
        h.widget(
          done(
            'read',
            {'file_path': '/w/a.dart'},
            text: '<path>/w/a.dart</path>\n<type>file</type>\n<content>\n1: x\n</content>',
            meta: {
              'path': '/w/a.dart',
              'offset': 1,
              'totalLines': 9,
              'lang': 'dart',
              'lines': [
                {'number': 1, 'text': 'void main() {}'},
              ],
            },
          ),
        ),
      );
      expect(find.byKey(const ValueKey('read-block')), findsOneWidget);
      expect(
        find.text(t('read.window', {'shown': 1, 'total': 9})),
        findsOneWidget,
      );
    });

    testWidgets('read: a result that is not a card keeps its text', (
      tester,
    ) async {
      final h = Harness(expanded: (_) => true);
      await tester.pumpWidget(
        h.widget(done('read', {'file_path': '/w/a.dart'}, text: 'raw text')),
      );
      expect(find.text('raw text'), findsOneWidget);
    });

    testWidgets('grep and glob: summaries and result lists', (tester) async {
      final h = Harness(expanded: (_) => true);
      await tester.pumpWidget(
        h.widget(
          done(
            'grep',
            {'pattern': 'foo'},
            meta: {
              'shape': 'matches',
              'truncated': false,
              'total': 1,
              'files': [
                {
                  'path': 'a.dart',
                  'matches': [
                    {'lineNumber': 3, 'line': 'foo()'},
                  ],
                },
              ],
            },
          ),
        ),
      );
      expect(find.text(t('tool.title.grep')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-block')), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
      await tester.pumpWidget(
        h.widget(
          done(
            'glob',
            {'pattern': '*.md'},
            text: 'Full list at /tmp/q',
            meta: {
              'shape': 'paths',
              'truncated': true,
              'total': 40,
              'paths': ['README.md'],
            },
          ),
        ),
      );
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('Full list at /tmp/q'), findsOneWidget);
    });

    testWidgets('web_fetch links its URL; web_search lists sources', (
      tester,
    ) async {
      Uri? opened;
      final h = Harness(
        actions: ToolHostActions(openUrl: (u) => opened = u),
        expanded: (_) => true,
      );
      await tester.pumpWidget(
        h.widget(
          done(
            'web_fetch',
            {'url': 'https://a.example/p'},
            meta: {
              'truncated': false,
              'url': 'https://a.example/p',
              'statusCode': 200,
            },
          ),
        ),
      );
      expect(find.text(t('tool.title.webFetch')), findsOneWidget);
      expect(find.text('${t('web.http')} 200'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-link')));
      expect(opened?.host, 'a.example');
      await tester.pumpWidget(
        h.widget(
          done(
            'web_search',
            {
              'queries': ['dart'],
            },
            meta: {
              'truncated': false,
              'sources': [
                {'url': 'https://b.example', 'title': 'Source B'},
              ],
            },
          ),
        ),
      );
      expect(find.textContaining('Source B'), findsOneWidget);
    });

    testWidgets('todo_write: completion summary, change summary and the list', (
      tester,
    ) async {
      final h = Harness(expanded: (_) => true);
      final call = done('todo_write', {
        'todos': [
          {'content': 'Write notes', 'status': 'completed'},
          {'content': 'Review PRs', 'status': 'in_progress'},
          {'content': 'Tag', 'status': 'in_progress'},
        ],
      });
      // feed the todo history through the session's events
      final src = h.owner.session.eventSource;
      src.replace([
        EventEntry({
          'type': 'todo/write',
          'seq': 1,
          'time': 1,
          'data': {
            'todos': [
              {'content': 'Write notes', 'status': 'pending'},
            ],
          },
        }),
        EventEntry({
          'type': 'tool/call',
          'seq': 2,
          'time': 1,
          'data': {
            'turn': 1,
            'step': 1,
            'callId': 'c1',
            'name': 'todo_write',
            'arguments': '{}',
          },
        }),
      ], false);
      await tester.pumpWidget(h.widget(call));
      expect(
        find.textContaining(t('todo.completed', {'done': 1, 'total': 3})),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tool-details')), findsOneWidget);
      expect(find.text('Review PRs'), findsOneWidget);
    });

    testWidgets('ask_user_question: answered row with its transcript', (
      tester,
    ) async {
      final h = Harness(expanded: (_) => true);
      final args = {
        'questions': [
          {'id': 'q1', 'question': 'Pick a colour'},
        ],
      };
      await tester.pumpWidget(
        h.widget(
          done(
            'ask_user_question',
            args,
            text: jsonEncode({
              'answers': [
                {
                  'id': 'q1',
                  'selected': ['Red'],
                },
              ],
            }),
          ),
        ),
      );
      expect(find.text(t('ask.rowTitle')), findsOneWidget);
      expect(find.text('Pick a colour'), findsOneWidget);
      expect(find.text('Red'), findsOneWidget);
      await tester.pumpWidget(
        h.widget(
          done(
            'ask_user_question',
            args,
            error: true,
            text: '',
            errorBody: {'code': 'ASK_CANCELLED'},
          ),
        ),
      );
      expect(find.text(t('ask.cancelledDetail')), findsOneWidget);
    });

    testWidgets(
      'goal and schedule results render their fields; subagent offers its transcript',
      (tester) async {
        var opened = '';
        final h = Harness(
          expanded: (_) => true,
          actions: ToolHostActions(openSubagent: (parent, id) => opened = id),
        );
        await tester.pumpWidget(
          h.widget(
            done(
              'get_goal',
              {},
              text: jsonEncode({
                'goal': {
                  'id': 'g',
                  'objective': 'Ship the release',
                  'revision': 1,
                  'roundsStarted': 1,
                  'maxGoalRounds': 5,
                  'phase': 'paused',
                },
                'activation': 'armed',
              }),
            ),
          ),
        );
        expect(find.text('Ship the release'), findsWidgets);
        expect(find.text(t('detail.goal.paused')), findsOneWidget);
        await tester.pumpWidget(
          h.widget(
            done('subagent', {
              'prompt': 'go',
            }, text: 'started subagent child-7'),
          ),
        );
        await tester.tap(find.text(en.t('open-in-app', 'path.open')));
        expect(opened, 'child-7');
      },
    );

    testWidgets(
      'an unknown tool falls back to the generic row with input and output',
      (tester) async {
        final h = Harness(expanded: (_) => true);
        await tester.pumpWidget(
          h.widget(done('mystery', {'a': 1}, text: 'result text')),
        );
        expect(find.text(t('tool.title.generic')), findsOneWidget);
        expect(find.text('result text'), findsOneWidget);
        expect(find.byKey(const ValueKey('io-card')), findsOneWidget);
      },
    );

    testWidgets(
      'an interrupted call says stopped; an auto-review denial replaces the row body',
      (tester) async {
        final h = Harness(expanded: (_) => true);
        await tester.pumpWidget(
          h.widget(
            done(
              'bash',
              shellArgs('x'),
              error: true,
              text: '',
              errorBody: {'code': 'interrupted'},
            ),
          ),
        );
        expect(find.byKey(const ValueKey('tool-summary')), findsOneWidget);
        await tester.pumpWidget(
          h.widget(
            done(
              'bash',
              shellArgs('rm -rf x'),
              error: true,
              text: '',
              errorBody: {
                'name': 'AutoReviewDeniedError',
                'code': 'AUTO_REVIEW_DENIED',
                'reason': 'too risky',
              },
            ),
          ),
        );
        expect(find.text(t('tool.autoReviewRejected')), findsOneWidget);
        expect(
          find.text(t('tool.autoReviewNotExecuted', {'reason': 'too risky'})),
          findsOneWidget,
        );
      },
    );

    testWidgets('sub-calls nest under their parent through the same dispatch', (
      tester,
    ) async {
      final h = Harness(expanded: (_) => true);
      final child = done(
        'read',
        {'file_path': '/w/x'},
        id: 'child',
        parent: 'run',
      );
      final raw = jsonEncode({'code': 'x'});
      final parent = ToolResult(
        callId: 'run',
        name: 'run_code',
        args: PartialArguments.fromText(raw),
        subCalls: [child],
        seq: 9,
        time: 1,
        callArgsRaw: raw,
        content: [
          {'type': 'text', 'text': 'done'},
        ],
        isError: false,
      );
      await tester.pumpWidget(h.widget(parent));
      expect(find.byKey(const ValueKey('sub-calls')), findsOneWidget);
      expect(find.text(t('tool.title.read')), findsOneWidget);
      expect(find.text(t('tool.title.code')), findsOneWidget);
    });

    testWidgets('Chinese titles come from the catalog', (tester) async {
      final h = Harness(i18n: zh);
      await tester.pumpWidget(h.widget(done('bash', shellArgs('ls'))));
      expect(find.text('运行命令'), findsOneWidget);
    });
  });

  testWidgets(
    'a row stays open after it is scrolled out of the list and back',
    (tester) async {
      final h = Harness();
      final controller = ScrollController();
      Widget tall(ToolCall call) => dshTestApp(
        ListView(
          controller: controller,
          children: [
            h.slots.renderKeyed<ChatNodeOwner, Widget>(
              chatNodeSlot,
              'tool-call',
              ChatNodeOwner(
                session: h.owner,
                node: ViewNode(
                  key: 'k',
                  kind: 'tool-call',
                  id: call.callId,
                  target: 'chat',
                  anchorSeq: 1,
                  location: const SessionLocation(),
                  visible: true,
                  data: ToolData(call),
                ),
                snapshot: ChatSnapshot.empty,
              ),
            )!,
            const SizedBox(height: 4000),
          ],
        ),
      );
      await tester.pumpWidget(
        tall(done('bash', shellArgs('ls'), text: 'kept output')),
      );
      await tester.tap(find.text('Bash'));
      await tester.pump();
      expect(find.text('kept output'), findsOneWidget);
      controller.jumpTo(3500);
      await tester.pump();
      expect(find.text('Bash'), findsNothing);
      controller.jumpTo(0);
      await tester.pump();
      expect(find.text('kept output'), findsOneWidget);
    },
  );

  group('read_image', () {
    const envelope =
        '<path>/w/shot.png</path>\n<type>image</type>\n<content>\nimage 320x200\n</content>';
    Map<String, Object?> attachment({Object? original}) => {
      'attachmentId': 'sha256:abc',
      'mediaType': 'image/png',
      'bytes': 1658,
      'width': 320,
      'height': 200,
      'name': 'shot.png',
      'originalDimensions': ?original,
    };

    ToolResult image({
      List<Object?>? content,
      Object? meta = const {'path': '/w/shot.png'},
      bool error = false,
      String? parent,
    }) => done(
      'read_image',
      {'file_path': 'shot.png'},
      content:
          content ??
          [
            {'type': 'text', 'text': envelope},
            {'type': 'image', 'attachment': attachment()},
          ],
      meta: meta,
      error: error,
      parent: parent,
    );

    test('a settled result becomes the gallery material', () {
      final m = imageCardModel(image())!;
      expect(m.path, '/w/shot.png');
      expect(m.images.single.attachmentId, 'sha256:abc');
      expect(m.extraText, isNull);
      expect(m.originalSizes.single, isNull);
    });

    test('downscaled images keep their original size; extra text survives', () {
      final m = imageCardModel(
        image(
          content: [
            {'type': 'text', 'text': envelope},
            {
              'type': 'image',
              'attachment': attachment(
                original: {'width': 4000, 'height': 2500},
              ),
            },
            {'type': 'text', 'text': 'hook note'},
          ],
        ),
      )!;
      expect(m.originalSizes.single, (width: 4000, height: 2500));
      expect(m.extraText, 'hook note');
    });

    test('anything malformed declines to the generic card', () {
      expect(imageCardModel(image(error: true)), isNull);
      expect(imageCardModel(image(meta: null)), isNull);
      expect(imageCardModel(image(meta: {'path': ''})), isNull);
      // a nested call has no metadata and uses its own argument
      expect(imageCardModel(image(meta: null, parent: 'p')), isNotNull);
      expect(
        imageCardModel(
          image(
            content: [
              {'type': 'text', 'text': envelope},
            ],
          ),
        ),
        isNull,
      );
      expect(
        imageCardModel(
          image(
            content: [
              {'type': 'text', 'text': envelope},
              {
                'type': 'image',
                'attachment': {'attachmentId': 'x'},
              },
            ],
          ),
        ),
        isNull,
      );
      expect(
        imageCardModel(
          image(
            content: [
              {'type': 'text', 'text': 'no envelope'},
              {'type': 'image', 'attachment': attachment()},
            ],
          ),
        ),
        isNull,
      );
      expect(
        imageCardModel(
          image(
            content: [
              {'type': 'text', 'text': envelope},
              {'type': 'image', 'attachment': attachment()},
              {'type': 'reasoning', 'text': 'x'},
            ],
          ),
        ),
        isNull,
      );
    });

    testWidgets('the row expands to the gallery, path and size lines', (
      tester,
    ) async {
      final h = Harness(cwd: '/w');
      h.slots.register<ImageGalleryOwner, Widget>(
        DshSlots.toolCallImages.typed<ImageGalleryOwner, Widget>(),
        (o) => Text('gallery ${o.images.length}'),
      );
      await tester.pumpWidget(h.widget(image()));
      expect(find.text('gallery 1'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tool-row-read_image')));
      await tester.pump();
      expect(find.text('gallery 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('image-path')), findsOneWidget);
      expect(
        find.text(
          t('row.imageSize', {'width': 320, 'height': 200, 'bytes': 1658}),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed read shows the plain row', (tester) async {
      final h = Harness(cwd: '/w');
      await tester.pumpWidget(h.widget(image(error: true)));
      expect(find.byKey(const ValueKey('tool-row-read_image')), findsOneWidget);
    });
  });

  group('read highlighting', () {
    testWidgets('an ambient highlighter colours the read card by its language', (
      tester,
    ) async {
      final h = Harness(cwd: '/w');
      const envelope =
          '<path>/w/a.dart</path>\n<type>file</type>\n<content>\n1: var x\n</content>';
      final call = done(
        'read',
        {'file_path': '/w/a.dart'},
        text: envelope,
        meta: {
          'path': '/w/a.dart',
          'offset': 1,
          'totalLines': 1,
          'lang': 'dart',
          'lines': [
            {'number': 1, 'text': 'var x'},
          ],
        },
      );
      final highlighter = _StubHighlighter();
      await tester.pumpWidget(
        DshCodeHighlighting(highlighter: highlighter, child: h.widget(call)),
      );
      await tester.tap(find.byKey(const ValueKey('tool-row-read')));
      await tester.pump();
      expect(highlighter.requested, contains('dart'));
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((w) => w.text.toPlainText() == 'var x');
      expect(rich, isNotEmpty);
      final spans = <TextSpan>[];
      rich.first.text.visitChildren((s) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      expect(spans.map((s) => s.text), ['var', ' x']);
      expect(spans.first.style!.color, isNot(spans.last.style!.color));
    });
  });
}

class _StubHighlighter implements DshCodeHighlighter {
  final List<String?> requested = [];

  @override
  List<List<DshCodeSpan>>? highlight(String code, String? lang) => [
    for (final line in code.split('\n'))
      [
        const DshCodeSpan('var', DshCodeToken.keyword),
        DshCodeSpan(line.substring(3)),
      ],
  ];

  @override
  void prepare(String? lang) => requested.add(lang);

  @override
  Stream<void> get loaded => const Stream.empty();
}
