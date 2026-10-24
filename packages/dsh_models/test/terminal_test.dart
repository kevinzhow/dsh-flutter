import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_terminal.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Acknowledge every screen write the way a synchronous emulator does.
StreamSubscription<TerminalViewState> autoRender(
  TerminalView view,
  List<TerminalFrame> written,
) {
  var last = 0;
  return view.state.changes.listen((s) {
    final r = s.render;
    if (r != null && r.revision > last) {
      last = r.revision;
      written.add(r.frame);
      view.acknowledge(r.revision);
    }
  });
}

void main() {
  late FakeTerminalHost fake;
  late MemoryTerminalPrefs prefs;
  late ClientTerminals terminals;
  late List<TerminalFrame> written;
  late TerminalView view;

  Future<void> start({
    Map<String, Object?>? snapshot,
    bool mount = true,
    String? shellPath,
  }) async {
    view = terminals.view('s1', 'tab1', shellPath: shellPath);
    autoRender(view, written);
    if (mount) view.mount();
    await settle();
    fake.attach.start(
      1,
      snapshot ?? terminalSnapshot(info: terminalInfo(id: view.id)),
    );
    await settle();
  }

  setUp(() {
    fake = FakeTerminalHost();
    fake.host.generation = FakeGeneration();
    prefs = MemoryTerminalPrefs();
    terminals = ClientTerminals(
      host: fake.terminalHost,
      prefs: prefs,
      newId: () => 'term-1',
    );
    written = [];
  });

  tearDown(() async {
    await terminals.dispose();
    await fake.close();
  });

  group('starting a terminal', () {
    test(
      'reads the limits, creates the shell, holds it and follows its screen',
      () async {
        await start(
          snapshot: terminalSnapshot(
            screen: 'hello',
            info: terminalInfo(id: 'term-1'),
          ),
        );
        expect(fake.host.callsTo('terminal/environment').single.args, {
          'agentId': 's1',
        });
        final create = fake.host.callsTo('terminal/create').single.args;
        expect(create['agentId'], 's1');
        final request = create['request']! as Map<String, Object?>;
        expect(request, {
          'id': 'term-1',
          'shellPath': '/bin/bash',
          'cols': 80,
          'rows': 24,
        });
        expect(fake.retains.single.terminalId, 'term-1');
        expect(fake.attaches.single.terminalId, 'term-1');
        final s = view.snapshot;
        expect(s.phase, TerminalPhase.connected);
        expect(s.writable, isTrue);
        expect(s.title, 'bash');
        expect(written.single, isA<TerminalFrameSnapshot>());
        expect((written.single as TerminalFrameSnapshot).screen, 'hello');
      },
    );

    test(
      'does not attach before the hold of the generation is acknowledged',
      () async {
        fake = FakeTerminalHost(autoAck: false);
        fake.host.generation = FakeGeneration();
        terminals = ClientTerminals(
          host: fake.terminalHost,
          prefs: prefs,
          newId: () => 'term-1',
        );
        view = terminals.view('s1', 'tab1')..mount();
        await settle();
        expect(fake.retains, hasLength(1));
        expect(fake.attaches, isEmpty);
        fake.retain
          ..open(1)
          ..ack(1);
        await settle();
        expect(fake.attaches, hasLength(1));
      },
    );

    test(
      'remembers the shell, and a guide choice wins over the remembered one',
      () async {
        await start(shellPath: '/usr/bin/zsh');
        expect(prefs.preferredShell, '/usr/bin/zsh');
        final request =
            fake.host.callsTo('terminal/create').single.args['request']!
                as Map<String, Object?>;
        expect(request['shellPath'], '/usr/bin/zsh');
        final launch = await terminals.launchShells('s1');
        expect(launch.shells.map((s) => s.name), ['bash', 'zsh']);
        expect(launch.selectedShell, '/usr/bin/zsh');
      },
    );

    test(
      'falls back to the first shell when the remembered one is gone',
      () async {
        prefs.rememberShell('/bin/fish');
        final launch = await terminals.launchShells('s1');
        expect(launch.selectedShell, '/bin/bash');
        await start();
        final request =
            fake.host.callsTo('terminal/create').single.args['request']!
                as Map<String, Object?>;
        expect(request['shellPath'], '/bin/bash');
      },
    );

    test('the session limit shows as its own issue', () async {
      fake.host.handlers['terminal/create'] = (_) => throw RemoteException(
        'terminal/limit-reached',
        'limit',
        {'limit': 8},
      );
      view = terminals.view('s1', 'tab1')..mount();
      await settle();
      expect(view.snapshot.phase, TerminalPhase.failed);
      expect(view.snapshot.issue, TerminalViewIssue.terminalLimit);
      expect(fake.attaches, isEmpty);
    });

    test('a missing Host terminal is reported, not replaced', () async {
      view = terminals.view('s1', 'tab1', terminalId: 'gone')..mount();
      await settle();
      expect(view.snapshot.phase, TerminalPhase.failed);
      expect(view.snapshot.issue, TerminalViewIssue.missingTerminal);
      expect(fake.host.callsTo('terminal/create'), isEmpty);
    });

    test('a listed Host terminal is reattached without creating', () async {
      fake.host.handlers['terminal/list'] = (_) => [
        terminalInfo(id: 'old', title: 'work'),
      ];
      view = terminals.view('s1', 'tab1', terminalId: 'old')..mount();
      autoRender(view, written);
      await settle();
      expect(fake.host.callsTo('terminal/create'), isEmpty);
      expect(view.snapshot.title, 'work');
      fake.attach.start(
        1,
        terminalSnapshot(
          info: terminalInfo(id: 'old', title: 'work'),
        ),
      );
      await settle();
      expect(view.snapshot.phase, TerminalPhase.connected);
    });
  });

  group('screen frames', () {
    test('output is delivered in order, one write at a time', () async {
      view = terminals.view('s1', 'tab1');
      final seen = <String>[];
      view.state.changes.listen((s) {
        final r = s.render;
        if (r == null) return;
        final f = r.frame;
        seen.add(f is TerminalFrameOutput ? f.data : 'snapshot');
        // Acknowledge later: nothing else is published until then.
        Timer(Duration.zero, () => view.acknowledge(r.revision));
      });
      view.mount();
      await settle();
      fake.attach
        ..start(1, terminalSnapshot(info: terminalInfo(id: 'term-1')))
        ..emit(1, terminalOutput(1, 'a'))
        ..emit(1, terminalOutput(2, 'b'));
      await settle();
      expect(seen, ['snapshot', 'a', 'b']);
    });

    test('a sequence gap fails the view and detaches', () async {
      await start();
      fake.attach
        ..emit(1, terminalOutput(1, 'a'))
        ..emit(1, terminalOutput(3, 'c'));
      await settle();
      expect(view.snapshot.phase, TerminalPhase.failed);
      expect(view.snapshot.issue, TerminalViewIssue.invalidOutput);
      expect(view.snapshot.writable, isFalse);
      expect(fake.attach.frames.hasListener, isFalse);
    });

    test('output before the snapshot is invalid', () async {
      view = terminals.view('s1', 'tab1')..mount();
      await settle();
      fake.attach
        ..open(1)
        ..emit(1, terminalOutput(1, 'a'));
      await settle();
      expect(view.snapshot.issue, TerminalViewIssue.invalidOutput);
    });

    test('a second snapshot in one generation is invalid', () async {
      await start();
      fake.attach.emit(1, terminalSnapshot(info: terminalInfo(id: 'term-1')));
      await settle();
      expect(view.snapshot.issue, TerminalViewIssue.invalidOutput);
    });

    test('a frame that is not a terminal frame is invalid', () async {
      await start();
      fake.attach.emit(1, {'type': 'output', 'sequence': 'x'});
      await settle();
      expect(view.snapshot.issue, TerminalViewIssue.invalidOutput);
    });

    test('a state frame updates the title without a screen write', () async {
      await start();
      final before = written.length;
      fake.attach.emit(
        1,
        terminalState(terminalInfo(id: 'term-1', title: 'build')),
      );
      await settle();
      expect(view.snapshot.title, 'build');
      expect(written.length, before);
    });
  });

  group('input', () {
    test('writes are numbered from one and acknowledged in order', () async {
      await start();
      view
        ..write('l')
        ..write('s\r');
      expect(fake.attach.sent.map((c) => c.toJson()), [
        {'type': 'write', 'sequence': 1, 'data': 'l'},
        {'type': 'write', 'sequence': 2, 'data': 's\r'},
      ]);
      fake.attach
        ..emit(1, terminalAck(1))
        ..emit(1, terminalAck(2));
      await settle();
      expect(view.snapshot.phase, TerminalPhase.connected);
      expect(view.snapshot.writable, isTrue);
    });

    test(
      'resize is ordered with input and skipped when the size is unchanged',
      () async {
        await start();
        view
          ..write('a')
          ..resize(80, 24) // same as the Host's: nothing to send
          ..resize(100, 30)
          ..write('b');
        expect(fake.attach.sent.map((c) => c.toJson()), [
          {'type': 'write', 'sequence': 1, 'data': 'a'},
          {'type': 'resize', 'sequence': 2, 'cols': 100, 'rows': 30},
          {'type': 'write', 'sequence': 3, 'data': 'b'},
        ]);
      },
    );

    test('resize is clamped to the Host limits', () async {
      fake.host.handlers['terminal/environment'] = (_) =>
          terminalEnvironment(maxCols: 120, maxRows: 40);
      await start();
      view.resize(300, 100);
      final resize = fake.attach.sentOf<TerminalInputResize>().single;
      expect((resize.cols, resize.rows), (120, 40));
    });

    test('a read-only view sends nothing', () async {
      await start(
        snapshot: terminalSnapshot(
          writable: false,
          info: terminalInfo(id: 'term-1'),
        ),
      );
      expect(view.snapshot.writable, isFalse);
      view
        ..write('x')
        ..resize(100, 30);
      expect(fake.attach.sent, isEmpty);
    });

    test(
      'commands wait for the carrier window and resume on acknowledgement',
      () async {
        // Room for one small command in flight at a time.
        await start(
          snapshot: terminalSnapshot(
            info: terminalInfo(id: 'term-1'),
            inputWindow: {'maxBytes': 80, 'frameOverheadBytes': 20},
          ),
        );
        view
          ..write('a')
          ..write('b')
          ..write('c');
        expect(fake.attach.sent.map((c) => (c as TerminalInputWrite).data), [
          'a',
        ]);
        fake.attach.emit(1, terminalAck(1));
        await settle();
        expect(fake.attach.sent.map((c) => (c as TerminalInputWrite).data), [
          'a',
          'b',
        ]);
        fake.attach
          ..emit(1, terminalAck(2))
          ..emit(1, terminalAck(3));
        await settle();
        expect(fake.attach.sent.map((c) => (c as TerminalInputWrite).data), [
          'a',
          'b',
          'c',
        ]);
      },
    );

    test('input over the raw byte budget ends the attachment', () async {
      fake.host.handlers['terminal/environment'] = (_) =>
          terminalEnvironment(maxInputBytes: 4);
      await start();
      view.write('12345');
      expect(view.snapshot.issue, TerminalViewIssue.inputFull);
      expect(view.snapshot.phase, TerminalPhase.failed);
      expect(fake.attach.sent, isEmpty);
    });

    test(
      'a frame larger than the carrier window ends the attachment',
      () async {
        await start(
          snapshot: terminalSnapshot(
            info: terminalInfo(id: 'term-1'),
            inputWindow: {'maxBytes': 30, 'frameOverheadBytes': 20},
          ),
        );
        view.write('this is longer than the window');
        expect(view.snapshot.issue, TerminalViewIssue.inputFull);
      },
    );

    test('multi-byte input is counted in UTF-8 bytes', () async {
      fake.host.handlers['terminal/environment'] = (_) =>
          terminalEnvironment(maxInputBytes: 5);
      await start();
      view.write('你好'); // 6 bytes
      expect(view.snapshot.issue, TerminalViewIssue.inputFull);
    });

    test('a refusal acknowledgement turns the view read-only', () async {
      await start();
      view.write('x');
      fake.attach.emit(1, terminalAck(1, refusal: 'read-only'));
      await settle();
      expect(view.snapshot.writable, isFalse);
      expect(view.snapshot.phase, TerminalPhase.connected);
    });

    test('an acknowledgement for a command never sent is invalid', () async {
      await start();
      fake.attach.emit(1, terminalAck(1));
      await settle();
      expect(view.snapshot.issue, TerminalViewIssue.invalidOutput);
    });

    test('a send that fails ends the attachment', () async {
      await start();
      fake.attach.sendFailure = StateError('boom');
      view.write('x');
      expect(view.snapshot.phase, TerminalPhase.failed);
      expect(view.snapshot.writable, isFalse);
    });

    test('taking control reattaches and starts numbering again', () async {
      await start(
        snapshot: terminalSnapshot(
          writable: false,
          info: terminalInfo(id: 'term-1'),
        ),
      );
      view.connect();
      await settle();
      expect(fake.attaches, hasLength(2));
      expect(fake.attaches.first.frames.hasListener, isFalse);
      fake.attach.start(1, terminalSnapshot(info: terminalInfo(id: 'term-1')));
      await settle();
      expect(view.snapshot.writable, isTrue);
      view.write('x');
      expect((fake.attach.sent.single as TerminalInputWrite).sequence, 1);
    });
  });

  group('reconnecting', () {
    test('a lost connection keeps the screen, drops input, and resumes on the next generation', () async {
      await start();
      view.write('a');
      expect(fake.attach.sent, hasLength(1));
      final first = fake.attach;
      fake.reconnect(); // ends the attachment, publishes generation 2 and re-acks the hold
      await settle();
      // The new attachment is opened by the view, not replayed by the transport.
      expect(fake.attaches, hasLength(2));
      expect(first.frames.hasListener, isFalse);
      expect(view.snapshot.phase, TerminalPhase.connecting);
      expect(view.snapshot.writable, isFalse);
      view.write('lost while reconnecting');
      expect(fake.attach.sent, isEmpty);
      fake.attach.start(
        2,
        terminalSnapshot(
          sequence: 40,
          screen: 'prompt\$ ',
          info: terminalInfo(id: 'term-1'),
        ),
      );
      await settle();
      expect(view.snapshot.phase, TerminalPhase.connected);
      expect(view.snapshot.writable, isTrue);
      expect((written.last as TerminalFrameSnapshot).screen, 'prompt\$ ');
      // Numbering restarts; the output sequence continues from the snapshot.
      view.write('b');
      expect(fake.attach.sent.single.toJson(), {
        'type': 'write',
        'sequence': 1,
        'data': 'b',
      });
      fake.attach.emit(2, terminalOutput(41, 'x'));
      await settle();
      expect((written.last as TerminalFrameOutput).data, 'x');
    });

    test('shows the disconnected state until the new generation holds the terminal', () async {
      fake = FakeTerminalHost(autoAck: false);
      fake.host.generation = FakeGeneration();
      terminals = ClientTerminals(
        host: fake.terminalHost,
        prefs: prefs,
        newId: () => 'term-1',
      );
      view = terminals.view('s1', 'tab1');
      autoRender(view, written);
      view.mount();
      await settle();
      fake.retain
        ..open(1)
        ..ack(1);
      await settle();
      fake.attach.start(1, terminalSnapshot(info: terminalInfo(id: 'term-1')));
      await settle();
      fake.reconnect();
      await settle();
      expect(view.snapshot.phase, TerminalPhase.disconnected);
      expect(fake.attaches, hasLength(1));
      fake.retain
        ..open(2)
        ..ack(2);
      await settle();
      expect(fake.attaches, hasLength(2));
    });

    test('reconnect on request opens a fresh attachment', () async {
      await start();
      fake.attach.end(1, CarrierLost());
      await settle();
      expect(view.snapshot.phase, TerminalPhase.disconnected);
      view.connect();
      await settle();
      expect(fake.attaches, hasLength(2));
      expect(view.snapshot.phase, TerminalPhase.connecting);
    });

    test(
      'a screen that closes and opens again reattaches to the same process',
      () async {
        await start();
        final detach = view.mount();
        detach();
        expect(fake.attach.frames.hasListener, isFalse);
        expect(fake.host.callsTo('terminal/close'), isEmpty);
        view.mount();
        await settle();
        expect(fake.attaches.length, greaterThanOrEqualTo(2));
        expect(fake.host.callsTo('terminal/create'), hasLength(1));
      },
    );
  });

  group('the process ends', () {
    test('an exit state frame ends input and keeps the screen', () async {
      await start();
      fake.attach.emit(
        1,
        terminalState(
          terminalInfo(id: 'term-1', state: 'exited', exitCode: 3),
          writable: true,
        ),
      );
      await settle();
      expect(view.snapshot.info!.state, WebTerminalInfoState.exited);
      expect(view.snapshot.info!.exitCode, 3);
      expect(view.snapshot.writable, isFalse);
      view.write('x');
      expect(fake.attach.sent, isEmpty);
    });

    test('the Host ending the stream after the exit closes the view', () async {
      await start();
      fake.attach.emit(
        1,
        terminalState(terminalInfo(id: 'term-1', state: 'exited', exitCode: 0)),
      );
      fake.attach.end(1);
      await settle();
      expect(view.snapshot.phase, TerminalPhase.closed);
      expect(view.snapshot.info!.exitCode, 0);
    });

    test(
      'the Host ending the stream of a running shell is an ended attachment',
      () async {
        await start();
        fake.attach.end(1);
        await settle();
        expect(view.snapshot.phase, TerminalPhase.failed);
        expect(view.snapshot.issue, TerminalViewIssue.attachmentEnded);
      },
    );

    test('a Host refusal on attach names the missing terminal', () async {
      view = terminals.view('s1', 'tab1')..mount();
      await settle();
      fake.attach.end(1, RemoteException('terminal/unavailable', 'gone'));
      await settle();
      expect(view.snapshot.issue, TerminalViewIssue.missingTerminal);
    });

    test('a not-running refusal turns input off', () async {
      await start();
      view.write('x');
      fake.attach.emit(1, terminalAck(1, refusal: 'not-running'));
      await settle();
      expect(view.snapshot.writable, isFalse);
    });

    test('a failed process shows its error', () async {
      await start();
      fake.attach.emit(
        1,
        terminalState(
          terminalInfo(id: 'term-1', state: 'failed', error: 'pty lost'),
        ),
      );
      await settle();
      expect(view.snapshot.info!.state, WebTerminalInfoState.failed);
      expect(view.snapshot.info!.error, 'pty lost');
      expect(view.snapshot.writable, isFalse);
    });
  });

  group('rename and close', () {
    test('rename goes to the Host and updates the title', () async {
      await start();
      await view.rename(' build ');
      final call = fake.host.callsTo('terminal/rename').single.args;
      expect(call, {'agentId': 's1', 'id': 'term-1', 'title': 'build'});
      expect(view.snapshot.title, 'build');
    });

    test('closing a tab ends the process in the background and saves the request first', () async {
      await start();
      final gate = Completer<void>();
      fake.host.handlers['terminal/close'] = (_) => gate.future;
      terminals.close('s1', 'tab1');
      expect(prefs.pendingCloses.single.id, 'term-1');
      expect(terminals.existing('s1', 'tab1'), isNull);
      await settle();
      expect(fake.host.callsTo('terminal/close').single.args, {
        'agentId': 's1',
        'id': 'term-1',
      });
      expect(
        fake.retain.cancelled,
        isTrue,
        reason: 'the hold goes with the tab',
      );
      gate.complete();
      await settle();
      expect(prefs.pendingCloses, isEmpty);
      expect(terminals.closeFailures.value, isEmpty);
    });

    test('a failed close stays pending and can be retried', () async {
      await start();
      var fail = true;
      fake.host.handlers['terminal/close'] = (_) {
        if (fail) throw RemoteException('terminal/unavailable', 'busy');
        return null;
      };
      terminals.close('s1', 'tab1');
      await settle();
      expect(terminals.closeFailures.value.single.id, 'term-1');
      expect(prefs.pendingCloses, hasLength(1));
      fail = false;
      terminals.retryClose('term-1');
      await settle();
      expect(terminals.closeFailures.value, isEmpty);
      expect(prefs.pendingCloses, isEmpty);
    });

    test('a saved close request is retried when the service starts', () async {
      await terminals.dispose();
      prefs.saveClose(
        const TerminalCloseRequest(
          sessionId: 's9',
          id: 'left-over',
          title: 'old',
        ),
      );
      terminals = ClientTerminals(host: fake.terminalHost, prefs: prefs);
      await settle();
      expect(fake.host.callsTo('terminal/close').single.args, {
        'agentId': 's9',
        'id': 'left-over',
      });
      expect(prefs.pendingCloses, isEmpty);
    });

    test('a Session the Host does not know retires the request', () async {
      await terminals.dispose();
      fake.host.handlers['terminal/close'] = (_) =>
          throw RemoteException('session/not-found', 'no');
      prefs.saveClose(
        const TerminalCloseRequest(sessionId: 's9', id: 'x', title: 'old'),
      );
      terminals = ClientTerminals(host: fake.terminalHost, prefs: prefs);
      await settle();
      expect(prefs.pendingCloses, isEmpty);
      expect(terminals.closeFailures.value, isEmpty);
    });
  });
}
