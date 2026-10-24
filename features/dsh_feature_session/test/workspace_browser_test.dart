import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 23, 12);

SessionListEntry entry(
  String id, {
  String? title,
  bool blank = false,
  bool running = false,
  int minutesAgo = 5,
}) => SessionListEntry(
  SessionSummary(
    sessionId: id,
    updatedAt: now
        .subtract(Duration(minutes: minutesAgo))
        .millisecondsSinceEpoch,
    running: running,
    blank: blank,
    agentAvailable: true,
  ),
  title,
);

TreeWorkspace workspace(String id, String title, List<String> sessions) =>
    TreeWorkspace(
      workspaceId: id,
      title: title,
      path: '/w/$id',
      createdAt: 1,
      sessionIds: sessions,
    );

void main() {
  late WorkspaceViewState view;
  var opened = <String>[];
  var started = <String>[];
  var added = 0;

  setUp(() {
    view = WorkspaceViewState();
    opened = [];
    started = [];
    added = 0;
  });

  Future<void> pump(
    WidgetTester t, {
    List<SessionListEntry>? items,
    List<TreeWorkspace>? workspaces,
    String? currentId,
    bool wide = true,
    Future<RemoteSearchResult> Function(String)? search,
    SessionRowState rowState = const SessionRowState(),
  }) async {
    t.view.physicalSize = const Size(280, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      dshTestApp(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: WorkspaceBrowser(
            snapshot: SessionListSnapshot(
              phase: ListPhase.ready,
              items:
                  items ??
                  [
                    entry('s1', title: 'Fix parser', minutesAgo: 5),
                    entry('s2', title: 'Plan release', minutesAgo: 120),
                    entry('s3', title: 'Loose end', minutesAgo: 3000),
                  ],
            ),
            workspaces:
                workspaces ??
                [
                  workspace('w1', 'Project X', ['s1', 's2']),
                ],
            view: view,
            i18n: const DshI18n(DshLocale.en),
            currentId: currentId,
            rowState: rowState,
            onOpen: opened.add,
            wide: wide,
            onStartInWorkspace: started.add,
            addControl: (box, icon, ink) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => added++,
              child: SizedBox(width: box, height: box),
            ),
            search: search,
            now: () => now,
          ),
        ),
        size: const Size(280, 600),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('groups are folded until opened, and Ungrouped trails', (
    t,
  ) async {
    await pump(t);
    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.text('Project X'), findsOneWidget);
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('Fix parser'), findsNothing);
    await t.tap(find.text('Project X'));
    await t.pumpAndSettle();
    expect(find.text('Fix parser'), findsOneWidget);
    expect(find.text('5min'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    await t.tap(find.text('Fix parser'));
    expect(opened, ['s1']);
    // Folding again hides the rows; the choice persists in the view state.
    await t.tap(find.text('Project X'));
    await t.pumpAndSettle();
    expect(find.text('Fix parser'), findsNothing);
    expect(view.groupExpansion['w1'], isFalse);
  });

  testWidgets('the group of the open session opens by itself', (t) async {
    await pump(t, currentId: 's2');
    expect(find.text('Plan release'), findsOneWidget);
    expect(
      find.text('Loose end'),
      findsNothing,
      reason: 'Ungrouped stays folded',
    );
  });

  testWidgets('the blank current session reads New Session, without a time', (
    t,
  ) async {
    await pump(
      t,
      items: [
        entry('b', blank: true),
        entry('s1', title: 'T'),
      ],
      workspaces: [
        workspace('w1', 'Project X', ['b', 's1']),
      ],
      currentId: 'b',
    );
    expect(find.text('New Session'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('5min'), findsOneWidget, reason: 'only the real session');
  });

  testWidgets('more than five rows fold behind a count that expands', (
    t,
  ) async {
    await pump(
      t,
      items: [
        for (var i = 0; i < 8; i++)
          entry('s$i', title: 'Row $i', minutesAgo: 10 + i),
      ],
      workspaces: [
        workspace('w1', 'W', [for (var i = 0; i < 8; i++) 's$i']),
      ],
      currentId: 's0',
    );
    expect(find.text('Row 4'), findsOneWidget);
    expect(find.text('Row 5'), findsNothing);
    await t.tap(find.text('Show 3 more sessions'));
    await t.pumpAndSettle();
    expect(find.text('Row 7'), findsOneWidget);
    await t.tap(find.text('Show less'));
    await t.pumpAndSettle();
    expect(find.text('Row 7'), findsNothing);
  });

  testWidgets('the row button starts a session in its workspace', (t) async {
    await pump(t);
    final row = find.byKey(const ValueKey('workspace-row-w1'));
    final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(t.getCenter(row));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('workspace-row-new')));
    await t.pumpAndSettle();
    expect(started, ['w1']);
    expect(view.groupExpansion['w1'], isTrue);
  });

  testWidgets('search narrows to matches and opens one', (t) async {
    await pump(
      t,
      search: (q) async =>
          const RemoteSearchResult([ContentMatch('s3', 'an excerpt')], false),
    );
    await t.tap(find.byKey(const ValueKey('browser-search')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('browser-search-input')),
      'rel',
    );
    await t.pump(searchDebounce + const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.text('Plan release'), findsOneWidget);
    expect(find.text('Fix parser'), findsNothing);
    await t.tap(find.text('Plan release'));
    await t.pumpAndSettle();
    expect(opened, ['s2']);
    expect(find.byKey(const ValueKey('browser-search-open')), findsNothing);
  });

  testWidgets('a search with no match says so', (t) async {
    await pump(t, search: (q) async => const RemoteSearchResult([], false));
    await t.tap(find.byKey(const ValueKey('browser-search')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('browser-search-input')),
      'qqq',
    );
    await t.pump(searchDebounce + const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('browser-no-matches')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('browser-search-clear')));
    await t.pumpAndSettle();
    expect(find.text('Workspaces'), findsOneWidget);
  });

  testWidgets('view options regroup, reorder and filter', (t) async {
    await pump(t);
    await t.tap(find.byKey(const ValueKey('browser-view-options')));
    await t.pumpAndSettle();
    expect(find.text('Group by'), findsOneWidget);
    expect(find.text('In one list'), findsOneWidget);
    await t.tap(find.text('In one list'));
    await t.pumpAndSettle();
    expect(view.groupBy, SessionGroupBy.flat);
    expect(find.text('Sessions'), findsOneWidget, reason: 'the flat header');
    expect(find.text('Fix parser'), findsOneWidget);
    expect(find.text('Loose end'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('browser-view-options')));
    await t.pumpAndSettle();
    await t.tap(find.text('Archived only'));
    await t.pumpAndSettle();
    expect(view.archivedFilter, ArchivedFilter.only);
    expect(find.text('No archived sessions yet'), findsOneWidget);
    await t.tap(find.text('View other sessions'));
    await t.pumpAndSettle();
    expect(view.archivedFilter, ArchivedFilter.hide);
  });

  testWidgets(
    'the add button reaches the host chooser; the rail keeps two controls',
    (t) async {
      await pump(t);
      await t.tap(find.byKey(const ValueKey('browser-add')));
      expect(added, 1);
      await pump(t, wide: false);
      expect(find.text('Workspaces'), findsNothing);
      expect(find.byKey(const ValueKey('browser-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-add')), findsOneWidget);
    },
  );
}
