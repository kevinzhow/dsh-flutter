import 'package:dsh_slots/dsh_slots.dart';
import 'package:test/test.dart';

void main() {
  late SlotRegistry r;
  setUp(() {
    r = SlotRegistry();
    for (final s in DshSlots.all) {
      r.declare(s);
    }
  });

  group('guard: composition errors fail loudly', () {
    test('registering into an undeclared slot fails', () {
      const undeclared = Slot<int, String>(
        'feature.made.up',
        SlotCardinality.list,
        SlotScope.root,
      );
      expect(
        () => r.register(undeclared, (p) => '$p', id: 'x'),
        throwsA(isA<SlotError>()),
      );
    });

    test('declaring the same slot twice fails', () {
      expect(
        () => r.declare(DshSlots.conversationView),
        throwsA(isA<SlotError>()),
      );
    });

    test('a duplicate list id fails', () {
      final slot = DshSlots.conversationView.typed<int, String>();
      r.register(slot, (p) => 'a', id: 'chat');
      expect(
        () => r.register(slot, (p) => 'b', id: 'chat'),
        throwsA(isA<SlotError>()),
      );
    });

    test('a duplicate keyed cell fails at the same priority', () {
      final slot = DshSlots.toolCallToolview.typed<int, String>();
      r.register(slot, (p) => 'a', key: 'read_image');
      expect(
        () => r.register(slot, (p) => 'b', key: 'read_image'),
        throwsA(isA<SlotError>()),
      );
      r.register(slot, (p) => 'override', key: 'read_image', priority: -1);
      expect(r.renderKeyed(slot, 'read_image', 0), 'override');
    });

    test('a list slot needs an id and a keyed slot needs a key', () {
      expect(
        () => r.register(
          DshSlots.conversationView.typed<int, String>(),
          (p) => 'x',
        ),
        throwsA(isA<SlotError>()),
      );
      expect(
        () => r.register(
          DshSlots.conversationChatNode.typed<int, String>(),
          (p) => 'x',
        ),
        throwsA(isA<SlotError>()),
      );
    });

    test(
      'a slot cannot be used with a different cardinality than declared',
      () {
        const lie = Slot<int, String>(
          'conversation.view',
          SlotCardinality.keyed,
          SlotScope.session,
        );
        expect(
          () => r.register(lie, (p) => 'x', key: 'k'),
          throwsA(isA<SlotError>()),
        );
      },
    );

    test('names must look like dsh slot names', () {
      expect(
        () => r.declare(
          const Slot<int, String>(
            'Bad Name',
            SlotCardinality.single,
            SlotScope.root,
          ),
        ),
        throwsA(isA<SlotError>()),
      );
      expect(
        () => r.declare(
          const Slot<int, String>(
            'a..b',
            SlotCardinality.single,
            SlotScope.root,
          ),
        ),
        throwsA(isA<SlotError>()),
      );
    });

    test('every shipped declaration uses a valid dsh-shaped name', () {
      for (final s in DshSlots.all) {
        expect(slotNamePattern.hasMatch(s.name), isTrue, reason: s.name);
      }
      expect(
        DshSlots.all.map((s) => s.name).toSet().length,
        DshSlots.all.length,
      );
    });
  });

  group('dispatch', () {
    test('list orders by order then registration', () {
      final s = DshSlots.conversationSessionHeaderActions.typed<int, String>();
      r.register(s, (p) => 'b', id: 'b', order: 5);
      r.register(s, (p) => 'a', id: 'a', order: 1);
      r.register(s, (p) => 'c', id: 'c', order: 5);
      expect(r.renderList(s, 0), ['a', 'b', 'c']);
    });

    test('single: lowest priority shadows', () {
      final s = DshSlots.conversationHeader.typed<int, String>();
      expect(r.renderSingle(s, 0), isNull);
      r.register(s, (p) => 'default');
      r.register(s, (p) => 'override', priority: -10);
      expect(r.renderSingle(s, 0), 'override');
    });

    test(
      'chain: first non-null select in priority order renders with matched',
      () {
        final s = DshSlots.conversationComposer.typed<int, String>();
        r.registerChain<int, String, String>(
          s,
          select: (p) => p > 10 ? 'big' : null,
          builder: (p, m) => 'first:$m',
          priority: 1,
        );
        r.registerChain<int, int, String>(
          s,
          select: (p) => p > 5 ? p : null,
          builder: (p, m) => 'second:$m',
          priority: 2,
        );
        expect(r.renderChain(s, 20), 'first:big');
        expect(r.renderChain(s, 7), 'second:7');
        expect(r.renderChain(s, 1), isNull);
      },
    );
  });

  group('labelled list entries', () {
    test('entries lists id, order and the resolved label', () {
      final s = DshSlots.settingsSection.typed<int, String>();
      var locale = 'en';
      r.register(
        s,
        (p) => 'models',
        id: 'models',
        order: 5,
        label: () => locale == 'en' ? 'Models' : '模型',
      );
      r.register(
        s,
        (p) => 'general',
        id: 'general',
        order: 0,
        label: () => 'General',
      );
      r.register(s, (p) => 'bare', id: 'bare', order: 9);
      expect(
        [for (final e in r.entries(s)) (e.id, e.order, e.label)],
        [('general', 0, 'General'), ('models', 5, 'Models'), ('bare', 9, null)],
      );
      locale = 'zh';
      expect(r.entries(s)[1].label, '模型');
    });

    test('renderOnly renders the one occupant', () {
      final s = DshSlots.settingsSection.typed<int, String>();
      r.register(s, (p) => 'g$p', id: 'general');
      r.register(s, (p) => 'm$p', id: 'models');
      expect(r.renderOnly(s, 'models', 7), 'm7');
      expect(r.renderOnly(s, 'nope', 7), isNull);
    });

    test('a registration can be withdrawn and announces both changes', () {
      final s = DshSlots.settingsGeneralItem.typed<int, String>();
      final seen = <String>[];
      final sub = r.changes.listen(seen.add);
      final off = r.register(s, (p) => 'row', id: 'row');
      expect(r.renderList(s, 0), ['row']);
      off();
      off();
      expect(r.renderList(s, 0), isEmpty);
      expect(seen, ['settings.general.item', 'settings.general.item']);
      // The id is free again.
      r.register(s, (p) => 'again', id: 'row');
      sub.cancel();
    });
  });
}
