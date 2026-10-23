import 'package:dsh_highlight/dsh_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_source.dart';

/// `token:text` per span ('fg' for the foreground), one string per line.
List<String> show(List<List<HighlightSpan>> lines) => [
  for (final l in lines)
    l
        .map(
          (s) =>
              '${s.token?.name ?? 'fg'}${s.italic ? '/i' : ''}${s.bold ? '/b' : ''}${s.underline ? '/u' : ''}:${s.text}',
        )
        .join('|'),
];

Future<HighlightEngine> load(
  Map<String, Map<String, Object?>> grammars,
  String id, {
  int maxLineLength = 1000,
  Duration limit = Duration.zero,
}) async {
  final e = HighlightEngine(
    MemorySource(grammars),
    maxLineLength: maxLineLength,
    lineTimeLimit: limit,
  );
  await e.load(id);
  return e;
}

Map<String, Object?> grammar(
  String scope,
  List<Object?> patterns, {
  Map<String, Object?>? repository,
  List<String>? embedded,
}) => {
  'name': scope.split('.').last,
  'scopeName': scope,
  'patterns': patterns,
  if (repository != null) 'repository': repository,
  if (embedded != null) 'embeddedLangs': embedded,
};

void main() {
  group('match rules and captures', () {
    test('keywords, numbers and line comments', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'match': r'\b(if|else)\b', 'name': 'keyword.control.mini'},
          {'match': r'\b\d+\b', 'name': 'constant.numeric.mini'},
          {'match': r'//.*$', 'name': 'comment.line.mini'},
        ]),
      }, 'mini');
      expect(show(e.highlightLines('if 12 x // note', 'mini')!), [
        'keyword:if|fg: |constant:12|fg: x |comment:// note',
      ]);
    });

    test('capture groups get their own scopes; empty and unset groups skipped', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {
            'match': r'(\w+)(=)(\d+)?(x)?',
            'captures': {
              '1': {'name': 'variable.parameter.function.mini'},
              '2': {'name': 'punctuation.separator.mini'},
              '3': {'name': 'constant.numeric.mini'},
              '4': {'name': 'keyword.mini'},
            },
          },
        ]),
      }, 'mini');
      expect(show(e.highlightLines('key=7 a=', 'mini')!), [
        'parameter:key|punctuation:=|constant:7|fg: |parameter:a|punctuation:=',
      ]);
    });

    test(
      'a capture with patterns retokenizes its text; captures nest',
      () async {
        final e = await load({
          'mini': grammar('source.mini', [
            {
              'match': r'\[(a b)\]',
              'captures': {
                '1': {
                  'name': 'string.quoted.mini',
                  'patterns': [
                    {'match': 'a', 'name': 'keyword.mini'},
                  ],
                },
              },
            },
          ]),
        }, 'mini');
        expect(show(e.highlightLines('[a b]', 'mini')!), [
          'fg:[|keyword:a|stringExpression: b|fg:]',
        ]);
      },
    );

    test(r'$1 in a scope name is replaced by the capture', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'match': r'#(comment|keyword)\b', 'name': r'${1:/downcase}.mini'},
        ]),
      }, 'mini');
      expect(show(e.highlightLines('#comment #keyword', 'mini')!), [
        'comment:#comment|fg: |keyword:#keyword',
      ]);
    });
  });

  group('begin / end / while', () {
    final block = {
      'mini': grammar('source.mini', [
        {
          'begin': r'/\*',
          'end': r'\*/',
          'name': 'comment.block.mini',
          'contentName': 'comment.content.mini',
        },
        {'match': r'\bx\b', 'name': 'keyword.mini'},
      ]),
    };

    test('a block spans lines and keeps its state', () async {
      final e = await load(block, 'mini');
      expect(show(e.highlightLines('x /* a x\nx b */ x', 'mini')!), [
        'keyword:x|fg: |comment:/* a x',
        'comment:x b */|fg: |keyword:x',
      ]);
    });

    test('state does not leak between calls', () async {
      final e = await load(block, 'mini');
      e.highlightLines('/* open', 'mini');
      expect(show(e.highlightLines('x', 'mini')!), ['keyword:x']);
    });

    test('begin/end captures and nested patterns', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {
            'begin': r'(")',
            'end': r'(")',
            'beginCaptures': {
              '1': {'name': 'punctuation.separator.mini'},
            },
            'endCaptures': {
              '1': {'name': 'keyword.mini'},
            },
            'name': 'string.quoted.double.mini',
            'patterns': [
              {'match': r'\\.', 'name': 'constant.numeric.escape.mini'},
            ],
          },
        ]),
      }, 'mini');
      expect(show(e.highlightLines(r'"a\"b"', 'mini')!), [
        r'punctuation:"|stringExpression:a|constant:\"|stringExpression:b|keyword:"',
      ]);
    });

    test('end pattern with a backreference to the begin capture', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {
            'begin': r'<<(\w+)$',
            'end': r'^\1$',
            'name': 'string.unquoted.heredoc.mini',
          },
        ]),
      }, 'mini');
      expect(show(e.highlightLines('<<EOT\nbody\nEOT\nafter', 'mini')!), [
        'string:<<EOT',
        'string:body',
        'string:EOT',
        'fg:after',
      ]);
      // A different terminator does not end it.
      expect(show(e.highlightLines('<<A\nB\nA', 'mini')!), [
        'string:<<A',
        'string:B',
        'string:A',
      ]);
    });

    test('backreference text is escaped, not treated as regex', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'begin': r'(\S+)<', 'end': r'>\1', 'name': 'string.quoted.mini'},
        ]),
      }, 'mini');
      expect(show(e.highlightLines('a.b<x>a.b y', 'mini')!), [
        'stringExpression:a.b<x>a.b|fg: y',
      ]);
      expect(show(e.highlightLines('a.b<x>aXb', 'mini')!), [
        'stringExpression:a.b<x>aXb',
      ]);
    });

    test('applyEndPatternLast lets inner patterns win ties', () async {
      Map<String, Map<String, Object?>> make(bool last) => {
        'mini': grammar('source.mini', [
          {
            'begin': r'\[',
            'end': r'\]',
            if (last) 'applyEndPatternLast': 1,
            'name': 'string.quoted.mini',
            'patterns': [
              {'match': r'\]', 'name': 'keyword.inner.mini'},
            ],
          },
        ]),
      };
      final normal = await load(make(false), 'mini');
      expect(show(normal.highlightLines('[a] b', 'mini')!), [
        'stringExpression:[a]|fg: b',
      ]);
      final last = await load(make(true), 'mini');
      expect(show(last.highlightLines('[a] b', 'mini')!), [
        'stringExpression:[a|keyword:]|stringExpression: b',
      ]);
    });

    test('while rules continue only while their pattern matches', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'begin': r'^>', 'while': r'^>', 'name': 'string.quoted.quote.mini'},
          {'match': r'\bx\b', 'name': 'keyword.mini'},
        ]),
      }, 'mini');
      expect(show(e.highlightLines('> a x\n> b\nx', 'mini')!), [
        'stringExpression:> a x',
        'stringExpression:> b',
        'keyword:x',
      ]);
    });
  });

  group('includes', () {
    test(r'$self, #repository and nested repositories', () async {
      final e = await load({
        'mini': grammar(
          'source.mini',
          [
            {'include': '#paren'},
            {'match': r'\bx\b', 'name': 'keyword.mini'},
          ],
          repository: {
            'paren': {
              'begin': r'\(',
              'end': r'\)',
              'name': 'string.quoted.mini',
              'patterns': [
                {'include': r'$self'},
              ],
            },
          },
        ),
      }, 'mini');
      expect(show(e.highlightLines('(x (x) x) x', 'mini')!), [
        'stringExpression:(|keyword:x|stringExpression: (|keyword:x|stringExpression:) |keyword:x|stringExpression:)|fg: |keyword:x',
      ]);
    });

    test('another grammar by scope name, with and without a rule', () async {
      final grammars = {
        'host': grammar(
          'source.host',
          [
            {'include': 'source.other'},
            {'match': r'\bh\b', 'name': 'keyword.host'},
          ],
          embedded: ['other'],
        ),
        'other': grammar(
          'source.other',
          [
            {'match': r'\bo\b', 'name': 'constant.numeric.other'},
          ],
          repository: {
            'only': {'match': r'\bz\b', 'name': 'comment.only'},
          },
        ),
        'host2': grammar(
          'source.host2',
          [
            {'include': 'source.other#only'},
          ],
          embedded: ['other'],
        ),
      };
      final e = await load(grammars, 'host');
      expect(e.isLoaded('other'), isTrue, reason: 'embedded grammar loaded');
      expect(show(e.highlightLines('h o z', 'host')!), [
        'keyword:h|fg: |constant:o|fg: z',
      ]);
      await e.load('host2');
      expect(show(e.highlightLines('o z', 'host2')!), ['fg:o |comment:z']);
    });

    test(r'$base in an embedded grammar refers to the host', () async {
      final e = await load({
        'host': grammar(
          'source.host',
          [
            {
              'begin': r'\{',
              'end': r'\}',
              'name': 'string.quoted.host',
              'patterns': [
                {'include': 'source.inner'},
              ],
            },
            {'match': r'\bh\b', 'name': 'keyword.host'},
          ],
          embedded: ['inner'],
        ),
        'inner': grammar('source.inner', [
          {'include': r'$base'},
        ]),
      }, 'host');
      // Inside braces the inner grammar includes the host's patterns again.
      expect(show(e.highlightLines('{h {h}}', 'host')!), [
        'stringExpression:{|keyword:h|stringExpression: {|keyword:h|stringExpression:}}',
      ]);
    });

    test('a missing include is ignored', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'include': 'source.nothing'},
          {'include': '#nope'},
          {'match': 'a', 'name': 'keyword.mini'},
        ]),
      }, 'mini');
      expect(show(e.highlightLines('a', 'mini')!), ['keyword:a']);
    });
  });

  group('injections', () {
    test('injection selectors with exclusion and priority', () async {
      final e = await load({
        'mini': {
          ...grammar('source.mini', [
            {'begin': '"', 'end': '"', 'name': 'string.quoted.mini'},
          ]),
          'injections': {
            'source.mini - string': {
              'patterns': [
                {'match': r'\bTODO\b', 'name': 'comment.todo.mini'},
              ],
            },
          },
        },
      }, 'mini');
      expect(show(e.highlightLines('TODO "TODO"', 'mini')!), [
        'comment:TODO|fg: |stringExpression:"TODO"',
      ]);
    });
  });

  group('guards and failure modes', () {
    test('lines of maxLineLength or more are one uncoloured span', () async {
      final e = await load(
        {
          'mini': grammar('source.mini', [
            {'match': r'\bx\b', 'name': 'keyword.mini'},
          ]),
        },
        'mini',
        maxLineLength: 20,
      );
      final long = 'x ' * 10; // 20 units
      expect(e.highlightLines(long, 'mini'), [
        [HighlightSpan(long)],
      ]);
      expect(show(e.highlightLines('${'x ' * 9}x', 'mini')!), [
        'keyword:x|fg: |keyword:x|fg: |keyword:x|fg: |keyword:x|fg: |keyword:x|fg: |keyword:x|fg: |keyword:x|fg: |keyword:x|fg: |keyword:x|fg: |keyword:x',
      ]);
    });

    test('the default guard is 1000 UTF-16 units', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'match': r'\bx\b', 'name': 'keyword.mini'},
        ]),
      }, 'mini');
      final just = '${'x ' * 499}x'; // 999 units: coloured
      final over = '${'x ' * 499}xx'; // 1000 units: not
      expect(e.highlightLines(just, 'mini')!.single.length, greaterThan(1));
      expect(e.highlightLines(over, 'mini'), [
        [HighlightSpan(over)],
      ]);
    });

    test('a skipped long line leaves the grammar state unchanged', () async {
      final e = await load(
        {
          'mini': grammar('source.mini', [
            {'begin': r'/\*', 'end': r'\*/', 'name': 'comment.block.mini'},
          ]),
        },
        'mini',
        maxLineLength: 12,
      );
      // The long line closes the comment, but it is skipped: the comment stays
      // open for the next line.
      final lines = e.highlightLines('/* a\n*/ aaaaaaaaaaaa\nb', 'mini')!;
      expect(show(lines), ['comment:/* a', 'fg:*/ aaaaaaaaaaaa', 'comment:b']);
    });

    test('empty lines are empty lists; a trailing newline adds none', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'match': 'a', 'name': 'keyword.mini'},
        ]),
      }, 'mini');
      expect(e.highlightLines('a\n\na\n', 'mini')!.map((l) => l.length), [
        1,
        0,
        1,
      ]);
      expect(e.highlightLines('', 'mini'), [<HighlightSpan>[]]);
      expect(show(e.highlightLines('a\r\na', 'mini')!), [
        'keyword:a',
        'keyword:a',
      ]);
    });

    test('concatenated spans equal the line, including unicode', () async {
      final e = await load({
        'mini': grammar('source.mini', [
          {'match': r'\w+', 'name': 'keyword.mini'},
        ]),
      }, 'mini');
      const line = 'héllo 日本語 😀 x';
      final spans = e.highlightLines(line, 'mini')!.single;
      expect(spans.map((s) => s.text).join(), line);
    });

    test('unsupported and not-yet-loaded grammars return null', () async {
      final source = MemorySource({
        'mini': grammar('source.mini', [
          {'match': 'a', 'name': 'keyword.mini'},
        ]),
      });
      final e = HighlightEngine(source);
      expect(e.highlightLines('a', 'mini'), isNull, reason: 'not loaded yet');
      expect(e.highlightLines('a', 'nope'), isNull, reason: 'unsupported');
      await e.load('nope'); // unknown ids complete quietly
      expect(e.isLoaded('nope'), isFalse);
      expect(e.loadCount, 0);
      await e.load('mini');
      expect(e.highlightLines('a', 'mini'), isNotNull);
    });

    test(
      'load is idempotent and single flight; loaded fires per load',
      () async {
        final source = MemorySource({
          'a': grammar('source.a', [], embedded: ['b']),
          'b': grammar('source.b', []),
        });
        final e = HighlightEngine(source);
        var fired = 0;
        final sub = e.loaded.listen((_) => fired++);
        await Future.wait([e.load('a'), e.load('a'), e.load('a')]);
        await e.load('a');
        await Future<void>.delayed(Duration.zero);
        expect(source.reads, {'a': 1, 'b': 1});
        expect(e.isLoaded('a'), isTrue);
        expect(e.isLoaded('b'), isTrue);
        expect(e.loadCount, 1);
        expect(fired, 1);
        await e.load('b'); // already there
        expect(e.loadCount, 1);
        await sub.cancel();
      },
    );

    test(
      'a grammar that fails to read stays unloaded and can be retried',
      () async {
        var fail = true;
        final inner = MemorySource({
          'a': grammar('source.a', [
            {'match': 'a', 'name': 'keyword.a'},
          ]),
        });
        final e = HighlightEngine(_Flaky(inner, () => fail));
        await e.load('a');
        expect(e.isLoaded('a'), isFalse);
        expect(e.failedLoads, {'a'});
        fail = false;
        await e.load('a');
        expect(e.isLoaded('a'), isTrue);
        expect(e.failedLoads, isEmpty);
      },
    );

    test(
      'an untranslatable pattern degrades to never matching, counted',
      () async {
        final e = await load({
          'mini': grammar('source.mini', [
            {'match': r'(?(1)a|b)', 'name': 'keyword.bad.mini'},
            {'match': r'[\d-z]', 'name': 'keyword.bad2.mini'},
            {'match': 'ok', 'name': 'keyword.mini'},
          ]),
        }, 'mini');
        expect(show(e.highlightLines('ok a b 1', 'mini')!), [
          'keyword:ok|fg: a b 1',
        ]);
        expect(e.degradedPatternCount, 2);
        final stats = e.patternStats('mini')!;
        expect(stats.unique, 3);
        expect(stats.degraded, 2);
        expect(stats.translated, 1);
      },
    );

    test('the per-line time limit keeps the tokens so far', () async {
      final e = await load(
        {
          'slow': grammar('source.slow', [
            // Catastrophic backtracking, searched first on every scan.
            {'match': r'(?:a|aa)+c$'},
            {'match': r'\w', 'name': 'keyword.mini'},
          ]),
        },
        'slow',
        limit: const Duration(milliseconds: 1),
      );
      final line = '${'a' * 34}b';
      final spans = e.highlightLines(line, 'slow')!.single;
      expect(spans.map((s) => s.text).join(), line);
      expect(e.timedOutLines, 1);
    });
  });
}

class _Flaky implements GrammarSource {
  _Flaky(this.inner, this.shouldFail);
  final GrammarSource inner;
  final bool Function() shouldFail;
  @override
  Set<String> get available => inner.available;
  @override
  Future<String> read(String id) {
    if (shouldFail()) throw StateError('disk on fire');
    return inner.read(id);
  }
}
