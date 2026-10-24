import 'package:dsh_client/generated_commands.dart' show CommandsRemote;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_commands/dsh_feature_commands.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

CandidateRequest request(String query, {bool leading = true}) =>
    CandidateRequest(
      query: query,
      quoted: false,
      position: leading ? TriggerPosition.leading : TriggerPosition.inline,
      drilled: false,
      signal: AbortSignal.never,
    );

void main() {
  late FakeHost host;
  late FakeSessions sessions;
  late InputTriggerRegistry triggers;
  late CommandUiRegistry commandUi;
  late CommandSource source;
  late RecordingPort port;
  var locale = DshLocale.en;

  setUp(() {
    host = FakeHost();
    sessions = FakeSessions()..held.add('s2');
    triggers = InputTriggerRegistry();
    commandUi = CommandUiRegistry();
    locale = DshLocale.en;
    source = CommandSource(
      registry: commandUi,
      triggers: triggers,
      commands: CommandsRemote(host),
      sessions: sessions,
      i18n: () => DshI18n(locale),
    );
    triggers.registerSource(source);
    port = RecordingPort();
    triggers.sessionOf('s1', port);
  });

  group('the menu', () {
    test('an empty query lists Add then Commands in usage order, unlisted rows last', () async {
      commandUi.register(
        CommandContribution(
          name: 'file',
          label: () => 'File',
          icon: 'paperclip',
          available: (_) => true,
          ui: ActionSpec((_) {}),
        ),
      );
      final rows = await source.candidates('s1', request(''));
      expect(rows.map((r) => r.name), [
        'file', 'goal', 'plan', 'feedback', // Add
        'compact', 'permission', 'export', 'custom', // Commands, unlisted last
      ]);
      expect(rows.first.section, 'Add');
      expect(rows[4].section, 'Commands');
      expect(rows.firstWhere((r) => r.name == 'goal').label, 'Goal');
      expect(
        rows.firstWhere((r) => r.name == 'goal').description,
        'Set or view the goal for a long-running task',
      );
      // A plugin command keeps its catalog description.
      expect(rows.last.description, 'A plugin command');
    });

    test(
      'the zh locale localizes titles, descriptions and section headings',
      () async {
        locale = DshLocale.zh;
        final rows = await source.candidates('s1', request(''));
        expect(rows.first.section, '添加');
        expect(rows.firstWhere((r) => r.name == 'plan').label, '计划');
      },
    );

    test('a typed query ranks by name and label', () async {
      final rows = await source.candidates('s1', request('pl'));
      expect(rows.map((r) => r.name).first, 'plan');
      final byLabel = await source.candidates('s1', request('目标'));
      // The English label is the title; the zh query matches nothing here.
      expect(byLabel, isEmpty);
    });

    test('an inline token hides commands that take input', () async {
      final rows = await source.candidates('s1', request('', leading: false));
      expect(rows.map((r) => r.name), isNot(contains('goal')));
      expect(rows.map((r) => r.name), contains('compact'));
    });

    test('a contribution colliding with a host command fails loudly', () {
      commandUi.register(
        CommandContribution(
          name: 'compact',
          available: (_) => true,
          ui: ActionSpec((_) {}),
        ),
      );
      expect(source.candidates('s1', request('')), throwsStateError);
    });

    test('an unavailable contribution is not listed', () async {
      commandUi.register(
        CommandContribution(
          name: 'model',
          available: (_) => false,
          ui: ActionSpec((_) {}),
        ),
      );
      final rows = await source.candidates('s1', request(''));
      expect(rows.map((r) => r.name), isNot(contains('model')));
    });

    test('a failed catalog rejects: the menu drops the group, never a silent default', () async {
      host.listError = StateError('offline');
      await expectLater(source.candidates('s2', request('')), throwsStateError);
    });

    test('a session the app does not hold never reaches the host', () async {
      await expectLater(
        source.candidates('ghost', request('')),
        throwsStateError,
      );
      expect(host.listed, isNot(contains('ghost')));
    });
  });

  group('the decision table, menu column', () {
    TokenSpan span() => TokenSpan(0, 1, 1);
    InputTriggerPick pick(String name) => InputTriggerPick(
      candidate: InputTriggerCandidate(name: name),
      sessionId: 's1',
      position: TriggerPosition.leading,
      via: PickVia.menu,
      action: PickAction.pick,
      span: span(),
    );

    setUp(() async {
      await source.directory.ensureReady('s1', AbortSignal.never);
    });

    test(
      'a bare host command consumes the token and executes detached',
      () async {
        final out = source.onPick(pick('compact'));
        expect(out, isA<PickHandled>());
        expect(port.calls, ['consumeSpan 0-1']);
        await tick();
        expect(host.executed.single.line, '/compact');
      },
    );

    test('a host command with input claims, spelled in the locale', () {
      final out = source.onPick(pick('plan'))! as PickClaim;
      expect(out.claim.token, '/plan ');
      locale = DshLocale.zh;
      final zh = source.onPick(pick('plan'))! as PickClaim;
      expect(zh.claim.token, '/计划 ');
      // The submit always sends the catalog name.
      expect(zh.claim.name, 'plan');
    });

    test(
      'a contribution opens its popup and consumes only after a selection',
      () async {
        var selected = '';
        commandUi.register(
          CommandContribution(
            name: 'model',
            available: (_) => true,
            ui: PopupSelectSpec(
              options: (s, signal) async => const [
                SelectOption(id: 'm1', label: 'M1'),
              ],
              onSelect: (o, s) async => selected = o.id,
            ),
          ),
        );
        final out = source.onPick(pick('model'));
        expect(out, isA<PickHandled>());
        final popup = source.popupFor('s1');
        expect(popup.state.value.open, isTrue);
        await tick();
        expect(port.calls, isEmpty);
        await popup.select(0);
        expect(selected, 'm1');
        expect(port.calls, ['consumeSpan 0-1', 'focus']);
        expect(popup.state.value.open, isFalse);
      },
    );

    test('an action runs after the token is consumed', () {
      var ran = '';
      commandUi.register(
        CommandContribution(
          name: 'file',
          available: (_) => true,
          ui: ActionSpec((s) => ran = s),
        ),
      );
      source.onPick(pick('file'));
      expect(port.calls, ['consumeSpan 0-1']);
      expect(ran, 's1');
    });

    test(
      'a decoration replaces only the bare invocation of a host command',
      () async {
        commandUi.decorate(
          CommandDecoration(
            name: 'permission',
            available: (_) => true,
            ui: PopupSelectSpec(
              options: (s, g) async => const [],
              onSelect: (o, s) async {},
            ),
          ),
        );
        // Menu pick: the popup, not the claim.
        expect(source.onPick(pick('permission')), isA<PickHandled>());
        expect(source.popupFor('s1').state.value.command, 'permission');
        // An argued line still reaches the host command.
        final out = await source.matchEnter(
          's1',
          '/permission read-only',
          AbortSignal.never,
          const SubmitEnvelope(),
        );
        expect(out, isA<PickClaim>());
      },
    );

    test(
      'a decoration never manufactures a command the host does not list',
      () {
        commandUi.decorate(
          CommandDecoration(
            name: 'ghost',
            available: (_) => true,
            ui: ActionSpec((_) {}),
          ),
        );
        expect(source.onPick(pick('ghost')), isNull);
      },
    );

    test(
      'a failed detached run lands in the composer as an error notice',
      () async {
        host.executeError = StateError('admission failed');
        source.onPick(pick('compact'));
        await tick();
        await tick();
        expect(port.calls.last, contains('notify error'));
      },
    );
  });

  group('Space and Enter', () {
    setUp(() async {
      await source.directory.ensureReady('s1', AbortSignal.never);
    });

    test(
      'Space claims a host command that takes input, with the typed spelling',
      () {
        final out = source.matchSpace('s1', '/goal')! as PickClaim;
        expect(out.claim.token, '/goal ');
        expect(out.claim.attachments, isTrue);
        expect(out.claim.hint, '[<objective>]');
        expect(source.matchSpace('s1', '/compact'), isNull);
        expect(source.matchSpace('s1', '/unknown'), isNull);
      },
    );

    test('Space never claims a client contribution', () {
      commandUi.register(
        CommandContribution(
          name: 'goal',
          available: (_) => true,
          ui: ActionSpec((_) {}),
        ),
      );
      expect(source.matchSpace('s1', '/goal'), isNull);
    });

    test('Enter on a localized spelling executes the catalog name', () async {
      final out = await source.matchEnter(
        's1',
        '/计划 off',
        AbortSignal.never,
        const SubmitEnvelope(),
      );
      final claim = (out! as PickClaim).claim;
      expect(claim.token, '/计划 ');
      final result = await claim.submit('off', const []);
      expect(result.isError, isFalse);
      expect(host.executed.single.line, '/plan off');
    });

    test('Enter on a bare host command with no input executes it and consumes the line', () async {
      final out = await source.matchEnter(
        's1',
        '/compact',
        AbortSignal.never,
        const SubmitEnvelope(),
      );
      expect(out, isA<PickHandled>());
      expect(port.calls, ['consumeToken /compact']);
      await tick();
      expect(host.executed.single.line, '/compact');
    });

    test(
      'Enter with arguments on a command without input is the model\'s',
      () async {
        expect(
          await source.matchEnter(
            's1',
            '/compact now',
            AbortSignal.never,
            const SubmitEnvelope(),
          ),
          isNull,
        );
        expect(host.executed, isEmpty);
      },
    );

    test('an unknown command is ordinary text', () async {
      expect(
        await source.matchEnter(
          's1',
          '/nope',
          AbortSignal.never,
          const SubmitEnvelope(),
        ),
        isNull,
      );
      expect(
        await source.matchEnter(
          's1',
          'plain',
          AbortSignal.never,
          const SubmitEnvelope(),
        ),
        isNull,
      );
      expect(
        await source.matchEnter(
          's1',
          '/',
          AbortSignal.never,
          const SubmitEnvelope(),
        ),
        isNull,
      );
    });

    test('attachments are refused by every route except a command that accepts them', () async {
      for (final line in ['/compact', '/plan x', '/permission']) {
        await expectLater(
          source.matchEnter(
            's1',
            line,
            AbortSignal.never,
            const SubmitEnvelope(attachments: 1),
          ),
          throwsA(isA<SubmitRefused>()),
          reason: line,
        );
      }
      // /goal declares attachments.
      final ok = await source.matchEnter(
        's1',
        '/goal x',
        AbortSignal.never,
        const SubmitEnvelope(attachments: 1),
      );
      expect(ok, isA<PickClaim>());
      // An action submits nothing, so it runs regardless.
      commandUi.register(
        CommandContribution(
          name: 'file',
          available: (_) => true,
          ui: ActionSpec((_) {}),
        ),
      );
      expect(
        await source.matchEnter(
          's1',
          '/file',
          AbortSignal.never,
          const SubmitEnvelope(attachments: 1),
        ),
        isA<PickHandled>(),
      );
      expect(host.executed, isEmpty);
    });

    test(
      'the refusal copy names the typed command in the active locale',
      () async {
        locale = DshLocale.zh;
        await expectLater(
          source.matchEnter(
            's1',
            '/compact',
            AbortSignal.never,
            const SubmitEnvelope(attachments: 1),
          ),
          throwsA(
            isA<SubmitRefused>().having(
              (e) => e.message,
              'message',
              '/compact 不接受附件，请先移除附件',
            ),
          ),
        );
      },
    );

    test('a claimed submit reports an unmatched line as an error and a handler error only with attachments', () async {
      final claim = (source.matchSpace('s1', '/plan')! as PickClaim).claim;
      host.unmatched = true;
      final miss = await claim.submit('x', const []);
      expect(miss.isError, isTrue);
      host.unmatched = false;
      host.result = {'kind': 'error', 'text': 'handler said no'};
      // The Host logged the lifecycle: admission is success.
      expect((await claim.submit('x', const [])).isError, isFalse);
      // With attachments the draft must stay for correction.
      final withFiles = await claim.submit('x', [
        {'type': 'file', 'receiptId': 'r1'},
      ]);
      expect(withFiles.isError, isTrue);
      expect(withFiles.text, 'handler said no');
      expect(host.executed.last.attachments, 1);
    });

    test('a refused call throws instead of reporting success', () async {
      final claim = (source.matchSpace('s1', '/plan')! as PickClaim).claim;
      host.executeError = StateError('refused');
      await expectLater(claim.submit('x', const []), throwsStateError);
    });

    test(
      'restoring a persisted chip resolves its claim after the warmup',
      () async {
        final cold = CommandSource(
          registry: commandUi,
          triggers: triggers,
          commands: CommandsRemote(host),
          sessions: sessions,
          i18n: () => DshI18n(locale),
        );
        final claim = await cold.matchClaim('s1', '/goal', AbortSignal.never);
        expect(claim?.name, 'goal');
        expect(
          await cold.matchClaim('s1', '/compact', AbortSignal.never),
          isNull,
        );
        expect(host.executed, isEmpty);
      },
    );
  });

  group('the directory', () {
    test('one pull serves concurrent callers and the snapshot then answers synchronously', () async {
      host.listDelayTicks = 3;
      final both = await Future.wait([
        source.directory.ensureReady('s2', AbortSignal.never),
        source.directory.ensureReady('s2', AbortSignal.never),
      ]);
      expect(both.first, same(both.last));
      expect(host.listed.where((id) => id == 's2'), hasLength(1));
      expect(source.directory.status('s2'), DirectoryStatus.ready);
      expect(source.directory.resolve('s2', 'goal')?.name, 'goal');
      expect(
        source.directory.resolve('s2', '目标'),
        isNotNull,
      ); // localized alias
      expect(source.directory.resolve('s2', 'nope'), isNull);
    });

    test('a failed pull rejects the waiter and a later call retries', () async {
      host.listError = StateError('offline');
      await expectLater(
        source.directory.ensureReady('s2', AbortSignal.never),
        throwsStateError,
      );
      expect(source.directory.status('s2'), DirectoryStatus.failed);
      host.listError = null;
      expect(
        (await source.directory.ensureReady('s2', AbortSignal.never)),
        isNotEmpty,
      );
    });

    test('an aborted wait rejects without cancelling the pull', () async {
      host.listDelayTicks = 5;
      final abort = AbortController();
      final waiting = source.directory.ensureReady('s2', abort.signal);
      abort.abort();
      await expectLater(waiting, throwsA(anything));
      await tick();
    });

    test('a catalog change refreshes in the background while the old snapshot serves', () async {
      await source.directory.ensureReady('s1', AbortSignal.never);
      host.catalog = [
        {'name': 'only', 'description': 'x'},
      ];
      host.listDelayTicks = 3;
      source.onCommandsChanged();
      expect(source.directory.status('s1'), DirectoryStatus.ready);
      expect(source.directory.resolve('s1', 'goal'), isNotNull);
      for (var i = 0; i < 10; i++) {
        await tick();
      }
      expect(source.directory.resolve('s1', 'goal'), isNull);
      expect(source.directory.resolve('s1', 'only'), isNotNull);
    });

    test(
      'a preset change drops the snapshot until the replacement lands',
      () async {
        await source.directory.ensureReady('s1', AbortSignal.never);
        host.listDelayTicks = 3;
        source.onPresetSelected('s1');
        expect(source.directory.resolve('s1', 'goal'), isNull);
        await source.directory.ensureReady('s1', AbortSignal.never);
        expect(source.directory.resolve('s1', 'goal'), isNotNull);
      },
    );

    test('only the latest pull may publish', () async {
      host.listDelayTicks = 6;
      final first = source.directory.refresh('s1');
      host.catalog = [
        {'name': 'newer', 'description': 'x'},
      ];
      host.listDelayTicks = 0;
      final second = source.directory.refresh('s1');
      await Future.wait([first, second]);
      expect(source.directory.resolve('s1', 'newer'), isNotNull);
    });
  });
}
