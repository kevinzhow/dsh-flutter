import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

void main() {
  test('projection changes name the session whose values moved', () async {
    final manager = SessionManager(FakeTransport());
    final changed = <String>[];
    final sub = manager.projectionChanges.listen(changed.add);
    addTearDown(() async {
      await sub.cancel();
      await manager.dispose();
    });
    manager.handleControlFrame({
      'type': 'projection',
      'sessionId': 's1',
      'key': 'userQuestions',
      'seq': 3,
      'value': {'active': <Object?>[], 'settled': <Object?>[]},
    });
    manager.handleControlFrame({
      'type': 'projection',
      'sessionId': 's2',
      'key': 'title',
      'seq': 1,
      'value': 'T',
    });
    expect(changed, ['s1', 's2']);
    expect(manager.projectionSessionIds, containsAll(['s1', 's2']));
    expect(
      manager.projectionValues('s1')['userQuestions'],
      isA<Map<Object?, Object?>>(),
    );
  });

  test('an observable disposes even with a listener still attached', () async {
    final value = Observable(1);
    final seen = <int>[];
    value.changes.listen(seen.add);
    value.set(2);
    await value.dispose().timeout(const Duration(seconds: 1));
    expect(seen, [2]);
  });
}
