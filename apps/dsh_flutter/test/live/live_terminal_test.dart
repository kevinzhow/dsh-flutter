@Tags(['live'])
library;

// Live check of the sidebar terminal against a real `dsh web` host that the
// caller started on 127.0.0.1 with its own DSH_HOME (never Kevin's instance):
//   DSH_LIVE_LAUNCH_FILE  mode-600 file holding the launch URL (never printed)
//   DSH_LIVE_RESULT       where to write the JSON result table
//   DSH_LIVE_WORKSPACE    the scratch workspace the host runs in
// It drives the real AppController + LiveBackend + ClientTerminals: a shell is
// created, takes input and a resize, survives a dropped connection and a screen
// that closes and opens again, hands control to a second view and takes it back,
// exits with its code, and is closed. The shell only runs echo, printf, pwd, ls
// and stty in the scratch workspace. No model is involved.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/generated_terminal.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:flutter_test/flutter_test.dart';

final launchFile = Platform.environment['DSH_LIVE_LAUNCH_FILE'];
final resultFile = Platform.environment['DSH_LIVE_RESULT'];
final workspace = Platform.environment['DSH_LIVE_WORKSPACE'];

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

Future<void> until(
  String what,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// What the Host drew, as a screen emulator would receive it.
class Screen {
  Screen(this.view) {
    sub = view.state.changes.listen((s) {
      final r = s.render;
      if (r == null || r.revision <= _last) return;
      _last = r.revision;
      final f = r.frame;
      if (f is TerminalFrameSnapshot) {
        snapshots++;
        text = f.screen;
        lastSnapshot = f.screen;
      } else if (f is TerminalFrameOutput) {
        text += f.data;
      }
      view.acknowledge(r.revision);
    });
  }

  final TerminalView view;
  late final StreamSubscription<TerminalViewState> sub;
  int _last = 0;
  int snapshots = 0;
  String text = '';
  String lastSnapshot = '';

  Future<void> sees(String needle) =>
      until('"$needle" on screen', () => text.contains(needle));
}

void main() {
  test(
    'the sidebar terminal against a live dsh host',
    () async {
      final launch = File(launchFile!).readAsStringSync().trim();
      final controller = AppController(
        backend: LiveBackend(),
        locale: DshLocale.en,
      );
      final ws = workspace!;
      try {
        await step('pair from the launch link', () async {
          expect(await controller.pair(launch), isTrue);
          return controller.hostOrigin;
        }, detail: (o) => 'connected to $o');
        await step('create a session in the scratch workspace', () async {
          await controller.createSession();
          final sc = controller.openSession!;
          await sc.open();
          await until('cwd', () => sc.owner.cwd != null);
          expect(sc.owner.cwd, ws);
          return sc.sessionId;
        }, detail: (_) => 'session opened');
        final sessionId = controller.openSession!.sessionId;
        final terminals = controller.terminals;

        final shells = await step('the host lists installed shells', () async {
          final l = await terminals.launchShells(sessionId);
          expect(l.shells, isNotEmpty);
          expect(l.selectedShell, isNotNull);
          return l;
        }, detail: (l) => l.shells.map((s) => s.name).join(', '));
        expect(
          await controller.backend.terminalHost.remote.list(sessionId),
          isEmpty,
        );

        // ---- a terminal -----------------------------------------------------
        final view = terminals.view(sessionId, 'tab-1');
        final screen = Screen(view);
        final detach = view.mount();
        await step(
          'the shell starts and the screen attaches',
          () async {
            await until(
              'connected',
              () => view.snapshot.phase == TerminalPhase.connected,
            );
            expect(view.snapshot.writable, isTrue);
            expect(view.snapshot.environment!.maxCols, greaterThan(0));
            expect(view.snapshot.info!.shell.path, shells.shells.first.path);
            expect(view.snapshot.info!.cwd, ws);
            return view.snapshot.info!;
          },
          detail: (i) =>
              '${i.shell.name} in the workspace, ${i.cols}x${i.rows}',
        );

        await step('typed input runs and its output comes back', () async {
          view.write("printf 'whalee-%s\\n' ready\r");
          await screen.sees('whalee-ready');
          view.write('pwd\r');
          await screen.sees(ws);
          view.write('echo \$TERM\r');
          await screen.sees('xterm-256color');
        }, detail: (_) => 'printf, pwd and echo \$TERM answered');

        await step(
          'there is no approval gate on a user terminal',
          () async {
            view.write("printf 'from the terminal' > terminal-wrote.txt\r");
            view.write('ls\r');
            await screen.sees('terminal-wrote.txt');
            expect(controller.approvals.pending.value, isEmpty);
            expect(
              File('$ws/terminal-wrote.txt').readAsStringSync(),
              'from the terminal',
            );
          },
          detail: (_) =>
              'wrote a file in the scratch workspace, no approval asked',
        );

        await step('a resize reaches the Host grid', () async {
          view.resize(100, 30);
          await until(
            'host grid',
            () =>
                view.snapshot.info!.cols == 100 &&
                view.snapshot.info!.rows == 30,
          );
          view.write('stty size\r');
          await screen.sees('30 100');
        }, detail: (_) => 'stty size reports 30 100');

        await step('control characters travel unchanged', () async {
          view.write('cat\r');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          view.write('typed into cat\r');
          await screen.sees('typed into cat');
          view.write('\x04'); // Ctrl-D ends cat
          view.write('echo after-cat-\$((2+3))\r');
          await screen.sees('after-cat-5');
        }, detail: (_) => 'cat read a line and ended on Ctrl-D');

        await step(
          'a screen that closes and opens again keeps the process',
          () async {
            detach();
            final before = screen.snapshots;
            view.mount();
            await until('re-attached', () => screen.snapshots > before);
            expect(screen.lastSnapshot, contains('whalee-ready'));
            expect(screen.lastSnapshot, contains('after-cat-5'));
            view.write('echo alive-\$((6*7))\r');
            await screen.sees('alive-42');
          },
          detail: (_) => 'the snapshot restored the earlier output',
        );

        await step(
          'a dropped connection is resumed from the screen',
          () async {
            final before = screen.snapshots;
            await (controller.backend as LiveBackend)
                .dropConnectionForTesting();
            await until(
              'disconnected',
              () =>
                  view.snapshot.phase == TerminalPhase.disconnected ||
                  view.snapshot.phase == TerminalPhase.connecting,
            );
            view.write('typed while down\r'); // dropped, never replayed
            await until(
              'resumed',
              () =>
                  screen.snapshots > before &&
                  view.snapshot.phase == TerminalPhase.connected &&
                  view.snapshot.writable,
              timeout: const Duration(seconds: 60),
            );
            expect(screen.lastSnapshot, contains('alive-42'));
            expect(screen.lastSnapshot, isNot(contains('typed while down')));
            view.write('echo resumed-\$((8+1))\r');
            await screen.sees('resumed-9');
          },
          detail: (_) => 'new snapshot after reconnect; input sent while down was not replayed',
        );

        await step(
          'a second view takes control and the first can take it back',
          () async {
            final second = terminals.view(
              sessionId,
              'tab-2',
              terminalId: view.id,
            );
            final screen2 = Screen(second);
            second.mount();
            await until('second attached', () => second.snapshot.writable);
            await until('first read-only', () => !view.snapshot.writable);
            expect(view.snapshot.phase, TerminalPhase.connected);
            view.write('refused\r'); // read-only: dropped
            second.write('echo from-second-\$((1+1))\r');
            await screen2.sees('from-second-2');
            view.connect();
            await until('first writable again', () => view.snapshot.writable);
            await until('second read-only', () => !second.snapshot.writable);
            view.write('echo from-first-\$((3+4))\r');
            await screen.sees('from-first-7');
            expect(screen.text, isNot(contains('refused')));
            await screen2.sub.cancel();
          },
          detail: (_) => 'only the latest attachment writes',
        );

        await step('rename shows on every view', () async {
          await view.rename('build');
          expect(view.snapshot.title, 'build');
          final listed = await controller.backend.terminalHost.remote.list(
            sessionId,
          );
          expect(listed.single.title, 'build');
        }, detail: (_) => 'host list shows the new title');

        await step('the shell exits with its code and stays visible', () async {
          view.write('exit 7\r');
          await until(
            'exited',
            () => view.snapshot.info?.state == WebTerminalInfoState.exited,
          );
          expect(view.snapshot.info!.exitCode, 7);
          expect(view.snapshot.writable, isFalse);
          view.write('echo nope\r');
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(screen.text, isNot(contains('nope')));
          expect(view.snapshot.phase, TerminalPhase.connected);
        }, detail: (_) => 'exit code 7, input off, screen kept');

        await step('closing the tab ends the Host terminal', () async {
          terminals.close(sessionId, 'tab-1');
          await Future<void>.delayed(const Duration(seconds: 1));
          final listed = await controller.backend.terminalHost.remote.list(
            sessionId,
          );
          expect(listed.where((i) => i.id == view.id), isEmpty);
          expect(controller.terminals.closeFailures.value, isEmpty);
        }, detail: (_) => 'terminal/list no longer has it');

        await step(
          'a new terminal after an exit works, and the limit is explicit',
          () async {
            final created = <TerminalView>[];
            for (var i = 0; i < 8; i++) {
              final v = terminals.view(sessionId, 'n$i')..mount();
              created.add(v);
              await until(
                'n$i connected',
                () => v.snapshot.phase == TerminalPhase.connected,
              );
            }
            final extra = terminals.view(sessionId, 'n8')..mount();
            await until(
              'limit',
              () => extra.snapshot.phase == TerminalPhase.failed,
            );
            expect(extra.snapshot.issue, TerminalViewIssue.terminalLimit);
            for (var i = 0; i < 8; i++) {
              terminals.close(sessionId, 'n$i');
            }
            terminals.close(sessionId, 'n8');
            await Future<void>.delayed(const Duration(seconds: 2));
            expect(
              await controller.backend.terminalHost.remote.list(sessionId),
              isEmpty,
            );
          },
          detail: (_) => '8 shells opened, the 9th refused with terminal/limit-reached, all closed',
        );
      } finally {
        if (resultFile != null) {
          File(resultFile!).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
          );
        }
        controller.dispose();
      }
    },
    skip: launchFile == null
        ? 'needs a live host (see the header of this file)'
        : null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
