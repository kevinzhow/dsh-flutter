import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_terminal.dart';
import 'package:dsh_feature_sidebar_terminal/dsh_feature_sidebar_terminal.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart' as xterm;

class _Actions implements SidebarTabBindingActions {
  final bindings = <String, Map<String, Object?>>{};
  @override
  void rememberBinding(String tabId, Map<String, Object?> binding) {
    bindings[tabId] = binding;
  }

  final List<({String kind, String? replace, Map<String, Object?> params})>
  opened = [];

  @override
  void openResource(
    String address, {
    int? line,
    Map<String, Object?> params = const {},
  }) {}

  @override
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  }) => opened.add((kind: kind, replace: replaceTabId, params: params));
}

const _phone = Size(400, 800);

void main() {
  late FakeTerminalHost fake;
  late ClientTerminals terminals;
  late SlotRegistry slots;
  late _Actions actions;
  late SidebarTabOwner owner;
  var i18n = const DshI18n(DshLocale.en);

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    fake = FakeTerminalHost();
    fake.host.generation = FakeGeneration();
    terminals = ClientTerminals(host: fake.terminalHost, newId: () => 'term-1');
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerSidebarTerminalFeature(
      slots,
      i18n: () => i18n,
      terminals: terminals,
    );
    actions = _Actions();
    owner = SidebarTabOwner(
      session: testSessionOwner('s1'),
      id: 'terminal-1',
      kind: 'terminal',
      contentId: 'sidebar://terminal/1',
      actions: actions,
    );
  });

  tearDown(() async {
    await terminals.dispose();
    await fake.close();
  });

  Widget body({Size size = _phone, SidebarTabOwner? tab}) => dshTestApp(
    Builder(
      builder: (context) => slots.renderKeyed(
        DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
        'terminal',
        tab ?? owner,
      )!,
    ),
    size: size,
  );

  Future<void> surface(WidgetTester t, Size size) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> open(WidgetTester t, {Map<String, Object?>? snapshot}) async {
    await surface(t, _phone);
    await t.pumpWidget(body());
    await settle(t);
    fake.attach.start(
      1,
      snapshot ?? terminalSnapshot(info: terminalInfo(id: 'term-1')),
    );
    await settle(t);
  }

  xterm.Terminal screen(WidgetTester t) => t
      .widget<xterm.TerminalView>(find.byKey(const ValueKey('terminal-screen')))
      .terminal;

  test(
    'a durable Host identity reattaches without creating a replacement shell',
    () async {
      final original = terminalViewOf(terminals, owner);
      await Future<void>.delayed(Duration.zero);
      expect(actions.bindings[owner.id], {'terminalId': original.id});
      fake.host.handlers['terminal/list'] = (_) => [
        terminalInfo(id: original.id),
      ];
      final restoredService = ClientTerminals(
        host: fake.terminalHost,
        newId: () =>
            throw StateError('Restoration must not allocate a terminal'),
      );
      final restoredOwner = SidebarTabOwner(
        session: owner.session,
        id: owner.id,
        kind: owner.kind,
        contentId: owner.contentId,
        params: actions.bindings[owner.id]!,
        actions: actions,
      );
      final restored = terminalViewOf(restoredService, restoredOwner);
      await restored.refresh();
      expect(restored.snapshot.info?.id, original.id);
      expect(fake.host.callsTo('terminal/create'), isEmpty);
      await restoredService.dispose();
    },
  );
  test(
    'a missing restored Host terminal never starts a new shell on retry',
    () async {
      final restoredService = ClientTerminals(
        host: fake.terminalHost,
        newId: () => throw StateError('Unexpected allocation'),
      );
      final restoredOwner = SidebarTabOwner(
        session: owner.session,
        id: owner.id,
        kind: owner.kind,
        contentId: owner.contentId,
        params: const {'terminalId': 'synthetic-missing'},
        actions: actions,
      );
      final restored = terminalViewOf(restoredService, restoredOwner);
      await restored.refresh();
      await restored.refresh();
      expect(restored.snapshot.issue, TerminalViewIssue.missingTerminal);
      expect(fake.host.callsTo('terminal/create'), isEmpty);
      await restoredService.dispose();
    },
  );
  testWidgets('shows the reading and starting states before a screen exists', (
    t,
  ) async {
    final gate = Completer<void>();
    fake.host.handlers['terminal/environment'] = (_) async {
      await gate.future;
      return terminalEnvironment();
    };
    await t.pumpWidget(body());
    await t.pump();
    expect(find.text('Reading terminal environment…'), findsOneWidget);
    expect(find.byKey(const ValueKey('terminal-screen')), findsNothing);
    gate.complete();
    await settle(t);
    expect(find.text('Connecting…'), findsOneWidget);
  });

  testWidgets('draws the Host screen and follows its output', (t) async {
    await open(
      t,
      snapshot: terminalSnapshot(
        screen: 'user@host:~\$ ls\r\nfile.txt',
        info: terminalInfo(id: 'term-1'),
      ),
    );
    expect(find.byKey(const ValueKey('terminal-status')), findsNothing);
    final text = screen(t).buffer.getText();
    expect(text, contains('user@host:~\$ ls'));
    expect(text, contains('file.txt'));
    fake.attach.emit(1, terminalOutput(1, '\r\nnext line'));
    await settle(t);
    expect(screen(t).buffer.getText(), contains('next line'));
  });

  testWidgets('the Host grid follows the size of the view', (t) async {
    await open(t);
    final terminal = screen(t);
    final resize = fake.attach.sentOf<TerminalInputResize>();
    expect(resize, isNotEmpty);
    expect(
      (resize.last.cols, resize.last.rows),
      (terminal.viewWidth, terminal.viewHeight),
    );
  });

  testWidgets('typing reaches the shell, in order', (t) async {
    await open(t);
    final terminal = screen(t);
    terminal.textInput('l');
    terminal.textInput('s');
    terminal.keyInput(xterm.TerminalKey.enter);
    await settle(t);
    final data = fake.attach.sentOf<TerminalInputWrite>().map((w) => w.data);
    expect(data.join(), 'ls\r');
  });

  group('key bar', () {
    testWidgets('has Esc, Tab, Ctrl and the arrows on a phone', (t) async {
      await open(t);
      expect(find.byKey(const ValueKey('terminal-key-bar')), findsOneWidget);
      for (final key in [
        'escape',
        'tab',
        'ctrl',
        'up',
        'down',
        'left',
        'right',
      ]) {
        expect(find.byKey(ValueKey('terminal-key-$key')), findsOneWidget);
      }
    });

    testWidgets('sends the keys a soft keyboard lacks', (t) async {
      await open(t);
      Future<List<String>> press(String key) async {
        final before = fake.attach.sentOf<TerminalInputWrite>().length;
        await t.tap(find.byKey(ValueKey('terminal-key-$key')));
        await settle(t);
        return fake.attach
            .sentOf<TerminalInputWrite>()
            .skip(before)
            .map((w) => w.data)
            .toList();
      }

      expect(await press('escape'), ['\x1b']);
      expect(await press('tab'), ['\t']);
      expect(await press('up'), ['\x1b[A']);
      expect(await press('down'), ['\x1b[B']);
      expect(await press('right'), ['\x1b[C']);
      expect(await press('left'), ['\x1b[D']);
    });

    testWidgets('Ctrl waits for the next character, then lets go', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('terminal-key-ctrl')));
      await settle(t);
      screen(t).textInput('c');
      await settle(t);
      screen(t).textInput('c');
      await settle(t);
      final data = fake.attach.sentOf<TerminalInputWrite>().map((w) => w.data);
      expect(data, ['\x03', 'c']);
    });

    testWidgets('Ctrl does nothing to a key with no control code', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('terminal-key-ctrl')));
      await settle(t);
      screen(t).textInput('é');
      await settle(t);
      expect(fake.attach.sentOf<TerminalInputWrite>().map((w) => w.data), [
        'é',
      ]);
    });

    testWidgets('is not drawn on a wide window or while read-only', (t) async {
      await surface(t, const Size(1400, 900));
      await t.pumpWidget(body(size: const Size(1400, 900)));
      await settle(t);
      fake.attach.start(1, terminalSnapshot(info: terminalInfo(id: 'term-1')));
      await settle(t);
      expect(find.byKey(const ValueKey('terminal-key-bar')), findsNothing);
    });

    testWidgets('is not drawn when the view cannot write', (t) async {
      await open(
        t,
        snapshot: terminalSnapshot(
          writable: false,
          info: terminalInfo(id: 'term-1'),
        ),
      );
      expect(find.byKey(const ValueKey('terminal-key-bar')), findsNothing);
    });

    test('control characters follow the usual mapping', () {
      expect(controlCharacterFor('c'), '\x03');
      expect(controlCharacterFor('C'), '\x03');
      expect(controlCharacterFor('d'), '\x04');
      expect(controlCharacterFor('['), '\x1b');
      expect(controlCharacterFor('@'), '\x00');
      expect(controlCharacterFor('1'), isNull);
      expect(controlCharacterFor('ab'), isNull);
      expect(controlCharacterFor(''), isNull);
    });
  });

  group('states', () {
    testWidgets('read-only: says so and takes control on request', (t) async {
      await open(
        t,
        snapshot: terminalSnapshot(
          writable: false,
          info: terminalInfo(id: 'term-1'),
        ),
      );
      expect(find.text('This view is read-only.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('terminal-take-control')));
      await settle(t);
      expect(fake.attaches, hasLength(2));
      fake.attach.start(1, terminalSnapshot(info: terminalInfo(id: 'term-1')));
      await settle(t);
      expect(find.text('This view is read-only.'), findsNothing);
    });

    testWidgets('disconnected: keeps the screen and offers to reconnect', (
      t,
    ) async {
      fake = FakeTerminalHost(autoAck: false);
      fake.host.generation = FakeGeneration();
      terminals = ClientTerminals(
        host: fake.terminalHost,
        newId: () => 'term-1',
      );
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      registerSidebarTerminalFeature(
        slots,
        i18n: () => i18n,
        terminals: terminals,
      );
      await surface(t, _phone);
      await t.pumpWidget(body());
      await settle(t);
      fake.retain
        ..open(1)
        ..ack(1);
      await settle(t);
      fake.attach.start(
        1,
        terminalSnapshot(
          screen: 'still here',
          info: terminalInfo(id: 'term-1'),
        ),
      );
      await settle(t);
      fake.reconnect(); // the connection is gone and the hold not yet back
      await settle(t);
      expect(find.text('Disconnected.'), findsOneWidget);
      expect(find.byKey(const ValueKey('terminal-reconnect')), findsOneWidget);
      expect(screen(t).buffer.getText(), contains('still here'));
      expect(find.byKey(const ValueKey('terminal-error')), findsNothing);
      await t.tap(find.byKey(const ValueKey('terminal-reconnect')));
      await settle(t);
      expect(fake.attaches, hasLength(2));
    });

    testWidgets(
      'exited: shows the code and opens a new terminal in its place',
      (t) async {
        await open(t);
        fake.attach.emit(
          1,
          terminalState(
            terminalInfo(id: 'term-1', state: 'exited', exitCode: 3),
          ),
        );
        await settle(t);
        expect(find.text('Process exited (3)'), findsOneWidget);
        expect(find.byKey(const ValueKey('terminal-key-bar')), findsNothing);
        await t.tap(find.byKey(const ValueKey('terminal-new')));
        expect(actions.opened.single.kind, 'terminal');
        expect(actions.opened.single.replace, 'terminal-1');
      },
    );

    testWidgets('closed by the Host after the exit', (t) async {
      await open(t);
      fake.attach.emit(
        1,
        terminalState(terminalInfo(id: 'term-1', state: 'exited', exitCode: 0)),
      );
      fake.attach.end(1);
      await settle(t);
      expect(find.text('Process exited (0)'), findsOneWidget);
      expect(find.byKey(const ValueKey('terminal-new')), findsOneWidget);
    });

    testWidgets('a shell that failed shows its error and no reconnect', (
      t,
    ) async {
      await open(t);
      fake.attach.emit(
        1,
        terminalState(
          terminalInfo(id: 'term-1', state: 'failed', error: 'pty lost'),
        ),
      );
      await settle(t);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Terminal error: pty lost'), findsOneWidget);
    });

    testWidgets('the session limit explains itself', (t) async {
      fake.host.handlers['terminal/create'] = (_) => throw RemoteException(
        'terminal/limit-reached',
        'limit',
        {'limit': 8},
      );
      await t.pumpWidget(body());
      await settle(t);
      expect(
        find.textContaining('The terminal limit has been reached.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('terminal-retry')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('terminal-retry')));
      await settle(t);
      expect(fake.host.callsTo('terminal/environment'), hasLength(2));
    });

    testWidgets('a terminal the Host no longer has', (t) async {
      final missing = SidebarTabOwner(
        session: owner.session,
        id: 'terminal-9',
        kind: 'terminal',
        contentId: 'sidebar://terminal/9',
        actions: actions,
      );
      // A restored identity that the Host does not list.
      terminals.view('s1', 'terminal-9', terminalId: 'gone');
      await t.pumpWidget(body(tab: missing));
      await settle(t);
      expect(
        find.text('This terminal no longer exists. Open a new terminal.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('terminal-new')));
      expect(actions.opened.single.replace, 'terminal-9');
    });

    testWidgets('a broken screen stream names itself', (t) async {
      await open(t);
      fake.attach.emit(1, terminalOutput(5, 'gap'));
      await settle(t);
      expect(
        find.textContaining('The terminal screen could not be received.'),
        findsOneWidget,
      );
    });

    testWidgets('the input buffer limit names itself', (t) async {
      fake.host.handlers['terminal/environment'] = (_) =>
          terminalEnvironment(maxInputBytes: 2);
      await open(t);
      screen(t).textInput('abc');
      await settle(t);
      expect(find.textContaining('The input buffer is full.'), findsOneWidget);
    });
  });

  testWidgets('zh copy comes from the generated catalog', (t) async {
    i18n = const DshI18n(DshLocale.zh);
    await open(t);
    fake.attach.emit(
      1,
      terminalState(terminalInfo(id: 'term-1', state: 'exited', exitCode: 3)),
    );
    await settle(t);
    expect(find.text('进程已退出（3）'), findsOneWidget);
    expect(find.text('新建终端'), findsOneWidget);
  });

  group('tab chrome', () {
    testWidgets('the title follows the Host name and renames on long press', (
      t,
    ) async {
      await surface(t, _phone);
      await t.pumpWidget(
        dshTestApp(
          Builder(
            builder: (context) => Column(
              children: [
                SizedBox(
                  height: 44,
                  child: slots.renderKeyed(
                    DshSlots.sidebarRightPaneTabTitle
                        .typed<SidebarTabOwner, Widget>(),
                    'terminal',
                    owner,
                  )!,
                ),
                SizedBox(
                  height: 600,
                  child: slots.renderKeyed(
                    DshSlots.sidebarRightPaneTab
                        .typed<SidebarTabOwner, Widget>(),
                    'terminal',
                    owner,
                  )!,
                ),
              ],
            ),
          ),
        ),
      );
      await settle(t);
      fake.attach.start(
        1,
        terminalSnapshot(
          info: terminalInfo(id: 'term-1', title: 'bash'),
        ),
      );
      await settle(t);
      expect(find.text('bash'), findsWidgets);
      fake.attach.emit(
        1,
        terminalState(terminalInfo(id: 'term-1', title: 'build')),
      );
      await settle(t);
      expect(find.text('build'), findsOneWidget);
      await t.longPress(find.byKey(const ValueKey('terminal-title')));
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('terminal-rename')), 'ops');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      final rename = fake.host.callsTo('terminal/rename').single.args;
      expect(rename, {'agentId': 's1', 'id': 'term-1', 'title': 'ops'});
    });

    testWidgets(
      'the tab type is multiple, listed on the guide, and ends the process on close',
      (t) async {
        final type = slots.sidebarTabs.typeOf('terminal')!;
        expect(type.multiple, isTrue);
        expect(type.guideOrder, isNotNull);
        await t.pumpWidget(body());
        await settle(t);
        type.onClose!('s1', 'terminal-1', 'sidebar://terminal/1');
        await settle(t);
        expect(fake.host.callsTo('terminal/close').single.args, {
          'agentId': 's1',
          'id': 'term-1',
        });
      },
    );
  });

  group('guide card', () {
    Widget card() => dshTestApp(
      Builder(
        builder: (context) => slots.renderKeyed(
          DshSlots.sidebarRightTabGuideEntry.typed<SidebarGuideOwner, Widget>(),
          'terminal',
          SidebarGuideOwner(
            session: owner.session,
            kind: 'terminal',
            tabId: 'guide-1',
            actions: actions,
          ),
        )!,
      ),
      size: _phone,
    );

    testWidgets('opens the remembered shell at once', (t) async {
      await surface(t, _phone);
      await t.pumpWidget(card());
      expect(find.text('New terminal'), findsOneWidget);
      expect(
        find.text('Run commands in the Session workspace'),
        findsOneWidget,
      );
      await t.tap(find.text('New terminal'));
      expect(actions.opened.single.kind, 'terminal');
      expect(actions.opened.single.replace, 'guide-1');
      expect(actions.opened.single.params, isEmpty);
    });

    testWidgets('lists the shells, remembers the pick and opens it', (t) async {
      await surface(t, _phone);
      await t.pumpWidget(card());
      await t.tap(find.byKey(const ValueKey('terminal-shell-menu')));
      await t.pumpAndSettle();
      expect(fake.host.callsTo('terminal/shells'), hasLength(1));
      expect(
        fake.host.callsTo('terminal/create'),
        isEmpty,
        reason: 'listing starts no process',
      );
      expect(find.text('bash'), findsOneWidget);
      expect(find.text('zsh'), findsOneWidget);
      await t.tap(find.text('zsh'));
      await t.pumpAndSettle();
      expect(actions.opened.single.params, {'shellPath': '/usr/bin/zsh'});
      expect(
        (await terminals.launchShells('s1')).selectedShell,
        '/usr/bin/zsh',
      );
    });

    testWidgets('a failed lookup offers a retry', (t) async {
      await surface(t, _phone);
      var fail = true;
      fake.host.handlers['terminal/shells'] = (_) {
        if (fail) throw RemoteException('x/y', 'no shells today');
        return [
          {'path': '/bin/sh', 'args': <Object?>[], 'name': 'sh'},
        ];
      };
      await t.pumpWidget(card());
      await t.tap(find.byKey(const ValueKey('terminal-shell-menu')));
      await t.pumpAndSettle();
      expect(find.textContaining('no shells today'), findsOneWidget);
      fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('sh'), findsOneWidget);
    });
  });
}
