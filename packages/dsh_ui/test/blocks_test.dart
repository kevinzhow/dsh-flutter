import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
  theme: ThemeData(
    extensions: [
      resolveTheme(
        officialPack,
        ThemeSettings(
          preference: b == Brightness.dark
              ? ThemePreference.dark
              : ThemePreference.light,
        ),
        Brightness.light,
      ),
    ],
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

const labels = DshTerminalLabels(
  commandLine: _line,
  signal: _signal,
  exitCode: _exit,
  noExitCode: 'no exit code',
  running: 'running',
  failed: 'failed',
  done: 'done',
  copy: 'Copy',
  copied: 'Copied',
  noOutput: 'no output',
  collapse: 'Collapse',
  expand: _expand,
);
String _line(int n) => 'command line $n';
String _signal(String s) => 'signal $s';
String _exit(int c) => 'exit code $c';
String _expand(int n) => '… $n more';

const toolbar = DshCodeToolbarLabels(
  codeLabel: 'Code',
  wrapLabel: 'Wrap',
  unwrapLabel: 'Unwrap',
  copy: 'Copy',
  copied: 'Copied',
);

void main() {
  group('terminal block', () {
    testWidgets('a clean settle shows the output and a copy action', (t) async {
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'ls -la',
            cwd: '/home/u/project',
            home: '/home/u',
            output: 'a\nb\n',
            exitCode: 0,
            labels: labels,
          ),
        ),
      );
      expect(find.text('project'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.byKey(const ValueKey('terminal-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('terminal-status')), findsNothing);
    });

    testWidgets('home prompts as ~, no cwd as a dollar sign', (t) async {
      expect(terminalPromptLabel('/home/u/', '/home/u'), '~');
      expect(terminalPromptLabel(r'C:\w\app', null), 'app');
      await t.pumpWidget(
        host(const DshTerminalBlock(command: 'x', output: 'y', labels: labels)),
      );
      expect(find.text(r'$'), findsOneWidget);
    });

    testWidgets('a failed exit shows the capsule', (t) async {
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'false',
            output: 'oops',
            exitCode: 2,
            labels: labels,
          ),
        ),
      );
      expect(find.text('exit code 2'), findsOneWidget);
    });

    testWidgets('a signal and a missing code each name themselves', (t) async {
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'sleep',
            signal: 'SIGKILL',
            labels: labels,
          ),
        ),
      );
      expect(find.text('signal SIGKILL'), findsOneWidget);
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'x',
            exitCodeMissing: true,
            labels: labels,
          ),
        ),
      );
      expect(find.text('no exit code'), findsOneWidget);
    });

    testWidgets('running with no output is the prompt line alone', (t) async {
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'sleep 9',
            running: true,
            labels: labels,
          ),
        ),
      );
      expect(find.text('sleep 9'), findsOneWidget);
      expect(find.text('no output'), findsNothing);
      expect(find.byKey(const ValueKey('terminal-copy')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a settled command with no output says so', (t) async {
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'true',
            output: '',
            exitCode: 0,
            labels: labels,
          ),
        ),
      );
      expect(find.text('no output'), findsOneWidget);
    });

    testWidgets('a background launch keeps only the command', (t) async {
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'server',
            background: true,
            labels: labels,
          ),
        ),
      );
      expect(find.text('server'), findsOneWidget);
      expect(find.byKey(const ValueKey('terminal-copy')), findsNothing);
    });

    testWidgets('a long output folds its middle and expands', (t) async {
      final output = [for (var i = 1; i <= 30; i++) 'line $i'].join('\n');
      await t.pumpWidget(
        host(
          DshTerminalBlock(
            command: 'seq',
            output: output,
            exitCode: 0,
            maxLines: 6,
            outputMaxHeight: 5000,
            labels: labels,
          ),
        ),
      );
      expect(find.text('line 3'), findsOneWidget);
      expect(find.text('line 4'), findsNothing);
      expect(find.text('… 24 more'), findsOneWidget);
      expect(find.text('line 30'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('terminal-expand')));
      await t.pump();
      expect(find.text('line 4'), findsOneWidget);
      expect(find.text('Collapse'), findsOneWidget);
    });

    testWidgets('copy confirms for a second', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await t.pumpWidget(
        host(
          const DshTerminalBlock(
            command: 'x',
            output: 'y',
            exitCode: 0,
            labels: labels,
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('terminal-copy')));
      await t.pump();
      await t.pump();
      expect(copied, 'y');
      expect(find.text('Copied'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets(
      'multi-line commands get a row each, only the first with the cwd',
      (t) async {
        await t.pumpWidget(
          host(
            const DshTerminalBlock(
              command: 'cd a\nmake',
              cwd: '/w/app',
              output: 'ok',
              exitCode: 0,
              labels: labels,
            ),
          ),
        );
        expect(find.text('app'), findsOneWidget);
        expect(find.text(r'$'), findsOneWidget);
      },
    );
  });

  group('diff block', () {
    const fold = DshFoldLabels(collapse: 'Collapse', expand: _expand);
    testWidgets('rows carry their prefixes and the language label', (t) async {
      await t.pumpWidget(
        host(
          const DshDiffBlock(
            diffs: [
              DshDiffHunk(
                path: 'src/app.ts',
                oldText: 'a\nold\nb\n',
                newText: 'a\nnew\nb\n',
              ),
            ],
            toolbar: toolbar,
            fold: fold,
          ),
        ),
      );
      expect(find.text('typescript'), findsOneWidget);
      expect(find.text('src/app.ts'), findsOneWidget);
      expect(find.text('- old'), findsOneWidget);
      expect(find.text('+ new'), findsOneWidget);
      expect(find.text('  a'), findsOneWidget);
    });

    testWidgets('an unknown language reads the generic label', (t) async {
      await t.pumpWidget(
        host(
          const DshDiffBlock(
            diffs: [
              DshDiffHunk(path: 'notes.xyz', oldText: null, newText: 'n\n'),
            ],
            toolbar: toolbar,
            fold: fold,
          ),
        ),
      );
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('+ n'), findsOneWidget);
    });

    testWidgets('a tall diff folds past maxLines', (t) async {
      final text = [for (var i = 0; i < 40; i++) 'l$i'].join('\n');
      await t.pumpWidget(
        host(
          DshDiffBlock(
            diffs: [DshDiffHunk(path: 'a.dart', oldText: null, newText: text)],
            toolbar: toolbar,
            fold: fold,
            maxLines: 9,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('diff-fold')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('diff-fold')));
      await t.pump();
      expect(find.text('+ l20'), findsOneWidget);
    });

    test('translucent fills blend like Chromium', () {
      // 8% (alpha 20) of a red over the light card colour.
      final c = blendLikeChromium(
        const Color(0x14EC1313),
        const Color(0xFFF9FAFB),
      );
      expect(
        ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()),
        (248, 231, 232),
      );
    });

    test('the menu surface lands where Chromium put it over a saturated page', () {
      // `saturate(150%)` lifts the dark page (21, 21, 23) to (21, 21, 24); the
      // 45% menu fill over that is dsh's panel colour.
      final under = saturateLikeChromium(const Color(0xFF151517), 1.5);
      final c = blendLikeChromium(const Color(0x7343454A), under);
      expect(
        ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()),
        (41, 42, 46),
      );
      // White stays white.
      expect(
        saturateLikeChromium(const Color(0xFFFFFFFF), 1.5),
        const Color(0xFFFFFFFF),
      );
    });
  });

  group('read block', () {
    const labelsRead = DshReadLabels(
      toolbar: toolbar,
      fold: DshFoldLabels(collapse: 'Collapse', expand: _expand),
      window: _window,
    );
    testWidgets('numbers its lines, shows the path and the window note', (
      t,
    ) async {
      await t.pumpWidget(
        host(
          const DshReadBlock(
            label: 'src/a.dart',
            lang: 'dart',
            totalLines: 200,
            lines: [DshReadLine(10, 'void main() {}'), DshReadLine(11, '}')],
            labels: labelsRead,
          ),
        ),
      );
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('src/a.dart'), findsOneWidget);
      expect(find.text('2 of 200'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('void main() {}'), findsOneWidget);
    });

    testWidgets('a whole file has no window note and an empty one no copy', (
      t,
    ) async {
      await t.pumpWidget(
        host(const DshReadBlock(lines: [], totalLines: 0, labels: labelsRead)),
      );
      expect(find.byKey(const ValueKey('code-copy')), findsNothing);
      expect(find.textContaining(' of '), findsNothing);
    });
  });

  group('search block', () {
    const labelsSearch = DshSearchLabels(
      pathsSummary: _paths,
      matchesSummary: _matches,
      copy: 'Copy',
      copied: 'Copied',
      noResults: 'No results',
      collapse: 'Collapse',
      expand: _expand,
    );
    testWidgets('grep groups collapse per file', (t) async {
      await t.pumpWidget(
        host(
          const DshSearchBlock.matches(
            files: [
              DshSearchFile('a.dart', [
                DshSearchMatch(3, 'foo()'),
                DshSearchMatch(9, 'foo(1)'),
              ]),
              DshSearchFile('b.dart', [DshSearchMatch(1, 'foo')]),
            ],
            truncated: false,
            total: 3,
            labels: labelsSearch,
          ),
        ),
      );
      expect(find.text('3 matches in 2 files'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
      expect(find.textContaining('foo()'), findsOneWidget);
      await t.tap(find.text('a.dart'));
      await t.pump();
      expect(find.textContaining('foo()'), findsNothing);
      expect(find.textContaining('foo'), findsWidgets);
    });

    testWidgets('glob lists paths; empty says so; truncated says so', (
      t,
    ) async {
      await t.pumpWidget(
        host(
          const DshSearchBlock.paths(
            paths: ['a.dart', 'b.dart'],
            truncated: true,
            total: 50,
            labels: labelsSearch,
          ),
        ),
      );
      expect(find.text('2 of 50 paths (truncated)'), findsOneWidget);
      await t.pumpWidget(
        host(
          const DshSearchBlock.paths(
            paths: [],
            truncated: false,
            total: 0,
            labels: labelsSearch,
          ),
        ),
      );
      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('a long list folds and expands', (t) async {
      await t.pumpWidget(
        host(
          DshSearchBlock.paths(
            paths: [for (var i = 0; i < 30; i++) 'p$i'],
            truncated: false,
            total: 30,
            maxLines: 8,
            labels: labelsSearch,
          ),
        ),
      );
      expect(find.text('p3'), findsOneWidget);
      expect(find.text('p4'), findsNothing);
      await t.tap(find.byKey(const ValueKey('search-fold')));
      await t.pump();
      expect(find.text('p4'), findsOneWidget);
    });
  });

  group('web block', () {
    const labelsWeb = DshWebLabels(
      noResults: 'No results',
      sourcesTruncated: 'More sources',
      http: 'HTTP',
      contentTruncated: 'Content truncated',
    );
    testWidgets('search sources link out through the host', (t) async {
      Uri? opened;
      await t.pumpWidget(
        host(
          DshWebBlock.search(
            answer: 'Short **answer**.',
            sources: const [
              DshWebSource(
                url: 'https://example.com/a',
                title: 'Example A',
                snippet: 'about a',
                publishedAt: '2026-01-01',
              ),
              DshWebSource(url: 'javascript:alert(1)', title: 'Unsafe'),
            ],
            truncated: true,
            labels: labelsWeb,
            onOpenUrl: (u) => opened = u,
          ),
        ),
      );
      expect(find.textContaining('Example A'), findsOneWidget);
      expect(find.text('about a'), findsOneWidget);
      expect(find.text('More sources'), findsOneWidget);
      expect(safeWebUri('javascript:alert(1)'), isNull);
      expect(safeWebUri('https://example.com')?.host, 'example.com');
      expect(opened, isNull);
    });

    testWidgets('fetch shows the status and truncation', (t) async {
      await t.pumpWidget(
        host(
          DshWebBlock.fetch(
            url: 'https://example.com/page',
            statusCode: 200,
            truncated: true,
            labels: labelsWeb,
            onOpenUrl: (_) {},
          ),
        ),
      );
      expect(find.text('HTTP 200'), findsOneWidget);
      expect(find.text('Content truncated'), findsOneWidget);
    });

    testWidgets('an empty search says so', (t) async {
      await t.pumpWidget(
        host(
          DshWebBlock.search(
            sources: const [],
            truncated: false,
            labels: labelsWeb,
            onOpenUrl: (_) {},
          ),
        ),
      );
      expect(find.text('No results'), findsOneWidget);
    });
  });

  group('chrome', () {
    testWidgets('the disclosure row toggles and the state dot paints', (
      t,
    ) async {
      var toggles = 0;
      await t.pumpWidget(
        host(
          Column(
            children: [
              DshDisclosureRow(
                icon: DshIcons.api,
                title: 'Bash',
                open: false,
                expandable: true,
                onToggle: () => toggles++,
              ),
              const DshStateDot(DshStateDotState.done),
              const DshStateDot(DshStateDotState.error),
              const DshStateDot(DshStateDotState.idle),
              const DshPill(child: Text('exit code 1')),
            ],
          ),
        ),
      );
      await t.tap(find.text('Bash'));
      expect(toggles, 1);
      expect(find.text('exit code 1'), findsOneWidget);
    });

    testWidgets('the spinner animates unless animations are off', (t) async {
      await t.pumpWidget(host(const DshStateDot(DshStateDotState.ongoing)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(DshStateDot), findsOneWidget);
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(const DshStateDot(DshStateDotState.ongoing)),
        ),
      );
      await t.pumpAndSettle();
    });

    testWidgets('every generated icon paints', (t) async {
      final icons = [
        DshIcons.api,
        DshIcons.edit,
        DshIcons.browse,
        DshIcons.search,
        DshIcons.globe,
        DshIcons.checklist,
        DshIcons.question,
        DshIcons.sparkle,
        DshIcons.code,
        DshIcons.chevronDown,
        DshIcons.chevronUp,
        DshIcons.chevronRight,
        DshIcons.inspect,
        DshIcons.copy,
        DshIcons.check,
        DshIcons.wrap,
        DshIcons.nowrap,
        DshIcons.play,
        DshIcons.users,
        DshIcons.clock,
        DshIcons.goal,
        DshIcons.branch,
        DshIcons.agentPreset,
        DshIcons.cordisPlugin,
        DshIcons.plan,
      ];
      await t.pumpWidget(
        host(
          Wrap(
            children: [
              for (final i in icons) DshIcon(i, color: Colors.black),
              const DshMarkdownFileIcon(),
            ],
          ),
        ),
      );
      expect(find.byType(DshIcon), findsNWidgets(icons.length));
    });

    testWidgets('the shadow box keeps shadows outside a translucent fill', (
      t,
    ) async {
      await t.pumpWidget(
        host(
          const DshShadowBox(
            color: Color(0x80FFFFFF),
            radius: 12,
            shadows: [BoxShadow(blurRadius: 8, color: Color(0x40000000))],
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      );
      expect(find.byType(DshShadowBox), findsOneWidget);
    });
  });
}

String _window(int shown, int total) => '$shown of $total';
String _paths(int shown, int total, bool truncated) =>
    '$shown of $total paths${truncated ? ' (truncated)' : ''}';
String _matches(int shown, int total, int files, bool truncated) =>
    '$shown matches in $files files';
