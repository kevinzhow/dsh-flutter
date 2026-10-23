import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 23, 12);

SessionListEntry entry(
  String id, {
  String? title,
  bool running = false,
  bool blank = false,
  String cwd = '/work/project-x',
  Duration ago = const Duration(minutes: 5),
}) => SessionListEntry(
  SessionSummary(
    sessionId: id,
    updatedAt: now.subtract(ago).millisecondsSinceEpoch,
    running: running,
    blank: blank,
    agentAvailable: true,
    cwd: cwd,
  ),
  title,
);

void main() {
  Widget list(
    SessionListSnapshot s, {
    DshI18n i18n = const DshI18n(DshLocale.en),
    ValueChanged<String>? onOpen,
    VoidCallback? onNew,
    Future<void> Function()? onRefresh,
  }) => dshTestApp(
    SessionListView(
      snapshot: s,
      i18n: i18n,
      onOpen: onOpen ?? (_) {},
      onRefresh: onRefresh ?? () async {},
      onNew: onNew ?? () {},
      now: now,
    ),
  );

  testWidgets('empty list explains itself and offers a new session', (t) async {
    var made = 0;
    await t.pumpWidget(
      list(
        const SessionListSnapshot(phase: ListPhase.ready),
        onNew: () => made++,
      ),
    );
    expect(find.byKey(const ValueKey('sessions-empty')), findsOneWidget);
    expect(find.text('No sessions yet'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sessions-empty-new')));
    expect(made, 1);
  });

  testWidgets('blank sessions are not listed', (t) async {
    await t.pumpWidget(
      list(
        SessionListSnapshot(
          phase: ListPhase.ready,
          items: [entry('a', blank: true)],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('sessions-empty')), findsOneWidget);
  });

  testWidgets('rows show title, folder, age and open on tap, newest first', (
    t,
  ) async {
    String? opened;
    await t.pumpWidget(
      list(
        SessionListSnapshot(
          phase: ListPhase.ready,
          items: [
            entry('old', title: 'Older', ago: const Duration(days: 2)),
            entry('new', title: 'Newer', running: true),
            entry('untitled'),
          ],
        ),
        onOpen: (id) => opened = id,
      ),
    );
    expect(find.text('Newer'), findsOneWidget);
    expect(find.textContaining('project-x'), findsWidgets);
    expect(find.textContaining('5 min ago'), findsWidgets);
    expect(find.textContaining('2 d ago'), findsOneWidget);
    expect(find.text('Untitled session'), findsOneWidget);
    final newer = t.getTopLeft(find.text('Newer')).dy;
    final older = t.getTopLeft(find.text('Older')).dy;
    expect(newer, lessThan(older));
    await t.tap(find.text('Older'));
    expect(opened, 'old');
  });

  testWidgets('a failed load shows the error with retry', (t) async {
    var retried = 0;
    await t.pumpWidget(
      list(
        const SessionListSnapshot(state: ListState.error, error: 'boom'),
        onRefresh: () async => retried++,
      ),
    );
    expect(find.byKey(const ValueKey('sessions-error')), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('zh copy', (t) async {
    await t.pumpWidget(
      list(
        const SessionListSnapshot(phase: ListPhase.ready),
        i18n: const DshI18n(DshLocale.zh),
      ),
    );
    expect(find.text('还没有会话'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
  });

  test('relative time and folder helpers', () {
    const en = DshI18n(DshLocale.en);
    expect(relativeTime(en, now, now), 'Just now');
    expect(
      relativeTime(en, now, now.subtract(const Duration(hours: 3))),
      '3 h ago',
    );
    expect(cwdLeaf('/a/b/c/'), 'c');
    expect(cwdLeaf(null), '');
  });
}
