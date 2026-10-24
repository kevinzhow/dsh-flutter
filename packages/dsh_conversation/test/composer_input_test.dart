import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:test/test.dart';

import 'support/input_fakes.dart';

const ref = atomicChar;

ReferenceInsert file(String path, {String? text}) => ReferenceInsert(
  source: 'reference',
  ref: text ?? '@$path',
  label: path.split('/').last,
  appearance: 'file',
  clipboardText: text ?? '@$path',
);

void main() {
  late InputTriggerRegistry registry;
  late ComposerInput input;
  late FakeReferenceSource reference;

  setUp(() {
    registry = InputTriggerRegistry();
    reference = FakeReferenceSource();
    registry.registerSource(reference);
    input = ComposerInput(sessionId: 's1')..bind(registry);
  });

  tearDown(() => input.dispose());

  /// Type [text] at the end, one character at a time, as a soft keyboard does.
  void type(String text) {
    for (final ch in text.split('')) {
      final s = input.snapshot;
      final next =
          s.text.substring(0, s.selEnd) + ch + s.text.substring(s.selEnd);
      final held = input.textChanged(
        next,
        s.selEnd + ch.length,
        s.selEnd + ch.length,
      );
      expect(held, isNotEmpty);
    }
  }

  group('chips in the draft', () {
    test('inserting a reference replaces the token with one placeholder and a space', () {
      type('see @re');
      final s = input.snapshot;
      expect(
        input.insertReference(file('README.md'), TokenSpan(4, 7, s.rev)),
        isTrue,
      );
      expect(input.snapshot.text, 'see $ref ');
      expect(input.snapshot.chips.single.ref, '@README.md');
      expect(input.clipboardText, 'see @README.md ');
      // The caret lands after the separating space.
      expect(input.snapshot.selEnd, 6);
    });

    test('a space that already follows is not doubled', () {
      type('@a b');
      // move the caret back after the token
      input.textChanged('@a b', 2, 2);
      final s = input.snapshot;
      expect(
        input.insertReference(file('a.txt'), TokenSpan(0, 2, s.rev)),
        isTrue,
      );
      expect(input.snapshot.text, '$ref b');
    });

    test('a stale draft revision refuses the insertion', () {
      type('@a');
      final stale = TokenSpan(0, 2, input.snapshot.rev);
      type('b');
      expect(input.insertReference(file('a.txt'), stale), isFalse);
      expect(input.snapshot.chips, isEmpty);
    });

    test('deleting a placeholder removes exactly its chip', () {
      input.setPlainText('');
      type('@x');
      input.insertReference(
        file('one.txt'),
        TokenSpan(0, 2, input.snapshot.rev),
      );
      type('@y');
      var s = input.snapshot;
      input.insertReference(file('two.txt'), TokenSpan(2, 4, s.rev));
      s = input.snapshot;
      expect(s.text, '$ref $ref ');
      // Backspace over the first chip: the caret ends where the chip began.
      input.textChanged(' $ref ', 0, 0);
      expect(input.snapshot.chips.map((c) => c.ref), ['@two.txt']);
      expect(input.clipboardText, ' @two.txt ');
    });

    test('adjacent chips stay distinct when the second is deleted', () {
      input.addReferences([file('a.txt'), file('b.txt')]);
      final s = input.snapshot;
      expect(s.chips.map((c) => c.ref), ['@a.txt', '@b.txt']);
      // Delete the second placeholder (caret ends at its start).
      final text = s.text;
      final at = text.lastIndexOf(atomicChar);
      input.textChanged(text.substring(0, at) + text.substring(at + 1), at, at);
      expect(input.snapshot.chips.map((c) => c.ref), ['@a.txt']);
    });

    test('a pasted or typed placeholder never becomes a chip', () {
      final held = input.textChanged('a${ref}b', 2, 2);
      expect(held, 'ab');
      expect(input.snapshot.chips, isEmpty);
      input.paste('x${ref}y');
      expect(input.snapshot.text, 'abxy');
    });

    test(
      'a folder reference carries its trailing slash label and appearance',
      () {
        type('@do');
        input.insertReference(
          const ReferenceInsert(
            source: 'reference',
            ref: '@docs/',
            label: 'docs/',
            appearance: 'folder',
            clipboardText: '@docs/',
          ),
          TokenSpan(0, 3, input.snapshot.rev),
        );
        expect(input.snapshot.chips.single.appearance, 'folder');
        expect(input.snapshot.chips.single.label, 'docs/');
      },
    );
  });

  group('claimed commands', () {
    late FakeCommandSource commands;
    setUp(() {
      commands = FakeCommandSource(known: {'goal', 'plan'});
      registry.registerSource(commands);
    });

    test(
      'space after a completed leading token claims it and consumes the space',
      () {
        type('/goal');
        final held = input.textChanged('/goal ', 6, 6);
        expect(input.snapshot.claim?.name, 'goal');
        expect(input.snapshot.phase, InputPhase.claimed);
        // The chip carries the separator itself.
        expect(held, '$ref ');
        expect(input.snapshot.text, '$ref ');
        expect(input.clipboardText, '/goal ');
      },
    );

    test('an unknown token takes the space as ordinary text', () {
      type('/nope');
      input.textChanged('/nope ', 6, 6);
      expect(input.snapshot.claim, isNull);
      expect(input.snapshot.text, '/nope ');
    });

    test('deleting the command chip releases the claim', () {
      type('/goal');
      input.textChanged('/goal ', 6, 6);
      expect(input.snapshot.claim, isNotNull);
      input.textChanged(' ', 0, 0);
      expect(input.snapshot.claim, isNull);
      expect(input.snapshot.phase, InputPhase.plain);
    });

    test('a claimed draft suppresses the slash trigger but keeps @', () {
      type('/goal');
      input.textChanged('/goal ', 6, 6);
      type('see /x');
      expect(input.triggers!.menu.value.open, isFalse);
      type(' @r');
      expect(input.triggers!.menu.value.open, isTrue);
      expect(input.triggers!.menu.value.hit!.trigger, TriggerChar.at);
    });

    test(
      'submit runs the claimed command with the text after the token',
      () async {
        type('/goal');
        input.textChanged('/goal ', 6, 6);
        type('ship it');
        var sent = false;
        final result = await input.submit(send: (_) async => sent = true);
        expect(result, isA<SubmitCommandRan>());
        expect(sent, isFalse);
        expect(commands.executed, ['/goal ship it']);
        expect(input.snapshot.text, isEmpty);
        expect(input.snapshot.claim, isNull);
      },
    );

    test('a command that refuses keeps the draft and the claim', () async {
      final refusing = InputTriggerRegistry();
      final failing = FakeCommandSource();
      refusing.registerSource(failing);
      final c = ComposerInput(sessionId: 's2')..bind(refusing);
      final claim = CommandClaim(
        name: 'x',
        token: '/x ',
        submit: (args, attachments) async => const SubmitOutcome.error('nope'),
      );
      c.textChanged('/x', 2, 2);
      c.beginCommand(claim, TokenSpan(0, 2, c.snapshot.rev));
      await expectLater(
        c.submit(send: (_) async {}),
        throwsA(
          isA<SubmitRefused>().having((e) => e.message, 'message', 'nope'),
        ),
      );
      expect(c.snapshot.claim, isNotNull);
      expect(c.snapshot.phase, InputPhase.claimed);
      c.dispose();
    });

    test(
      'attachments are refused by a command that does not accept them',
      () async {
        type('/goal');
        input.textChanged('/goal ', 6, 6);
        await expectLater(
          input.submit(
            send: (_) async {},
            attachments: 1,
            unsupportedAttachments: (t) => 'no attachments for $t',
          ),
          throwsA(
            isA<SubmitRefused>().having(
              (e) => e.message,
              'message',
              'no attachments for /goal',
            ),
          ),
        );
        expect(commands.executed, isEmpty);
      },
    );

    test('a bare typed line adjudicates through the source on Enter', () async {
      type('/plan');
      final result = await input.submit(
        send: (_) async => fail('not a message'),
      );
      expect(result, isA<SubmitCommandRan>());
      expect(commands.executed, ['/plan ']);
    });

    test('an adjudication failure rejects and leaves the draft', () async {
      commands.enterError = StateError('catalog warmup failed');
      type('/plan');
      await expectLater(
        input.submit(send: (_) async {}),
        throwsA(isA<StateError>()),
      );
      expect(input.clipboardText, '/plan');
      expect(input.snapshot.phase, InputPhase.plain);
    });

    test('an unknown slash line goes to the model as ordinary text', () async {
      type('/unknown thing');
      final sent = <String>[];
      final result = await input.submit(send: (t) async => sent.add(t));
      expect(result, isA<SubmitSent>());
      expect(sent, ['/unknown thing']);
    });
  });

  group('submit serializes references exactly as dsh web sends them', () {
    test('a file chip becomes its @path text, a session chip the canonical mention', () async {
      type('look at @a');
      input.insertReference(
        file('src/main.dart'),
        TokenSpan(8, 10, input.snapshot.rev),
      );
      type('and @pla');
      final s = input.snapshot;
      final start = s.text.lastIndexOf('@');
      input.insertReference(
        const ReferenceInsert(
          source: 'reference',
          ref: '@[Planning chat](dsh-session:abc123)',
          label: 'Planning chat',
          appearance: 'session',
          clipboardText: '@[Planning chat](dsh-session:abc123)',
        ),
        TokenSpan(start, s.selEnd, s.rev),
      );
      final sent = <String>[];
      await input.submit(send: (t) async => sent.add(t));
      expect(sent, [
        'look at @src/main.dart and @[Planning chat](dsh-session:abc123)',
      ]);
      expect(reference.serialized, [
        '@src/main.dart',
        '@[Planning chat](dsh-session:abc123)',
      ]);
      expect(input.snapshot.text, isEmpty);
      expect(input.snapshot.chips, isEmpty);
    });

    test(
      'a path with spaces keeps its quoted form and the text is trimmed',
      () async {
        input.addReferences([
          file('my docs/read me.md', text: '@"my docs/read me.md"'),
        ]);
        type('  summarise  ');
        final sent = <String>[];
        await input.submit(send: (t) async => sent.add(t));
        expect(sent, ['@"my docs/read me.md"   summarise']);
      },
    );

    test('a serializer failure blocks the send and keeps the draft', () async {
      reference.serializeError = StateError('gone');
      input.addReferences([file('a.txt')]);
      await expectLater(
        input.submit(send: (_) async => fail('must not send')),
        throwsA(isA<StateError>()),
      );
      expect(input.snapshot.chips, hasLength(1));
    });

    test('a rejected send keeps the draft and its chips', () async {
      input.addReferences([file('a.txt')]);
      await expectLater(
        input.submit(send: (_) async => throw StateError('host refused')),
        throwsA(isA<StateError>()),
      );
      expect(input.snapshot.chips, hasLength(1));
      expect(input.clipboardText, '@a.txt ');
    });

    test('an empty draft with no attachment sends nothing; an attachment alone sends empty text', () async {
      expect(
        await input.submit(send: (_) async => fail('empty')),
        isA<SubmitNothing>(),
      );
      final sent = <String>[];
      final result = await input.submit(
        send: (t) async => sent.add(t),
        attachments: 1,
      );
      expect(result, isA<SubmitSent>());
      expect(sent, ['']);
    });
  });

  group('the pipeline over the draft', () {
    test('typing @ opens the reference menu and a pick through the controller inserts the chip', () async {
      reference.rows = [
        const InputTriggerCandidate(
          name: 'README.md',
          value: 'file',
          icon: 'file',
        ),
      ];
      reference.onPickFn = (pick) => PickInsertReference(file('README.md'));
      type('hi @');
      await Future<void>.delayed(Duration.zero);
      final menu = input.triggers!.menu;
      expect(menu.value.open, isTrue);
      expect(menu.value.groups.single.items.single.name, 'README.md');
      expect(menu.value.hit!.query, '');
      input.triggers!.pick('reference', 0);
      expect(menu.value.open, isFalse);
      expect(input.snapshot.text, 'hi $ref ');
      // The pick settled the token: typing on does not bring the menu back.
      type('x');
      expect(menu.value.open, isFalse);
    });

    test(
      'a drill pick splices text and keeps the menu following the token',
      () async {
        reference.rows = [
          const InputTriggerCandidate(name: 'src/', drill: true, value: 'dir'),
        ];
        reference.onPickFn = (pick) => pick.action == PickAction.drill
            ? const PickInsertText('@src/', keepCompleting: true)
            : null;
        type('@s');
        await Future<void>.delayed(Duration.zero);
        input.triggers!.pick('reference', 0, PickAction.drill);
        expect(input.snapshot.text, '@src/');
        await Future<void>.delayed(Duration.zero);
        final req = reference.requests.last;
        expect(req.query, 'src/');
        expect(req.drilled, isTrue);
      },
    );

    test('the file picker binding answers availability and opens', () {
      var opened = 0;
      var available = false;
      final off = input.bindFilePicker(() => available, () => opened++);
      expect(input.canPickFiles, isFalse);
      expect(input.pickFiles(), isFalse);
      available = true;
      expect(input.pickFiles(), isTrue);
      expect(opened, 1);
      off();
      expect(input.canPickFiles, isFalse);
    });

    test('consuming a bare token clears only a draft equal to it', () {
      type('/plan');
      expect(input.consumeBareToken('/other'), isFalse);
      expect(input.consumeBareToken('/plan'), isTrue);
      expect(input.snapshot.text, isEmpty);
    });

    test('a menu span is consumed only at its own revision', () {
      type('/pl');
      final span = TokenSpan(0, 3, input.snapshot.rev);
      type('a');
      expect(input.consumeSpan(span), isFalse);
      expect(input.consumeSpan(TokenSpan(0, 4, input.snapshot.rev)), isTrue);
      expect(input.snapshot.text, isEmpty);
    });
  });
}
