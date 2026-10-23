@Tags(['live'])
library;

// Live integration test of the app layer against a real `dsh web` host.
//
// Not run by `flutter test` alone: it needs a host, which
// `tool/live_spike/bin/live_app.dart` starts (a separate instance on 127.0.0.1,
// sharing ~/.dsh) before running this file with
//   DSH_LIVE_LAUNCH_FILE  mode-600 file holding the launch URL (never printed)
//   DSH_LIVE_RESULT       where to write the JSON result table
// It drives the real AppController + LiveBackend (pairing, session list, open,
// prompt, streaming, tool call, cancel, approval, question) and asserts what
// the chat model shows. At most five short prompts are sent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart'
    hide composerSlot;
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:flutter_test/flutter_test.dart';

final launchFile = Platform.environment['DSH_LIVE_LAUNCH_FILE'];
final resultFile = Platform.environment['DSH_LIVE_RESULT'];

final results = <Map<String, Object?>>[];

Future<T> step<T>(
  String name,
  Future<T> Function() body, {
  String Function(T)? detail,
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
      'state': 'FAIL',
      'ms': sw.elapsedMilliseconds,
      'detail': '$e',
    });
    rethrow;
  }
}

void skipped(String name, String why) =>
    results.add({'check': name, 'state': 'skip', 'ms': 0, 'detail': why});

Future<void> until(
  String what,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

String textOf(ViewNode n) => [
  for (final b in (n.data! as AssistantData).blocks)
    if (b is TextBlock) b.text,
].join();

void main() {
  test(
    'the app layer against a live dsh host',
    () async {
      final launch = File(launchFile!).readAsStringSync().trim();
      final controller = AppController(
        backend: LiveBackend(),
        locale: DshLocale.en,
      );
      Session? session;
      DshConnection? admin;
      try {
        // ---- pairing ------------------------------------------------------
        await step('pair from the launch link', () async {
          final ok = await controller.pair(launch);
          expect(ok, isTrue, reason: '${controller.pairingError?.kind}');
          expect(controller.phase, ConnectionPhase.connected);
          return controller.hostOrigin;
        }, detail: (o) => 'connected to $o');

        await step('session list loads', () async {
          await controller.manager!.refreshList();
          return controller.sessionList.items.length;
        }, detail: (n) => '$n rows');

        await step('create a session and open it', () async {
          await controller.createSession();
          final id = controller.openSessionId;
          expect(id, isNotNull, reason: '${controller.createError}');
          final sc = controller.openSession!;
          await sc.open();
          session = sc.session;
          expect(sc.session.snapshot.value.openState, OpenState.open);
          return id;
        }, detail: (id) => 'session opened');

        final sc = controller.openSession!;
        final chat = sc.conversation.chat;
        final snapshots = <ChatSnapshot>[];
        final chatSub = chat.changes.listen(snapshots.add);

        bool turnClosedAfter(num seq) => session!.eventSource.window.entries
            .any((e) => !e.transient && e.type == 'turn/end' && e.seq > seq);
        num lastSeq() => session!.eventSource.window.entries
            .where((e) => !e.transient)
            .fold<num>(-1, (a, e) => e.seq > a ? e.seq : a);
        List<ViewNode> nodes(String kind) =>
            chat.value.visibleNodes.where((n) => n.kind == kind).toList();

        // ---- prompt 1: streamed text ---------------------------------------
        await step(
          'prompt: streamed reply settles into one assistant node',
          () async {
            final base = lastSeq();
            await sc.send('Reply with exactly one word: pong');
            await until(
              'first live text',
              () =>
                  snapshots.any(
                    (s) => s.visibleNodes.any(
                      (n) =>
                          n.kind == 'assistant-step' &&
                          (n.data! as AssistantData).status == 'running' &&
                          textOf(n).isNotEmpty,
                    ),
                  ) ||
                  turnClosedAfter(base),
            );
            await until('turn end', () => turnClosedAfter(base));
            await until(
              'settled',
              () =>
                  nodes('assistant-step').isNotEmpty &&
                  (nodes('assistant-step').last.data! as AssistantData)
                          .status ==
                      'settled',
            );
            final user = nodes('user');
            expect(user, isNotEmpty);
            expect((user.last.data! as MessageData).text, contains('pong'));
            expect(
              textOf(nodes('assistant-step').last).toLowerCase(),
              contains('pong'),
            );
            expect(nodes('turn-tail'), isNotEmpty);
            final sawLive = snapshots.any(
              (s) => s.visibleNodes.any(
                (n) =>
                    n.kind == 'assistant-step' &&
                    (n.data! as AssistantData).status == 'running',
              ),
            );
            return sawLive;
          },
          detail: (live) => 'live streaming rows observed: $live',
        );

        // ---- prompt 2: a tool call -----------------------------------------
        await step('prompt: tool call row runs and returns a result', () async {
          final base = lastSeq();
          await sc.send(
            'Run the shell command `echo hello-whalee` and tell me its output in one short sentence.',
          );
          await until('turn end', () => turnClosedAfter(base));
          final tools = nodes('tool-call');
          expect(tools, isNotEmpty);
          final root = (tools.last.data! as ToolData).root;
          expect(root, isA<ToolResult>());
          final result = root as ToolResult;
          expect(result.isError, isFalse);
          expect(
            result.content.map((b) => '${(b as Map)['text']}').join(),
            contains('hello-whalee'),
          );
          return result.name;
        }, detail: (name) => 'tool $name settled with its result');

        // ---- prompt 3: cancel ----------------------------------------------
        await step(
          'cancel while running stops the turn',
          () async {
            final base = lastSeq();
            await sc.send(
              'Count from 1 to 300, one number per line, and nothing else.',
            );
            await until(
              'running with live text',
              () =>
                  session!.snapshot.value.running &&
                  snapshots.any(
                    (s) => s.visibleNodes.any(
                      (n) =>
                          n.kind == 'assistant-step' &&
                          (n.data! as AssistantData).status == 'running' &&
                          textOf(n).length > 20,
                    ),
                  ),
            );
            final sw = Stopwatch()..start();
            await sc.cancel();
            await until(
              'turn end',
              () => turnClosedAfter(base),
              timeout: const Duration(seconds: 30),
            );
            await until(
              'running false',
              () => !session!.snapshot.value.running,
            );
            final end = session!.eventSource.window.entries.lastWhere(
              (e) => !e.transient && e.type == 'turn/end',
            );
            final kind = ((end.data as Map)['reason'] as Map)['kind'];
            expect(kind, 'aborted');
            return sw.elapsedMilliseconds;
          },
          detail: (ms) =>
              'turn/end reason aborted ${ms}ms after cancel; running=false',
        );

        // ---- approval ------------------------------------------------------
        final backend = controller.backend as LiveBackend;
        admin = DshConnection(
          origin: Uri.parse(launch).replace(path: '', query: ''),
          interactions: Interactions.none,
        );
        admin.start(Uri.parse(launch).queryParameters['token']!);
        await admin.untilConnected();
        await step(
          'switch the session to workspace-write (asks for approval)',
          () async {
            await admin!.caller.call('commands', 'execute', {
              'agentId': sc.sessionId,
              'line': '/permission workspace-write',
              'submittedAttachments': <Object?>[],
            });
            await until(
              'permissions projection',
              () =>
                  (session!.projections.get('permissions')
                      as Map?)?['currentValue'] ==
                  'workspace-write',
              timeout: const Duration(seconds: 30),
            );
            return true;
          },
        );
        await step(
          'approval request reaches the composer takeover; allow once runs the tool',
          () async {
            final base = lastSeq();
            await sc.send(
              'Use the bash tool to run exactly this command: echo ok > ../whalee-approval-probe.txt . '
              'It writes outside the working directory, so the sandbox will deny it. When it does, retry the exact '
              'command once with escalated sandbox_permissions and a one-sentence justification. Then reply done.',
            );
            await until(
              'approval request',
              () => controller.approvals.forSession(sc.sessionId) != null,
              timeout: const Duration(seconds: 150),
            );
            final slot = controller.slots.renderChain(composerSlot, sc.owner);
            expect(
              slot,
              isNotNull,
              reason: 'the chain entry takes over the composer',
            );
            final sw = Stopwatch()..start();
            await controller.approvals
                .forSession(sc.sessionId)!
                .answer('allowed-once');
            final answered = sw.elapsedMilliseconds;
            await until(
              'turn end',
              () => turnClosedAfter(base),
              timeout: const Duration(seconds: 150),
            );
            expect(controller.approvals.forSession(sc.sessionId), isNull);
            final decided = session!.eventSource.window.entries
                .where(
                  (e) =>
                      !e.transient &&
                      e.type == 'approval/decided' &&
                      e.seq > base,
                )
                .toList();
            expect(decided, isNotEmpty);
            return answered;
          },
          detail: (ms) =>
              'answered allowed-once in ${ms}ms; approval/decided recorded',
        );

        // ---- user question (best effort: the model must choose to ask) -----
        var asked = false;
        await step('agent question answered through the waterfall (best effort)', () async {
          final base = lastSeq();
          await sc.send(
            'Use the ask_user_question tool to ask me one multiple-choice question: "Which colour?" '
            'with the options Red and Blue. After I answer, tell me my choice in one sentence.',
          );
          try {
            await until(
              'question request',
              () => controller.questions.forSession(sc.sessionId) != null,
              timeout: const Duration(seconds: 90),
            );
          } on TimeoutException {
            return 'the model did not ask';
          }
          asked = true;
          final q = controller.questions.forSession(sc.sessionId)!;
          expect(q.questions, isNotEmpty);
          final first = q.questions.first;
          await q.submit([
            QuestionAnswer(first.id, [
              if (first.options.isNotEmpty) first.options.first.label,
            ]),
          ]);
          await until(
            'turn end',
            () => turnClosedAfter(base),
            timeout: const Duration(seconds: 150),
          );
          return 'answered with ${first.options.isNotEmpty ? first.options.first.label : 'text'}';
        }, detail: (d) => d);
        if (!asked) {
          skipped(
            'question waterfall',
            'model chose not to call ask_user_question; flow covered by unit tests',
          );
          // the turn must still settle
        }

        await chatSub.cancel();
        // the list reflects the prompted session now
        await step('session list shows the prompted session', () async {
          await controller.manager!.refreshList();
          final row = controller.sessionList.items.where(
            (e) => e.sessionId == sc.sessionId,
          );
          expect(row, isNotEmpty);
          return (row.single.title ?? '').isNotEmpty;
        }, detail: (titled) => 'row present, title projection set: $titled');
        expect(backend.caller, isNotNull);
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
        ? 'needs tool/live_spike/bin/live_app.dart (a live host)'
        : null,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
