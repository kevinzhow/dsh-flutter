import 'package:dsh_conversation/src/user_text/document.dart';
import 'package:test/test.dart';

UserTextNode node(String id, int start, int end) =>
    UserTextNode(id, start, end, {'label': 'Synthetic'});
void main() {
  test(
    'original start precedes priority, same-start priority then ID is stable',
    () {
      final r = UserTextRegistry();
      r.register(
        UserTextRule(
          id: 'z',
          order: 0,
          match: (t, f, c) => f <= 2 ? node('z', 2, 4) : null,
        ),
      );
      r.register(
        UserTextRule(
          id: 'b',
          order: 0,
          match: (t, f, c) => f <= 2 ? node('b', 2, 5) : null,
        ),
      );
      r.register(
        UserTextRule(
          id: 'a',
          order: 99,
          match: (t, f, c) => f <= 1 ? node('a', 1, 2) : null,
        ),
      );
      expect(r.createDocument().evaluate('abcdef').map((n) => n.id), [
        'text',
        'a',
        'b',
        'text',
      ]);
    },
  );
  test(
    'only read facts invalidate queries and equal JSON reuses identities',
    () {
      final r = UserTextRegistry();
      var calls = 0;
      r.register(
        UserTextRule(
          id: 'tag',
          order: 0,
          match: (text, from, c) {
            calls++;
            c.read('labels');
            return from == 0 ? node('tag', 0, 1) : null;
          },
        ),
      );
      final doc = r.createDocument(), labels = ['Synthetic'];
      final first = doc.evaluate('a', facts: {'labels': labels, 'unread': 0});
      final count = calls;
      expect(
        identical(
          doc.evaluate('a', facts: {'labels': labels, 'unread': 1}),
          first,
        ),
        isTrue,
      );
      expect(calls, count);
      expect(
        identical(
          doc.evaluate(
            'a',
            facts: {
              'labels': ['Synthetic'],
            },
          ),
          first,
        ),
        isTrue,
      );
      expect(calls, greaterThan(count));
      doc.evaluate('b', facts: {'labels': labels});
      expect(calls, greaterThan(count + 1));
    },
  );
  test('failed queries are cached and retry after a read fact changes', () {
    final r = UserTextRegistry();
    var calls = 0;
    late UserTextContext escaped;
    r.register(
      UserTextRule(
        id: 'tag',
        order: 0,
        match: (text, from, c) {
          escaped = c;
          calls++;
          if (c.read('allow') != true) throw StateError('Synthetic refusal');
          return null;
        },
      ),
    );
    final doc = r.createDocument();
    expect(
      () => doc.evaluate('original'),
      throwsA(isA<UserTextTransformException>()),
    );
    expect(
      () => doc.evaluate('original'),
      throwsA(isA<UserTextTransformException>()),
    );
    expect(calls, 1);
    expect(() => escaped.read('allow'), throwsStateError);
    expect(
      doc.evaluate('original', facts: {'allow': true}).single.data['text'],
      'original',
    );
    expect(calls, 2);
  });
  test(
    'registration rejects invalid definitions and disposal is idempotent',
    () {
      final r = UserTextRegistry();
      UserTextRule rule(String id, double order) =>
          UserTextRule(id: id, order: order, match: (t, f, c) => null);
      expect(() => r.register(rule('text', 0)), throwsArgumentError);
      expect(() => r.register(rule('', 0)), throwsArgumentError);
      expect(
        () => r.register(rule('bad', double.infinity)),
        throwsArgumentError,
      );
      final off = r.register(rule('tag', 0));
      expect(() => r.register(rule('tag', 0)), throwsStateError);
      final revision = r.revision;
      off();
      off();
      expect(r.revision, revision + 1);
      expect(() => r.register(rule('tag', 0)), returnsNormally);
    },
  );
  test('invalid, nonprogressing, relabeled and rewritten source nodes fail atomically', () {
    for (final bad in [
      node('tag', 0, 0),
      node('tag', -1, 1),
      node('tag', 0, 10),
      node('other', 0, 1),
      UserTextNode('text', 0, 1, {'text': 'changed'}),
    ]) {
      final r = UserTextRegistry()
        ..register(UserTextRule(id: 'tag', order: 0, match: (t, f, c) => bad));
      expect(
        () => r.createDocument().evaluate('original'),
        throwsA(isA<UserTextTransformException>()),
      );
    }
  });
  test('the same document cannot recursively enter its own rule', () {
    final r = UserTextRegistry();
    late UserTextDocument doc;
    r.register(
      UserTextRule(
        id: 'tag',
        order: 0,
        match: (t, f, c) {
          doc.evaluate(t);
          return null;
        },
      ),
    );
    doc = r.createDocument();
    expect(
      () => doc.evaluate('original'),
      throwsA(isA<UserTextTransformException>()),
    );
  });
  test('fact numbers use Object.is semantics for signed zero and NaN', () {
    final r = UserTextRegistry();
    var calls = 0;
    r.register(
      UserTextRule(
        id: 'tag',
        order: 0,
        match: (t, f, c) {
          calls++;
          c.read('value');
          return null;
        },
      ),
    );
    final doc = r.createDocument();
    doc.evaluate('x', facts: {'value': 0.0});
    doc.evaluate('x', facts: {'value': -0.0});
    expect(calls, 2);
    doc.evaluate('x', facts: {'value': double.nan});
    doc.evaluate('x', facts: {'value': double.nan});
    expect(calls, 3);
  });
}
