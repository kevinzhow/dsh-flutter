@Tags(['live'])
library;

// Live check of the phase 1b-1 surfaces against a real `dsh web` host started by
// `tool/live_spike/bin/live_tools.dart` (a separate instance on 127.0.0.1 sharing
// ~/.dsh, a scratch workspace, token in a mode-600 file that is never printed).
// It drives the real AppController + LiveBackend and asserts what the tool cards,
// the todo and plan projections and the subagent catalog derive from the host's
// own events. At most eight short prompts are sent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_subagent/dsh_feature_subagent.dart';
import 'package:dsh_feature_tool/dsh_feature_tool.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart'
    hide composerSlot;
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final launchFile = Platform.environment['DSH_LIVE_LAUNCH_FILE'];
final resultFile = Platform.environment['DSH_LIVE_RESULT'];

final results = <Map<String, Object?>>[];

/// `DSH_LIVE_STEPS=plan,todo` runs only those checks (default: all), so a
/// single check can be re-run with a couple of prompts.
final _only = Platform.environment['DSH_LIVE_STEPS']?.split(',');
bool want(String name) => _only == null || _only!.contains(name);

Future<T> step<T>(
  String name,
  Future<T> Function() body, {
  String Function(T)? detail,
  bool bestEffort = false,
}) async {
  final sw = Stopwatch()..start();
  try {
    final value = await body();
    results.add({
      'check': name,
      'state': 'pass',
      'ms': sw.elapsedMilliseconds,
      'detail': detail?.call(value) ?? '',
    });
    return value;
  } on Object catch (e) {
    results.add({
      'check': name,
      'state': bestEffort ? 'MISS' : 'FAIL',
      'ms': sw.elapsedMilliseconds,
      'detail': e.toString().split('\n').first,
    });
    if (!bestEffort) rethrow;
    return Future<T>.error(e);
  }
}

Future<void> until(
  String what,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 150),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

String Function(String, [Map<String, Object?>]) tr(DshI18n i18n) =>
    (key, [params = const {}]) => i18n.t('conversation', key, params: params);

void main() {
  test(
    'phase 1b-1 surfaces against a live dsh host',
    () async {
      final launch = File(launchFile!).readAsStringSync().trim();
      final controller = AppController(
        backend: LiveBackend(),
        locale: DshLocale.en,
      );
      final t = tr(controller.i18n);
      DshConnection? admin;
      try {
        await step('pair, create a session, open it', () async {
          expect(await controller.pair(launch), isTrue);
          await controller.manager!.refreshList();
          await controller.createSession();
          expect(controller.openSessionId, isNotNull);
          await controller.openSession!.open();
          return controller.openSessionId;
        }, detail: (_) => 'session opened');

        final sc = controller.openSession!;
        final session = sc.session;
        final chat = sc.conversation.chat;
        Iterable<ToolCall> roots(String name) => [
          for (final n in chat.value.visibleNodes)
            if (n.kind == 'tool-call' &&
                (n.data! as ToolData).root.name == name)
              (n.data! as ToolData).root,
        ];
        num lastSeq() => session.eventSource.window.entries
            .where((e) => !e.transient)
            .fold<num>(-1, (a, e) => e.seq > a ? e.seq : a);
        bool closedAfter(num seq) => session.eventSource.window.entries.any(
          (e) => !e.transient && e.type == 'turn/end' && e.seq > seq,
        );
        Future<void> ask(String prompt, {Duration? timeout}) async {
          final base = lastSeq();
          await sc.send(prompt);
          await until(
            'turn end',
            () => closedAfter(base),
            timeout: timeout ?? const Duration(seconds: 150),
          );
        }

        admin = DshConnection(
          origin: Uri.parse(launch).replace(path: '', query: ''),
          interactions: Interactions.none,
        );
        admin.start(Uri.parse(launch).queryParameters['token']!);
        await admin.untilConnected();
        Future<void> command(String line) =>
            admin!.caller.call('commands', 'execute', {
              'agentId': sc.sessionId,
              'line': line,
              'submittedAttachments': <Object?>[],
            });

        // ---- 1. bash: a terminal card ---------------------------------------
        if (want('bash')) {
          await step('bash: a clean command settles into a terminal card', () async {
            await ask(
              "Use the bash tool to run exactly: printf 'alpha\\nbeta\\n' . Then say what it printed in one short sentence.",
            );
            final call = roots('bash').last as ToolResult;
            final card = terminalCardModel(call, sessionCwd: sc.owner.cwd);
            expect(
              card,
              isNotNull,
              reason: 'bash result is not a terminal card',
            );
            expect(card!.output, contains('alpha'));
            expect(card.exitCode, 0);
            expect(toolRowModel('bash', call).state, ToolRowState.ok);
            return '${card.output!.trim().replaceAll('\n', ' | ')}, cwd label ${card.cwd}';
          }, detail: (d) => d);
        }

        // ---- 2. bash: a failing exit ----------------------------------------
        if (want('fail')) {
          await step('bash: a failing command carries its exit code', () async {
            await ask(
              'Use the bash tool to run exactly: ls /whalee-no-such-directory . It will fail; report the error in one sentence.',
            );
            final call = roots('bash').last as ToolResult;
            final card = terminalCardModel(call, sessionCwd: sc.owner.cwd)!;
            expect(card.failed, isTrue);
            expect(card.exitCode, isNot(0));
            expect(terminalExitLabel(card, t), isNotNull);
            return 'exit label "${terminalExitLabel(card, t)}"';
          }, detail: (d) => d);
        }

        // ---- 3. write: a diff card ------------------------------------------
        if (want('write')) {
          await step('write: a new file shows an all-added diff', () async {
            await command('/permission workspace-write');
            await until(
              'permissions projection',
              () =>
                  (session.projections.get('permissions')
                      as Map?)?['currentValue'] ==
                  'workspace-write',
              timeout: const Duration(seconds: 30),
            );
            await ask(
              'Use the write tool to create notes.txt in the working directory containing exactly three lines: red, green, blue. Then reply done.',
            );
            final call = roots('write').last as ToolResult;
            final diff = diffCardModel(call)!;
            final totals = diffTotals(diff);
            expect(totals.added, 3);
            expect(totals.removed, 0);
            return 'diff +${totals.added} -${totals.removed}, path ${diff.single.path}';
          }, detail: (d) => d);
        }

        // ---- 4. edit: a diff with context ----------------------------------
        if (want('edit')) {
          await step('edit: a replacement shows +1 -1 with context', () async {
            await ask(
              'Use the edit tool to replace the line "green" with "emerald" in notes.txt (read the file first if needed). Then reply done.',
            );
            final call = roots('edit').last as ToolResult;
            expect(call.isError, isFalse);
            final diff = diffCardModel(call)!;
            final totals = diffTotals(diff);
            expect(totals.added, 1);
            expect(totals.removed, 1);
            final rows = buildDiffRows(diff);
            expect(rows.any((r) => r.kind == DshDiffRowKind.context), isTrue);
            return 'diff +${totals.added} -${totals.removed}, ${rows.length} rows';
          }, detail: (d) => d);
        }

        // ---- 5. search: grep and glob cards --------------------------------
        if (want('grep')) {
          await step('grep: matches group by file', () async {
            await ask(
              'Use the grep tool to find the pattern "emerald" in the working directory, then tell me its line number.',
            );
            final call = roots('grep').last as ToolResult;
            final search = searchCardModel(call);
            expect(search, isNotNull, reason: 'grep metadata is not a card');
            expect(
              search!.files!.single.matches.single.line,
              contains('emerald'),
            );
            return '${search.total} match in ${search.files!.single.path}';
          }, detail: (d) => d);
        }

        if (want('glob')) {
          await step(
            'glob: a path list',
            () async {
              await ask(
                'Use the glob tool with the pattern "*.txt" and tell me how many files it found.',
              );
              final call = roots('glob').last as ToolResult;
              final search = searchCardModel(call);
              expect(search, isNotNull);
              expect(search!.paths, isNotEmpty);
              return '${search.paths!.length} path(s), truncated=${search.truncated}';
            },
            detail: (d) => d,
            bestEffort: true,
          ).catchError((Object _) => '');
        }

        // ---- 6. todo: the projection, the row and the history ---------------
        if (want('todo')) {
          await step('todo: the todos projection and the list diff', () async {
            await ask(
              'Use the todo_write tool once to record exactly three to-do items: "Collect notes" (completed), "Write summary" (in_progress), "Share it" (pending). Then reply done.',
            );
            final todos = session.projections.get('todos');
            expect(todos, isA<List<Object?>>());
            expect((todos! as List).length, 3);
            final call = roots('todo_write').last as ToolResult;
            final baseline = sc.conversation.todoHistory.value.get(call.callId);
            expect(baseline, isNotNull);
            final diff = todoDiffModel(
              call,
              baseline,
              session.snapshot.value.hasMore,
              t,
            );
            expect(diff, isNotNull);
            return 'projection has 3 items; list diff: ${diff!.details.caption}';
          }, detail: (d) => d);
        }

        // ---- 7. plan: plan mode, submitted plan ------------------------------
        if (want('plan')) {
          await step('plan: a submitted plan becomes turn data', () async {
            await command('/plan');
            await until(
              'plan projection',
              () =>
                  (session.projections.get('plan') as Map?)?['active'] == true,
              timeout: const Duration(seconds: 30),
            );
            final base = lastSeq();
            await sc.send(
              'Plan a two-step change that adds a README to this folder. Submit the plan with the exit_plan_mode tool; it must start with a "# " heading.',
            );
            await until(
              'a submitted plan',
              () => chat.value.nodes.values.any(
                (n) => n.kind == submittedPlanKind,
              ),
              timeout: const Duration(seconds: 150),
            );
            final plan =
                chat.value.nodes.values
                        .firstWhere((n) => n.kind == submittedPlanKind)
                        .data!
                    as SubmittedPlan;
            expect(plan.title, isNotEmpty);
            // The review waits on the user: approve it (the first option) so the
            // turn can end; a plan that is kept open would ask again.
            final deadline = DateTime.now().add(const Duration(seconds: 150));
            while (!closedAfter(base) && DateTime.now().isBefore(deadline)) {
              final q = controller.questions.forSession(sc.sessionId);
              if (q != null) {
                final first = q.questions.first;
                await q.submit([
                  QuestionAnswer(first.id, [
                    if (first.options.isNotEmpty) first.options.first.label,
                  ]),
                ]);
              }
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
            expect(closedAfter(base), isTrue, reason: 'the turn did not end');
            final turn = locationTurn(
              chat.value.nodes.values
                  .firstWhere((n) => n.kind == submittedPlanKind)
                  .location,
            )!;
            expect(chat.value.plansOfTurn(turn), isNotEmpty);
            await command('/plan off');
            return 'plan "${plan.title}" (${plan.markdown.length} chars) in turn $turn';
          }, detail: (d) => d);
        }

        // ---- 8. subagent: catalog and the child's own transcript ------------
        if (want('subagent')) {
          await step(
            'subagent: the child is listed and its transcript follows by address',
            () async {
              await ask(
                'Use the subagent tool in one-shot mode with the task "Reply with the single word ready". Then tell me what it replied.',
                timeout: const Duration(seconds: 200),
              );
              await until(
                'subagent catalog',
                () =>
                    catalogOf(session.projections.get('subagentCatalog'))
                        .isNotEmpty,
                timeout: const Duration(seconds: 60),
              );
              final entry = catalogOf(
                session.projections.get('subagentCatalog'),
              ).first;
              final child = controller.manager!.getSubagent(
                parentSessionId: sc.sessionId,
                childSessionId: entry.id,
                mode: entry.mode,
              );
              await child.open().timeout(const Duration(seconds: 60));
              expect(child.snapshot.value.openState, OpenState.open);
              final events = child.eventSource.window.entries
                  .where((e) => !e.transient)
                  .length;
              expect(events, greaterThan(0));
              return 'mode ${entry.mode}, $events events in the child transcript';
            },
            detail: (d) => d,
            bestEffort: true,
          ).catchError((Object _) => '');
        }
      } finally {
        await admin?.stop();
        controller.dispose();
        if (resultFile != null) {
          File(resultFile!).writeAsStringSync(
            const JsonEncoder.withIndent(' ').convert(results),
          );
        }
      }
    },
    skip: launchFile == null
        ? 'needs tool/live_spike/bin/live_tools.dart (a live host)'
        : null,
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
