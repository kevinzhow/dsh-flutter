#!/usr/bin/env python3
"""Write the synthetic inputs of the `dsh-input-vector/1` fixture.

    synth_input_vector.py OUT.json      packages/dsh_conversation/test/fixtures/input_vector.json

No recorded content: every string is generic. The expectations are NOT written here: run
`gen_input_expected.py --write` on the output so dsh's own TypeScript code produces them.

detect    every caret of a set of drafts (URLs, emails, quotes, CJK, newlines, punctuation) under the three tiers
atToken   the same drafts through the shared `@` grammar
mention   paths with spaces, quotes, control characters, directories, with and without a preserved quote
rank      candidate lists against queries (prefix, subsequence, label match, CJK, empty, no match)
time      bucket boundaries of the relative time
menu      scripted event traces: open, refine, settle out of order, fail, move, hover, close, auto-close
"""
import json
import sys

DRAFTS = [
    '', '/', '/go', '/goal', '/goal ', '/goal fix', '@', '@wo', '@worker done', 'say /co', 'line1\n/go', '\n\n/goal',
    'see (/go', 'ping @wo', 'user@host', 'a/b', 'foo_1@bar', 'ftp://example', 'see ftp://example', 'ftp://a.b/c/d',
    'C:/path', 'note: /go', ':/go', '/goal @wor', 'args /path', 'read @"docs/design notes', 'read @"docs/design" tail',
    '@"', '@"a b', 'x @"a/b c"', '第一行\n/goal', '你好 @文档', '/计划', '  \n /goal', 'a /goal', '@src/main.dart',
    '@src/', 'mail a@b.c and @x', '//', 'x //y', '(@a', '"@a', 'a:/b', 'tab\t/c', '/a/b', '@a/b/c',
]
TIERS = ['plain', 'claimed', 'frozen']
LINES = ['', '@', '@a', '@"', '@"a b', 'x @a', 'x@a', 'x @"q r', 'x @"q r" @s', '@a b', 'a\t@b', '@a/b', '@你好', 'mail@host @']
PATHS = [
    'a.txt', 'src/main.dart', 'my docs/read me.md', 'dir', 'dir/sub', 'quote".txt', 'tab\there', 'bell\u0007x', 'del\u007fx',
    'c1\u0085x', '文档/说明.md', 'a b/c d', 'x/', '',
]
RANKS = [
    ([{'name': 'goal'}, {'name': 'plan'}, {'name': 'permission'}, {'name': 'compact'}, {'name': 'export'}, {'name': 'feedback'}, {'name': 'model', 'label': '模型'}], q)
    for q in ['', 'p', 'pl', 'go', 'gl', 'ex', 'mo', '模', 'zzz', 'PE', 'f', 'cmp', 'o']
] + [
    ([{'name': 'read-me'}, {'name': 'readme'}, {'name': 'a_readme'}, {'name': 'Read'}, {'name': 'xreadx'}], q)
    for q in ['read', 'rm', 'r-m', 'e', 'READ', 'ra']
]
TIMES = [(0, 0), (0, 59_999), (0, 60_000), (0, 3_599_999), (0, 3_600_000), (0, 86_399_999), (0, 86_400_000),
         (0, 29 * 86_400_000), (0, 30 * 86_400_000), (0, 364 * 86_400_000), (0, 365 * 86_400_000), (0, 800 * 86_400_000),
         (1_000, 0), (5_000_000, 5_000_000 + 125_000)]


def hit(trigger='/', query='', start=0, end=1, quoted=False, position='leading', rev=1):
    return {'trigger': trigger, 'query': query, 'quoted': quoted, 'position': position, 'start': start, 'end': end, 'draftRev': rev}


def menus():
    two = [{'name': 'command', 'showGroupTitle': True}, {'name': 'reference', 'showGroupTitle': False}]
    one = [{'name': 'command', 'showGroupTitle': True}]
    h = hit('/', 'g', 0, 2)
    h2 = hit('/', 'go', 0, 3)
    return [
        {'op': 'menu', 'name': 'open, settle two groups, move wraps', 'sources': two, 'events': [
            {'type': 'seed'}, {'type': 'hit', 'hit': h},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': ['goal', 'plan']},
            {'type': 'settled', 'generation': 1, 'source': 'reference', 'items': ['a.txt']},
            {'type': 'move', 'dir': 1}, {'type': 'move', 'dir': 1}, {'type': 'move', 'dir': 1}, {'type': 'move', 'dir': -1},
            {'type': 'move', 'dir': -1}, {'type': 'exact', 'source': 'command', 'name': 'plan'},
            {'type': 'exact', 'source': 'reference', 'name': 'nope'}, {'type': 'close'}]},
        {'op': 'menu', 'name': 'refinement keeps rows and highlight, stale generation dropped', 'sources': one, 'events': [
            {'type': 'seed'}, {'type': 'hit', 'hit': h},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': ['goal', 'plan', 'permission']},
            {'type': 'move', 'dir': 1}, {'type': 'hit', 'hit': h2},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': ['stale']},
            {'type': 'exact', 'source': 'command', 'name': 'plan'},
            {'type': 'settled', 'generation': 2, 'source': 'command', 'items': ['goal']}]},
        {'op': 'menu', 'name': 'all empty auto-closes', 'sources': two, 'events': [
            {'type': 'seed'}, {'type': 'hit', 'hit': h},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': []},
            {'type': 'settled', 'generation': 1, 'source': 'reference', 'items': []},
            {'type': 'close'}, {'type': 'move', 'dir': 1}]},
        {'op': 'menu', 'name': 'failure removes the group', 'sources': two, 'events': [
            {'type': 'seed'}, {'type': 'hit', 'hit': h},
            {'type': 'failed', 'generation': 1, 'source': 'command'},
            {'type': 'settled', 'generation': 1, 'source': 'reference', 'items': ['x']},
            {'type': 'failed', 'generation': 1, 'source': 'reference'}, {'type': 'failed', 'generation': 9, 'source': 'reference'}]},
        {'op': 'menu', 'name': 'hover parks the highlight only on a ready row', 'sources': two, 'events': [
            {'type': 'seed'}, {'type': 'hit', 'hit': h}, {'type': 'hover', 'source': 'command', 'index': 0},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': ['a', 'b']},
            {'type': 'hover', 'source': 'command', 'index': 1}, {'type': 'hover', 'source': 'command', 'index': 7},
            {'type': 'hover', 'source': 'reference', 'index': 0}, {'type': 'hit', 'hit': None}]},
        {'op': 'menu', 'name': 'the first non-empty group takes the first highlight', 'sources': two, 'events': [
            {'type': 'seed'}, {'type': 'hit', 'hit': h},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': []},
            {'type': 'settled', 'generation': 1, 'source': 'reference', 'items': ['r1', 'r2']},
            {'type': 'move', 'dir': -1}]},
        {'op': 'menu', 'name': 'a new trigger reseeds', 'sources': one, 'events': [
            {'type': 'seed'}, {'type': 'hit', 'hit': h},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': ['a']},
            {'type': 'close'}, {'type': 'seed'}, {'type': 'hit', 'hit': h2},
            {'type': 'settled', 'generation': 1, 'source': 'command', 'items': ['late']},
            {'type': 'settled', 'generation': 2, 'source': 'command', 'items': ['b']}]},
    ]


def cases():
    out = []
    for draft in DRAFTS:
        carets = sorted({0, len(draft), *range(1, len(draft))})
        for caret in carets:
            for tier in TIERS:
                out.append({'op': 'detect', 'draft': draft, 'caret': caret, 'tier': tier})
    for line in LINES:
        for cursor in range(len(line) + 1):
            out.append({'op': 'atToken', 'line': line, 'cursor': cursor})
    for path in PATHS:
        for kind in ('file', 'directory'):
            for keep in (False, True):
                out.append({'op': 'mention', 'path': path, 'kind': kind, 'preserveQuote': keep})
    for items, query in RANKS:
        out.append({'op': 'rank', 'items': items, 'query': query})
    for at, now in TIMES:
        out.append({'op': 'time', 'at': at, 'now': now})
    out.extend(menus())
    return out


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    fixture = {
        'format': 'dsh-input-vector/1',
        'description': 'Trigger detection, the @file grammar, menu reduction, candidate ranking and relative time: the Dart ports must answer every case as the dsh TypeScript does.',
        'cases': cases(),
    }
    with open(sys.argv[1], 'w', encoding='utf-8') as handle:
        handle.write(json.dumps(fixture, ensure_ascii=False))
    print('synth_input_vector: wrote %d cases' % len(fixture['cases']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
