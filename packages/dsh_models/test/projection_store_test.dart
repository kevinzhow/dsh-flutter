import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

void main() {
  test('higher seq wins; replays and stale frames drop', () {
    final s = ProjectionStore()
      ..apply('k', 'a', 5)
      ..apply('k', 'old', 5)
      ..apply('k', 'older', 3);
    expect(s.get('k'), 'a');
    s.apply('k', 'b', 6);
    expect(s.get('k'), 'b');
    expect(s.seqOf('k'), 6);
  });

  test('cached rows fill only absent keys and yield to sequenced rows', () {
    final s = ProjectionStore()..apply('title', 'live', 4);
    s.applyCached({'title': 'cached', 'goal': 'g'});
    expect(s.get('title'), 'live');
    expect(s.get('goal'), 'g');
    expect(s.seqOf('goal'), isNull);
    s.apply('goal', 'seq', 1);
    expect(s.get('goal'), 'seq');
  });

  test('seed drops cached rows and rows the baseline lacks unless newer', () {
    final s = ProjectionStore()
      ..applyCached({'c': 1})
      ..apply('old', 1, 2)
      ..apply('newer', 1, 20)
      ..seed(10, {'a': 1});
    expect(s.values, {'a': 1, 'newer': 1});
  });

  test('changes publishes immutable snapshots; clear empties', () {
    final s = ProjectionStore();
    final seen = <Map<String, Object?>>[];
    s.changes.listen(seen.add);
    s.apply('k', 1, 1);
    s.clear();
    expect(s.values, isEmpty);
    expect(() => seen.first['x'] = 1, throwsUnsupportedError);
  });
}
