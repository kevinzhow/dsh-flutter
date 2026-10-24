import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:test/test.dart';

import 'support/input_fakes.dart';

class _Port implements TriggerEditorPort {
  final List<String> calls = [];
  bool accept = true;
  @override
  bool beginCommand(CommandClaim claim, TokenSpan span) {
    calls.add('claim ${claim.name} ${span.start}-${span.end}');
    return accept;
  }

  @override
  bool consumeBareToken(String token) => accept;
  @override
  bool consumeSpan(TokenSpan span) => accept;
  @override
  bool insertReference(ReferenceInsert reference, TokenSpan span) {
    calls.add('ref ${reference.ref} ${span.start}-${span.end}');
    return accept;
  }

  @override
  bool insertText(String text, TokenSpan span, {bool keepCompleting = false}) {
    calls.add('text $text ${span.start}-${span.end} $keepCompleting');
    return accept;
  }

  @override
  void notify(bool error, String text) => calls.add('notify $text');
  @override
  void requestFocus() {}
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

InputTriggerCandidate row(String name, {bool drill = false}) =>
    InputTriggerCandidate(name: name, drill: drill, value: name);

void main() {
  late InputTriggerRegistry registry;
  late _Port port;
  late FakeSource at;
  late InputTriggerController c;

  setUp(() {
    registry = InputTriggerRegistry();
    at = FakeSource(
      sourceName: 'reference',
      rows: [row('a'), row('b', drill: true), row('c')],
    );
    registry.registerSource(at);
    port = _Port();
    c = registry.sessionOf('s', port);
  });

  group('registry', () {
    test('a duplicate trigger and name is refused', () {
      expect(
        () => registry.registerSource(FakeSource(sourceName: 'reference')),
        throwsStateError,
      );
      // The same name under another trigger is a different source.
      registry.registerSource(
        FakeSource(sourceName: 'reference', char: TriggerChar.slash),
      );
    });

    test('menu order is the declared order, ties by registration', () {
      registry.registerSource(FakeSource(sourceName: 'late', order0: 5));
      registry.registerSource(FakeSource(sourceName: 'early', order0: -1));
      registry.registerSource(FakeSource(sourceName: 'tie'));
      expect(registry.sources(TriggerChar.at).map((s) => s.name), [
        'early',
        'reference',
        'tie',
        'late',
      ]);
    });

    test('a session controller warms every source once and a late source is warmed too', () {
      expect(at.warmed, ['s']);
      final late = FakeSource(sourceName: 'late');
      registry.registerSource(late);
      expect(late.warmed, ['s']);
      expect(identical(registry.sessionOf('s', port), c), isTrue);
    });

    test('disposing a source drops its group from an open menu', () async {
      final other = FakeSource(sourceName: 'other', rows: [row('x')]);
      final off = registry.registerSource(other);
      c.track('@', 1, TriggerTier.plain, 1);
      await tick();
      expect(c.menu.value.groups.map((g) => g.source), ['reference', 'other']);
      off();
      expect(c.menu.value.groups.map((g) => g.source), ['reference']);
    });
  });

  group('tracking', () {
    test(
      'a trigger opens one pending group per source, then settles',
      () async {
        c.track('hi @', 4, TriggerTier.plain, 3);
        expect(c.menu.value.open, isTrue);
        expect(c.menu.value.groups.single.ready, isFalse);
        await tick();
        final g = c.menu.value.groups.single;
        expect(g.ready, isTrue);
        expect(g.items.map((i) => i.name), ['a', 'b', 'c']);
        expect(c.menu.value.highlight, const MenuHighlight('reference', 0));
        expect(c.menu.value.hit!.span, TokenSpan(3, 4, 3));
      },
    );

    test(
      'moving the caret off the token closes the menu and aborts the fetch',
      () async {
        at.hold = true;
        c.track('@a', 2, TriggerTier.plain, 1);
        final signal = at.requests.single.signal;
        c.track('@a b', 4, TriggerTier.plain, 2);
        expect(c.menu.value.open, isFalse);
        expect(signal.aborted, isTrue);
      },
    );

    test('a late settlement of a superseded request is dropped', () async {
      at.hold = true;
      c.track('@a', 2, TriggerTier.plain, 1);
      c.track('@ab', 3, TriggerTier.plain, 2);
      expect(at.pending, hasLength(2));
      at.pending[1].$2.complete([row('fresh')]);
      await tick();
      await tick();
      at.pending[0].$2.complete([row('stale')]);
      await tick();
      await tick();
      expect(c.menu.value.groups.single.items.map((i) => i.name), ['fresh']);
    });

    test('a refinement keeps the previous rows on screen until the new ones settle', () async {
      c.track('@', 1, TriggerTier.plain, 1);
      await tick();
      at.hold = true;
      c.track('@a', 2, TriggerTier.plain, 2);
      final g = c.menu.value.groups.single;
      expect(g.ready, isFalse);
      expect(g.items, hasLength(3));
    });

    test('a failing source disappears silently and the menu closes when none is left', () async {
      at.failWith = StateError('boom');
      c.track('@', 1, TriggerTier.plain, 1);
      await tick();
      expect(c.menu.value.open, isFalse);
    });

    test('an empty answer auto-closes', () async {
      at.rows = const [];
      c.track('@', 1, TriggerTier.plain, 1);
      await tick();
      expect(c.menu.value.open, isFalse);
    });

    test('a frozen tier closes the menu and never opens one', () async {
      c.track('@', 1, TriggerTier.plain, 1);
      await tick();
      c.track('@', 1, TriggerTier.frozen, 2);
      expect(c.menu.value.open, isFalse);
      c.track('@x', 2, TriggerTier.frozen, 3);
      expect(c.menu.value.open, isFalse);
    });

    test('a token with no registered source opens nothing', () {
      c.track('/', 1, TriggerTier.plain, 1);
      expect(c.menu.value.open, isFalse);
    });
  });

  group('keyboard', () {
    setUp(() async {
      c.track('@', 1, TriggerTier.plain, 1);
      await tick();
    });

    test('arrows wrap the highlight and are consumed', () {
      expect(c.arbitrate(ArbitrateKey.down), ArbitrateOutcome.consumed);
      expect(c.menu.value.highlight!.index, 1);
      c.arbitrate(ArbitrateKey.down);
      c.arbitrate(ArbitrateKey.down);
      expect(c.menu.value.highlight!.index, 0);
      c.arbitrate(ArbitrateKey.up);
      expect(c.menu.value.highlight!.index, 2);
    });

    test('Enter settles the highlighted row through its source', () {
      at.onPickFn = (p) => PickInsertReference(
        ReferenceInsert(
          source: 'reference',
          ref: '@${p.candidate.name}',
          label: p.candidate.name,
          clipboardText: '@${p.candidate.name}',
        ),
      );
      expect(c.arbitrate(ArbitrateKey.enter), ArbitrateOutcome.pickHighlighted);
      expect(port.calls, ['ref @a 0-1']);
      expect(at.picks.single.via, PickVia.menu);
      expect(at.picks.single.action, PickAction.pick);
    });

    test('Tab drills a drillable row and settles an ordinary one', () {
      c.arbitrate(ArbitrateKey.down);
      c.arbitrate(ArbitrateKey.tab);
      expect(at.picks.last.action, PickAction.drill);
      expect(at.picks.last.candidate.name, 'b');
    });

    test('Escape and Shift+Tab leave without settling and the same token stays dismissed', () async {
      expect(c.arbitrate(ArbitrateKey.escape), ArbitrateOutcome.consumed);
      expect(c.menu.value.open, isFalse);
      expect(at.picks, isEmpty);
      // Re-tracking the same token and query does not bring it back.
      c.track('@', 1, TriggerTier.plain, 1);
      expect(c.menu.value.open, isFalse);
      // A new query re-arms it.
      c.track('@a', 2, TriggerTier.plain, 2);
      expect(c.menu.value.open, isTrue);
    });

    test(
      'Enter while the refinement is pending is consumed without picking',
      () {
        at.hold = true;
        c.track('@a', 2, TriggerTier.plain, 2);
        expect(c.arbitrate(ArbitrateKey.enter), ArbitrateOutcome.consumed);
        expect(at.picks, isEmpty);
      },
    );

    test('Enter with no highlight and every key during composition pass', () {
      expect(
        c.arbitrate(ArbitrateKey.down, composing: true),
        ArbitrateOutcome.pass,
      );
      c.dismiss();
      expect(c.arbitrate(ArbitrateKey.enter), ArbitrateOutcome.pass);
    });

    test('hover and pick follow the pointer', () {
      c.hover('reference', 2);
      expect(c.menu.value.highlight!.index, 2);
      c.pick('reference', 1);
      expect(at.picks.single.candidate.name, 'b');
      expect(c.menu.value.open, isFalse);
    });
  });

  group('picks', () {
    setUp(() async {
      c.track('see @', 5, TriggerTier.plain, 7);
      await tick();
    });

    test('a pick settles the token: the menu stays shut for it', () {
      c.pick('reference', 0);
      c.track('see @', 5, TriggerTier.plain, 7);
      expect(c.menu.value.open, isFalse);
    });

    test(
      'a drill keeps completing: the next request is marked drilled',
      () async {
        at.onPickFn = (p) => const PickInsertText('@b/', keepCompleting: true);
        c.pick('reference', 1, PickAction.drill);
        expect(port.calls.single, 'text @b/ 4-5 true');
        c.track('see @b/', 7, TriggerTier.plain, 8);
        await tick();
        expect(at.requests.last.drilled, isTrue);
        expect(at.requests.last.query, 'b/');
      },
    );

    test('a refused edit withdraws the drill claim', () async {
      port.accept = false;
      at.onPickFn = (p) => const PickInsertText('@b/', keepCompleting: true);
      c.pick('reference', 1, PickAction.drill);
      c.track('see @b/', 7, TriggerTier.plain, 8);
      await tick();
      expect(at.requests.last.drilled, isFalse);
    });

    test('crumbs publish per source and a crumb pick drills back', () async {
      final withHeader = _HeaderSource();
      registry.registerSource(withHeader);
      c.track('see @src/', 9, TriggerTier.plain, 9);
      expect(c.headers.value['crumbs']!.map((x) => x.label), ['root', 'src']);
      c.pickCrumb('crumbs', 0);
      expect(withHeader.picks.single.action, PickAction.drill);
      expect(withHeader.picks.single.candidate.value, 'root-value');
      // The current crumb is not a target.
      c.track('see @src/', 9, TriggerTier.plain, 10);
      c.pickCrumb('crumbs', 1);
      expect(withHeader.picks, hasLength(1));
    });
  });

  group('space and enter adjudication', () {
    test('Space polls only leading tokens, in registration order, first answer wins', () {
      final first = FakeCommandSource(known: {'goal'});
      registry.registerSource(first);
      c.track('/goal', 5, TriggerTier.plain, 1);
      expect(c.onSpace(), isTrue);
      expect(port.calls.single, startsWith('claim goal 0-5'));
      port.calls.clear();
      c.track('x /goal', 7, TriggerTier.plain, 2);
      expect(c.onSpace(), isFalse);
    });

    test('Enter polls sources whose trigger opens the line', () async {
      final commands = FakeCommandSource(known: {'plan'});
      registry.registerSource(commands);
      final out = await c.adjudicate(
        '/plan now',
        AbortSignal.never,
        const SubmitEnvelope(),
      );
      expect(out, isA<PickClaim>());
      expect(
        await c.adjudicate('@x', AbortSignal.never, const SubmitEnvelope()),
        isNull,
      );
      final aborted = AbortController()..abort();
      await expectLater(
        c.adjudicate('/plan', aborted.signal, const SubmitEnvelope()),
        throwsA(anything),
      );
    });

    test('a persisted chip resolves its claim without acting', () async {
      final commands = FakeCommandSource(known: {'goal'});
      registry.registerSource(commands);
      // matchClaim is not claimed by the fake: restore answers null, never executes.
      expect(await c.resolveClaim('/goal', AbortSignal.never), isNull);
      expect(commands.executed, isEmpty);
    });
  });

  test('a disposed controller ignores everything', () {
    c.dispose();
    c.track('@', 1, TriggerTier.plain, 1);
    expect(c.menu.value.open, isFalse);
    expect(c.arbitrate(ArbitrateKey.down), ArbitrateOutcome.pass);
    expect(c.onSpace(), isFalse);
  });

  test('toggling the launcher opens one source over a synthetic span and closes it again', () async {
    final hit = TriggerHit(
      trigger: TriggerChar.at,
      query: '',
      quoted: false,
      position: TriggerPosition.inline,
      span: TokenSpan(4, 4, 2),
    );
    c.toggleSource('reference', hit);
    expect(c.launcher.value, 'reference');
    await tick();
    expect(c.menu.value.open, isTrue);
    c.toggleSource('reference', hit);
    expect(c.menu.value.open, isFalse);
    expect(c.launcher.value, isNull);
  });
}

class _HeaderSource extends FakeSource {
  _HeaderSource()
    : super(
        sourceName: 'crumbs',
        rows: [InputTriggerCandidate(name: 'x')],
      );

  @override
  List<InputTriggerCrumb>? header(String sessionId, HeaderRequest req) =>
      const [
        InputTriggerCrumb(label: 'root', value: 'root-value'),
        InputTriggerCrumb(label: 'src', value: 'src-value', current: true),
      ];
}
