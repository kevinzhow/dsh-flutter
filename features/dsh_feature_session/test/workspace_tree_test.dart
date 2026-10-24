import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:flutter_test/flutter_test.dart';

SessionListEntry e(
  String id, {
  String? title,
  int updated = 1000,
  bool blank = false,
  bool running = false,
  String? parent,
  String? origin,
  String? cwd,
}) => SessionListEntry(
  SessionSummary(
    sessionId: id,
    updatedAt: updated,
    running: running,
    blank: blank,
    agentAvailable: true,
    parentSessionId: parent,
    origin: origin,
    cwd: cwd,
  ),
  title,
);

TreeWorkspace ws(String id, List<String> sessions, {String? path}) =>
    TreeWorkspace(
      workspaceId: id,
      title: id.toUpperCase(),
      path: path ?? '/w/$id',
      createdAt: 1,
      sessionIds: sessions,
    );

List<GroupNode> groups(
  List<SessionListEntry> items,
  List<TreeWorkspace> workspaces, {
  SessionRowState rowState = const SessionRowState(),
  Set<String> expanded = const {'a', ungroupedKey},
  String? current,
  Map<String, SessionStatusFacts> statuses = const {},
}) => deriveGroups(
  items: items,
  workspaces: workspaces,
  rowState: rowState,
  statuses: statuses,
  expandedGroups: expanded,
  current: current,
);

void main() {
  group('deriveGroups', () {
    test('workspaces keep the host order, strays trail as Ungrouped', () {
      final g = groups(
        [e('s1'), e('s2'), e('s3')],
        [
          ws('b', ['s2']),
          ws('a', ['s1']),
        ],
      );
      expect([for (final x in g) x.key], ['b', 'a', ungroupedKey]);
      expect(g.last.workspaceId, isNull);
      expect(g.last.sessions.single.id, 's3');
    });

    test('only expanded groups carry rows, and the current one is marked', () {
      final g = groups(
        [e('s1'), e('s2')],
        [
          ws('a', ['s1']),
          ws('b', ['s2']),
        ],
        current: 's2',
      );
      expect(g[0].sessions, hasLength(1));
      expect(g[1].sessions, isEmpty);
      expect(g[1].containsCurrent, isTrue);
      expect(g[0].containsCurrent, isFalse);
    });

    test('blank sessions show only while selected, and lead their group', () {
      final items = [e('s1'), e('blank', blank: true)];
      expect(
        groups(items, [
          ws('a', ['s1', 'blank']),
        ]).first.sessions.map((s) => s.id),
        ['s1'],
      );
      final shown = groups(items, [
        ws('a', ['s1', 'blank']),
      ], current: 'blank');
      expect(shown.first.sessions.map((s) => s.id), ['blank', 's1']);
      expect(shown.first.sessions.first.blank, isTrue);
    });

    test('subagent sessions never get a row', () {
      final g = groups(
        [e('s1'), e('child', origin: 'subagent', parent: 's1')],
        [
          ws('a', ['s1', 'child']),
        ],
      );
      expect(g.first.sessions.map((s) => s.id), ['s1']);
    });

    test('pinned rows lead; archived follow the filter', () {
      final items = [e('s1'), e('s2'), e('s3')];
      final ws1 = [
        ws('a', ['s1', 's2', 's3']),
      ];
      final pinned = groups(
        items,
        ws1,
        rowState: const SessionRowState(pinned: ['s3']),
      );
      expect(pinned.first.sessions.map((s) => s.id), ['s3', 's1', 's2']);
      expect(pinned.first.sessions.first.pinned, isTrue);
      const archived = ['s2'];
      List<String> ids(ArchivedFilter f) => groups(
        items,
        ws1,
        rowState: SessionRowState(archived: archived, filter: f),
      ).first.sessions.map((s) => s.id).toList();
      expect(ids(ArchivedFilter.hide), ['s1', 's3']);
      expect(ids(ArchivedFilter.show), ['s1', 's2', 's3']);
      expect(ids(ArchivedFilter.only), ['s2']);
    });

    test('the archived-only view drops groups without archives', () {
      final g = groups(
        [e('s1'), e('s2')],
        [
          ws('a', ['s1']),
          ws('b', ['s2']),
        ],
        rowState: const SessionRowState(
          archived: ['s2'],
          filter: ArchivedFilter.only,
        ),
        expanded: const {'a', 'b'},
      );
      expect([for (final x in g) x.key], ['b']);
    });

    test('live status decides the row facts', () {
      final g = groups(
        [e('s1')],
        [
          ws('a', ['s1']),
        ],
        statuses: const {
          's1': SessionStatusFacts(
            running: true,
            pending: PendingInteraction.question,
            completionUnread: true,
            runningSubagents: 2,
          ),
        },
      );
      final n = g.first.sessions.single;
      expect(n.running, isTrue);
      expect(n.pending, PendingInteraction.question);
      expect(n.completed, isTrue);
      expect(n.runningSubagents, 2);
    });
  });

  group('ordering', () {
    final byId = {
      'a': e('a', updated: 10),
      'b': e('b', updated: 30),
      'c': e('c', updated: 20),
      'd': e('d', updated: 20),
    };

    test('recency, newest first with the id as tie-break', () {
      expect(orderByRecency(['a', 'b', 'c', 'd', 'gone'], byId), [
        'b',
        'c',
        'd',
        'a',
      ]);
    });

    test('a saved order holds; newcomers follow by recency, archives last', () {
      expect(
        reconcileManualOrder(['a', 'b', 'c', 'd'], ['c', 'a', 'zz'], byId),
        ['c', 'a', 'b', 'd'],
      );
      expect(
        reconcileManualOrder(
          ['a', 'b', 'c', 'd'],
          null,
          byId,
          const SessionRowState(pinned: ['a'], archived: ['b']),
        ),
        ['a', 'c', 'd', 'b'],
      );
    });

    test('a fork sits before its source', () {
      final forks = {
        'src': e('src', updated: 10),
        'fork': e('fork', updated: 5, parent: 'src'),
      };
      expect(reconcileManualOrder(['src', 'fork'], null, forks), [
        'fork',
        'src',
      ]);
    });

    test('the selected blank leads either order', () {
      expect(pinCurrentBlank(['a', 'blank', 'b'], 'blank'), [
        'blank',
        'a',
        'b',
      ]);
      expect(pinCurrentBlank(['a'], null), ['a']);
    });
  });

  group('search', () {
    final items = [
      e('s1', title: 'Fix the parser', updated: 10),
      e('s2', title: 'Plan release', updated: 30, cwd: '/home/x/parser-lib'),
      e('s3', title: 'Other', updated: 20),
      e('blank', blank: true),
    ];

    SearchResultSet run(
      String q, {
      List<ContentMatch> content = const [],
      int limit = 50,
    }) => deriveSearchResults(
      items: items,
      workspaces: [
        ws('a', ['s1']),
      ],
      query: q,
      rowState: const SessionRowState(),
      statuses: const {},
      content: content,
      contentHasMore: false,
      limit: limit,
      current: null,
    );

    test('titles and workspace labels match, newest first', () {
      expect(run('parser').items.map((r) => r.id), ['s2', 's1']);
      expect(run('PARSER').items.first.workspace, 'parser-lib');
      expect(run('  ').items, isEmpty);
    });

    test('host content matches follow and donate their snippet', () {
      final r = run(
        'zzz',
        content: const [
          ContentMatch('s3', 'the zzz line'),
          ContentMatch('blank', 'x'),
        ],
      );
      expect(r.items.map((x) => x.id), ['s3']);
      expect(r.items.single.snippet, 'the zzz line');
    });

    test('the limit bounds the rows and sets the refine hint', () {
      final r = run('a', limit: 1);
      expect(r.items, hasLength(1));
      expect(r.hasMore, isTrue);
    });
  });

  group('paths and watermarks', () {
    test('the owning parent is the nearest registered ancestor', () {
      expect(owningParentFolder('/a/b/c', ['/a', '/a/b', '/x']), '/a/b');
      expect(owningParentFolder('/a', ['/a']), isNull);
      expect(owningParentFolder(r'C:\p\q', [r'C:\p']), r'C:\p');
    });

    test('labels are basenames', () {
      expect(workspaceLabel('/a/b/'), 'b');
      expect(workspaceLabel(r'C:\x\y'), 'y');
      expect(workspaceLabel(null), '');
      expect(workspaceLabel('/'), '/');
    });

    test('rows beyond the watermark fold, the blank row stays', () {
      final rows = [
        for (var i = 0; i < 8; i++)
          SessionNode(
            id: 's$i',
            title: '',
            blank: i == 0,
            running: i == 7,
            runningSubagents: 0,
            completed: false,
            pinned: false,
            archived: false,
            updatedAt: 0,
          ),
      ];
      final shown = watermarkRows(rows, sessionWatermarkBase);
      expect(shown.rows, hasLength(6));
      expect(shown.hidden, 2);
      // A running row past the base raises the needed watermark.
      expect(requiredWatermark(rows, null, null), 7);
      expect(requiredWatermark(rows, 's2', null), 7);
    });
  });

  group('view state', () {
    test('round-trips through its storage', () {
      final storage = MemoryWorkspaceViewStorage();
      final a = WorkspaceViewState(storage: storage)
        ..setGroupBy(SessionGroupBy.flat)
        ..setArchivedFilter(ArchivedFilter.only)
        ..setGroupExpanded('w1', true)
        ..setOrderBy(SessionOrderBy.manual, {
          'w1': ['x', 'y'],
        });
      final b = WorkspaceViewState(storage: storage);
      expect(b.groupBy, SessionGroupBy.flat);
      expect(b.archivedFilter, ArchivedFilter.only);
      expect(b.orderBy, SessionOrderBy.manual);
      expect(b.groupExpansion, {'w1': true});
      expect(b.sessionOrderByAccount, {
        'w1': ['x', 'y'],
      });
      a.setOrderBy(SessionOrderBy.updated, const {});
      expect(a.sessionOrderByAccount, isEmpty);
    });

    test(
      'a damaged blob reads as the defaults; gone workspaces are dropped',
      () {
        final v = WorkspaceViewState(
          storage: MemoryWorkspaceViewStorage('{no'),
        );
        expect(v.groupBy, SessionGroupBy.workspace);
        v
          ..setGroupExpanded('keep', true)
          ..setGroupExpanded('gone', true)
          ..retainAccountKeys(['keep']);
        expect(v.groupExpansion, {'keep': true});
      },
    );
  });
}
