import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _Actions implements SidebarTabActions {
  @override
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  }) {}

  @override
  void openResource(
    String address, {
    int? line,
    Map<String, Object?> params = const {},
  }) {}
}

class _Highlighter implements DshCodeHighlighter {
  @override
  List<List<DshCodeSpan>>? highlight(String code, String? lang) => [
    for (final l in code.split('\n'))
      [
        if (l.startsWith('const'))
          const DshCodeSpan('const', DshCodeToken.keyword),
        DshCodeSpan(l.startsWith('const') ? l.substring(5) : l),
      ],
  ];
  @override
  void prepare(String? lang) {}
  @override
  Stream<void> get loaded => const Stream.empty();
}

void main() {
  late FakeWorkspaceFiles files;
  late FakeHostFileActions actions;
  var i18n = const DshI18n(DshLocale.en);

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    files = FakeWorkspaceFiles()..pageLines = 50;
    actions = FakeHostFileActions();
  });

  Widget view(
    String path, {
    int? line,
    int revision = 0,
    bool withFiles = true,
    DshCodeHighlighter? highlighter,
  }) {
    final base = testSessionOwner('s1');
    final owner = SessionOwner(
      session: base.session,
      conversation: base.conversation,
      actions: FakeActions(),
      cwdReader: () => '/work/project',
      hostHome: '/work',
      files: withFiles ? FakeFileServices(files, actions: actions) : null,
    );
    return dshTestApp(
      DshCodeHighlighting(
        highlighter: highlighter,
        child: DocumentView(
          key: ValueKey(path),
          owner: SidebarTabOwner(
            session: owner,
            kind: 'text',
            contentId: fileAddressFor('s1', '/work/project', path),
            actions: _Actions(),
            line: line,
            revision: revision,
          ),
          i18n: i18n,
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump();
  }

  testWidgets('source: numbered lines, coloured, with the path above', (
    t,
  ) async {
    files.texts['src/a.dart'] = 'const a = 1;\nb();\nc();';
    await t.pumpWidget(view('src/a.dart', highlighter: _Highlighter()));
    await settle(t);
    expect(find.byKey(const ValueKey('document-path')), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('code-line-1')),
      findsNothing,
      reason: 'the preview draws its own rows',
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'const a = 1;',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'markdown renders and the viewer menu offers the source and plain text',
    (t) async {
      files.texts['README.md'] = '# Title\n\nSome **bold** text';
      await t.pumpWidget(view('README.md'));
      await settle(t);
      expect(find.textContaining('Title', findRichText: true), findsWidgets);
      expect(find.text('# Title'), findsNothing);
      await t.tap(find.byKey(const ValueKey('viewer-menu')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewer-markdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer-code')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer-text')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('viewer-text')));
      await t.pumpAndSettle();
      expect(find.text('# Title'), findsOneWidget);
      // Plain text needs no second read.
      expect(files.calls.where((c) => c.startsWith('read ')), hasLength(1));
    },
  );

  testWidgets('frontmatter shows in its own box above the body', (t) async {
    files.texts['n.md'] = '---\ntitle: Hi\n---\nBody text';
    await t.pumpWidget(view('n.md'));
    await settle(t);
    expect(find.byKey(const ValueKey('document-frontmatter')), findsOneWidget);
    expect(find.text('title: Hi'), findsOneWidget);
  });

  test('frontmatter splitting follows dsh', () {
    expect(splitFrontmatter('no front\nmatter'), isNull);
    expect(splitFrontmatter('---\na: 1'), isNull);
    final s = splitFrontmatter('﻿---\na: 1\n...\nrest')!;
    expect((s.source, s.body), ('a: 1', 'rest'));
    expect(splitFrontmatter('---\n---\nx')!.source, '');
  });

  testWidgets('the wrap control only exists where it matters', (t) async {
    files.texts['a.dart'] = 'x';
    await t.pumpWidget(view('a.dart'));
    await settle(t);
    expect(find.byKey(const ValueKey('document-wrap')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('document-wrap')));
    await t.pump();
    expect(find.byKey(const ValueKey('document-scroll')), findsOneWidget);
    files.binaries['p.png'] = Uint8List.fromList(base64Decode(_png));
    await t.pumpWidget(view('p.png'));
    await settle(t);
    expect(find.byKey(const ValueKey('document-wrap')), findsNothing);
  });

  testWidgets('images show in a zoomable viewport', (t) async {
    files.binaries['p.png'] = Uint8List.fromList(base64Decode(_png));
    await t.pumpWidget(view('p.png'));
    await settle(t);
    expect(find.byKey(const ValueKey('document-image')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('more pages load on demand', (t) async {
    files.pageLines = 3;
    files.texts['long.txt'] = List.generate(
      8,
      (i) => 'row ${i + 1}',
    ).join('\n');
    await t.pumpWidget(view('long.txt'));
    await settle(t);
    expect(find.text('row 3'), findsOneWidget);
    expect(find.text('row 4'), findsNothing);
    await t.tap(
      find.byKey(const ValueKey('document-more')).evaluate().isEmpty
          ? find.text('Load more')
          : find.text('Load more'),
    );
    await settle(t);
    expect(find.text('row 4'), findsOneWidget);
  });

  testWidgets('a navigated line is marked and brought into view', (t) async {
    files.pageLines = 400;
    files.texts['big.txt'] = List.generate(
      300,
      (i) => 'row ${i + 1}',
    ).join('\n');
    await t.pumpWidget(view('big.txt', line: 200, revision: 1));
    await settle(t);
    await t.pump();
    await t.pump();
    expect(find.text('row 200'), findsOneWidget);
  });

  testWidgets('a binary container is unsupported and offers open and save', (
    t,
  ) async {
    files.binaries['report.pdf'] = Uint8List.fromList(List.filled(2000, 7));
    await t.pumpWidget(view('report.pdf'));
    await t.pump();
    expect(find.byKey(const ValueKey('document-unsupported')), findsOneWidget);
    expect(
      find.text('Preview is not available for this file type yet.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('file-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('file-save')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('file-open')));
    await settle(t);
    await settle(t);
    expect(actions.began, ['report.pdf']);
    expect(actions.opened, ['report.pdf']);
  });

  testWidgets('without file handling the unsupported face offers no actions', (
    t,
  ) async {
    actions = FakeHostFileActions();
    final base = testSessionOwner('s1');
    final owner = SessionOwner(
      session: base.session,
      conversation: base.conversation,
      actions: FakeActions(),
      cwdReader: () => '/w',
      files: FakeFileServices(files),
    );
    await t.pumpWidget(
      dshTestApp(
        DocumentView(
          owner: SidebarTabOwner(
            session: owner,
            kind: 'text',
            contentId: fileAddressFor('s1', '/w', 'a.zip'),
            actions: _Actions(),
          ),
          i18n: i18n,
        ),
      ),
    );
    await t.pump();
    expect(find.byKey(const ValueKey('file-open')), findsNothing);
  });

  testWidgets('failures say what happened and what can be done', (t) async {
    files.failures['gone.txt'] = RemoteException(
      'workspace-file/not-found',
      'x',
    );
    await t.pumpWidget(view('gone.txt'));
    await settle(t);
    expect(
      find.text('File not found. It may have been moved or deleted.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('document-retry')), findsNothing);

    files.failures['big.txt'] = RemoteException(
      'workspace-file/too-large',
      'x',
      {'limit': 2097152},
    );
    await t.pumpWidget(view('big.txt'));
    await settle(t);
    expect(
      find.text('This page exceeds the 2 MB limit and cannot be read.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('file-open')), findsOneWidget);

    files.failures['flaky.txt'] = RemoteException('transport/http-500', 'boom');
    await t.pumpWidget(view('flaky.txt'));
    await settle(t);
    expect(find.text('Read failed: boom'), findsOneWidget);
    files.failures.clear();
    files.texts['flaky.txt'] = 'now fine';
    await t.tap(find.byKey(const ValueKey('document-retry')));
    await settle(t);
    expect(find.text('now fine'), findsOneWidget);
  });

  testWidgets('a binary file read as text offers the system instead', (
    t,
  ) async {
    files.binaries['data.dat'] = Uint8List.fromList([0, 1, 2, 0]);
    await t.pumpWidget(view('data.dat'));
    await settle(t);
    expect(
      find.text('Preview is not available for this file type yet.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('file-open')), findsOneWidget);
  });

  testWidgets(
    'a file observed gone keeps its text under a notice with reload',
    (t) async {
      files.texts['a.txt'] = 'kept';
      await t.pumpWidget(view('a.txt'));
      await settle(t);
      files.watches['a.txt']!.add(
        const WatchChanged(absolutePath: '/work/project/a.txt', absent: true),
      );
      await settle(t);
      expect(
        find.byKey(const ValueKey('document-meta-failed')),
        findsOneWidget,
      );
      expect(find.text('kept'), findsOneWidget);
    },
  );

  testWidgets('reload rereads', (t) async {
    files.texts['a.txt'] = 'one';
    await t.pumpWidget(view('a.txt'));
    await settle(t);
    files.texts['a.txt'] = 'two';
    await t.tap(find.byKey(const ValueKey('document-reload')));
    await settle(t);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('no file service, no preview', (t) async {
    await t.pumpWidget(view('a.txt', withFiles: false));
    expect(find.byKey(const ValueKey('document-unavailable')), findsOneWidget);
  });

  testWidgets('zh copy', (t) async {
    i18n = const DshI18n(DshLocale.zh);
    files.binaries['x.pdf'] = Uint8List(1);
    await t.pumpWidget(view('x.pdf'));
    await t.pump();
    expect(find.text('该格式文件暂时无法预览'), findsOneWidget);
  });
}
