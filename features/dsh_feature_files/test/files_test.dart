import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_files/dsh_feature_files.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Actions implements SidebarTabActions {
  @override
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  }) {}

  final List<String> opened = [];
  @override
  void openResource(
    String address, {
    int? line,
    Map<String, Object?> params = const {},
  }) => opened.add(address);
}

WorkspaceDirectoryEntry dir(String n) =>
    WorkspaceDirectoryEntry(name: n, type: WorkspaceEntryType.directory);
WorkspaceDirectoryEntry file(String n, [int? size]) =>
    WorkspaceDirectoryEntry(name: n, type: WorkspaceEntryType.file, size: size);
WorkspaceDirectoryEntry other(String n) =>
    WorkspaceDirectoryEntry(name: n, type: WorkspaceEntryType.other);

void main() {
  late FakeWorkspaceFiles files;
  late _Actions actions;
  var i18n = const DshI18n(DshLocale.en);

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    files = FakeWorkspaceFiles()
      ..root = '/work/project'
      ..listings['.'] = [
        file('file10.txt'),
        file('file2.txt'),
        dir('src'),
        dir('Docs'),
        other('socket'),
      ]
      ..listings['/work/project/src'] = [file('main.dart'), dir('inner')]
      ..listings['/work/project/src/inner'] = <WorkspaceDirectoryEntry>[];
    actions = _Actions();
  });

  Widget view({String? cwd = '/work/project', SessionFileServices? services}) {
    final owner = SessionOwner(
      session: testSessionOwner('s1').session,
      conversation: testSessionOwner('s1').conversation,
      actions: FakeActions(),
      cwdReader: () => cwd,
      hostHome: '/work',
      files: services ?? FakeFileServices(files),
    );
    return dshTestApp(
      FilesView(
        owner: SidebarTabOwner(
          session: owner,
          kind: 'files',
          contentId: 'sidebar://files',
          actions: actions,
        ),
        i18n: i18n,
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump();
  }

  test('natural order puts file2 before file10, directories first', () {
    expect(naturalCompare('file2', 'file10'), lessThan(0));
    expect(naturalCompare('A', 'a'), 0);
    final ordered = orderEntries([
      file('b'),
      dir('z'),
      file('a10'),
      file('a2'),
      dir('Y'),
    ]);
    expect(ordered.map((e) => e.name), ['Y', 'z', 'a2', 'a10', 'b']);
  });

  testWidgets('lists the workspace root with the home abbreviated', (t) async {
    await t.pumpWidget(view());
    await settle(t);
    expect(find.text('~/project'), findsOneWidget);
    final names = [
      for (final e in t.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('files-list')),
          matching: find.byType(Text),
        ),
      ))
        e.data,
    ];
    expect(names, ['Docs', 'src', 'file2.txt', 'file10.txt', 'socket']);
  });

  testWidgets('a directory opens in place and collapses again', (t) async {
    await t.pumpWidget(view());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('dir-/work/project/src')));
    await settle(t);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('inner'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('dir-/work/project/src/inner')));
    await settle(t);
    expect(find.text('Empty directory'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('dir-/work/project/src')));
    await settle(t);
    expect(find.text('main.dart'), findsNothing);
    expect(find.text('Empty directory'), findsNothing);
  });

  testWidgets('a file opens through the sidebar as a session address', (
    t,
  ) async {
    await t.pumpWidget(view());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('dir-/work/project/src')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('file-/work/project/src/main.dart')));
    expect(actions.opened, ['dsh-resource://file/session/s1/src/main.dart']);
  });

  testWidgets('anything that is not a file or directory refuses to open', (
    t,
  ) async {
    await t.pumpWidget(view());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('other-/work/project/socket')));
    expect(actions.opened, isEmpty);
  });

  testWidgets('a change on the watch rereads the directory', (t) async {
    await t.pumpWidget(view());
    await settle(t);
    files.listings['.'] = [file('new.txt')];
    files.watches['/work/project']!.add(
      const WatchChanged(absolutePath: '/work/project', version: 'v2'),
    );
    await t.pump(const Duration(milliseconds: 10));
    await t.pump(const Duration(milliseconds: 200));
    await settle(t);
    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('file2.txt'), findsNothing);
  });

  testWidgets('reload rereads every open directory', (t) async {
    await t.pumpWidget(view());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('dir-/work/project/src')));
    await settle(t);
    files.calls.clear();
    await t.tap(find.byKey(const ValueKey('files-reload')));
    await settle(t);
    expect(files.calls.where((c) => c.startsWith('list')), [
      'list /work/project',
      'list /work/project/src',
    ]);
  });

  testWidgets('a failed listing says why; a failed reread keeps the old rows', (
    t,
  ) async {
    files.failures['/work/project/src'] = RemoteException(
      'workspace-file/not-found',
      'gone',
    );
    await t.pumpWidget(view());
    await settle(t);
    await t.tap(find.byKey(const ValueKey('dir-/work/project/src')));
    await settle(t);
    expect(
      find.text('That directory is gone. It may have been moved or deleted.'),
      findsOneWidget,
    );
    files.failures.clear();
    files.failures['/work/project'] = RemoteException(
      'transport/http-500',
      'boom',
    );
    await t.tap(find.byKey(const ValueKey('files-reload')));
    await settle(t);
    expect(find.text('file2.txt'), findsOneWidget);
    expect(find.text('Read failed: boom'), findsOneWidget);
  });

  testWidgets('truncated listings say so', (t) async {
    files.listings['.'] = WorkspaceDirectoryListing(
      path: '',
      entries: [file('a')],
      truncated: true,
    );
    await t.pumpWidget(view());
    await settle(t);
    expect(
      find.text('Too many entries, showing only some of them.'),
      findsOneWidget,
    );
  });

  testWidgets('no workspace, no tree', (t) async {
    await t.pumpWidget(view(cwd: null));
    expect(find.byKey(const ValueKey('files-no-workspace')), findsOneWidget);
    expect(
      find.text('This session has no workspace directory.'),
      findsOneWidget,
    );
  });

  testWidgets('zh copy', (t) async {
    i18n = const DshI18n(DshLocale.zh);
    files.listings['.'] = <WorkspaceDirectoryEntry>[];
    await t.pumpWidget(view());
    await settle(t);
    expect(find.text('空目录'), findsOneWidget);
  });
}
