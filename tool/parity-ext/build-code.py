#!/usr/bin/env python3
"""Code surfaces: the highlighted code card (CodeBlock) and the file window of a read result (ReadBlock).

React host: host/code.tsx mounts dsh's real CodeBlock (card form, with the toolbar) and ReadBlock with dsh's real shiki
highlighter and ui-tool's own label adapters. Flutter: tool/parity_flutter/test/parity/cases/code.dart renders DshCodeBlock
and DshReadBlock with DshSyntaxHighlighter (package dsh_highlight) over the real grammars. Kinds and props:

  code.block   {layout, blocks: [{id, code, lang?, lineNumbers?, wrap?}]}; `wrap` omitted keeps the card's own wrap
               toggle (a markdown fence's form). Parity ids: code-wrap, code-copy (single-block cases only click them)
  code.read    {layout, block: {label?, lang?, lines: [{number, text}], totalLines, maxLines?}}; parity ids: read-block,
               code-wrap, read-fold

Ids: components.code.<surface>.<name>.<theme>. All content is invented source text.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402
from parity_lib import fonts  # noqa: E402

ORDER = 410
PRIM = 'packages/client/ui-primitives/src/'
PHONE = 390
LAYOUT = {'direction': 'column', 'gap': 12, 'align': 'stretch'}

TS = """import { load } from './config'

interface Settings {
  port: number
  verbose?: boolean
}

export async function start(settings: Settings): Promise<void> {
  const server = await listen(settings.port, { backlog: 128, label: 'primary-http-listener' })
  console.log(`listening on ${server.address} (verbose: ${settings.verbose ?? false})`)
}
"""

PY = """import json
from dataclasses import dataclass


@dataclass
class Settings:
    port: int = 8080
    verbose: bool = False


def load(path: str) -> Settings:
    \"\"\"Read the settings file; missing keys keep their defaults.\"\"\"
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    return Settings(**{k: v for k, v in data.items() if k in Settings.__annotations__})


if __name__ == '__main__':
    print(load('settings.json'))
"""

MD = """# Release notes

Run the **install** step, then start the app:

```bash
npm install && npm test
```

- [x] Fix the parser
- [ ] Update the [docs](https://example.com/docs)

> Remember to tag the release.
"""

TEXT = """Plain notes without a language:
  first line, indented by two spaces
  second line that is long enough to wrap onto another row of the card

done.
"""

ZH_TS = """// 读取设置并启动服务
export async function start(settings: Settings): Promise<void> {
  const server = await listen(settings.port, { label: '主要服务' })
  console.log(`服务已启动，端口 ${server.port}`)
}
"""

READ_TS = """export function pad(value: number, width = 2): string {
  return String(value).padStart(width, '0')
}

export function formatTime(date: Date): string {
  const hours = pad(date.getHours())
  const minutes = pad(date.getMinutes())
  return `${hours}:${minutes}`
}

export const SEPARATOR = ':'
"""


def lines_of(text, first=1):
    return [{'number': first + i, 'text': line} for i, line in enumerate(text.rstrip('\n').split('\n'))]


def block(block_id, code, lang=None, line_numbers=False, wrap=None):
    item = {'id': block_id, 'code': code}
    if lang:
        item['lang'] = lang
    if line_numbers:
        item['lineNumbers'] = True
    if wrap is not None:
        item['wrap'] = wrap
    return item


# Frame heights: the bottom of the card in the React capture plus the frame's 16px margin (the expanded read block
# is the tallest state of its case; the unwrapped cases need the wrapped height too, because the card starts wrapped).
BLOCK_HEIGHT = {'typescript-wrapped': 366, 'typescript-numbered': 404, 'typescript-unwrapped': 366, 'python-numbered-many': 537, 'markdown-fence': 347, 'plain-text': 214, 'numbered-unwrapped': 404, 'zh-cn': 252}
READ_HEIGHT = {'window-ts': 309, 'python-full': 423, 'capped-long': 575, 'wrapped': 366, 'plain-text': 195, 'zh-cn': 195}


def block_case(name, title, blocks, interactions=None, locale='en'):
    props = {'layout': LAYOUT, 'blocks': blocks}
    return themed(base_case('components.code.block.' + name, title, 'code.block',
                            {'width': PHONE, 'height': BLOCK_HEIGHT[name], 'density': 2},
                            [('default', 'Default', props, interactions)], locale=locale,
                            category='extension/code', react_hint=PRIM + 'markdown/CodeBlock.tsx'))


# The pointer leaves the toolbar after the click (it would keep the hover tint and the tooltip of the pressed action).
WRAP_CLICK = [{'type': 'click', 'target': 'code-wrap'}, {'type': 'hover', 'target': 'code-block'}]
cases = block_case('typescript-wrapped', 'TypeScript card, wrapped (the fence default)', [block('b', TS, 'typescript')])
cases += block_case('typescript-numbered', 'TypeScript card with line numbers', [block('b', TS, 'typescript', True)])
cases += block_case('typescript-unwrapped', 'TypeScript card after the wrap toggle', [block('b', TS, 'typescript')],
                    WRAP_CLICK)
cases += block_case('python-numbered-many', 'Python card with line numbers, ten and more lines',
                    [block('b', PY, 'python', True)])
cases += block_case('markdown-fence', 'Markdown sample containing a fence', [block('b', MD, 'markdown')])
cases += block_case('plain-text', 'Unknown language: plain text under the generic label', [block('b', TEXT, 'text')])
cases += block_case('numbered-unwrapped', 'Numbered and unwrapped', [block('b', TS, 'ts', True)], WRAP_CLICK)
cases += block_case('zh-cn', 'Chinese comments and strings with the Chinese toolbar', [block('b', ZH_TS, 'typescript', True)], locale='zh-CN')
replace_cases('components.code.block.', cases)


def read_case(name, title, read, interactions=None, locale='en', variants=None):
    props = {'layout': LAYOUT, 'block': read}
    variants = variants or [('default', 'Default', props, interactions)]
    return themed(base_case('components.code.read.' + name, title, 'code.read',
                            {'width': PHONE, 'height': READ_HEIGHT[name], 'density': 2}, variants, locale=locale,
                            category='extension/code', react_hint=PRIM + 'ReadBlock.tsx'))


read_ts = {'label': 'src/time.ts', 'lang': 'typescript', 'lines': lines_of(READ_TS, 38), 'totalLines': 120}
LONG = '\n'.join('export const value%d = compute(%d, "label-%d")' % (i, i, i) for i in range(1, 25))
read_long = {'label': 'src/values.ts', 'lang': 'typescript', 'lines': lines_of(LONG), 'totalLines': 24}
read_py = {'label': 'settings/load.py', 'lang': 'python', 'lines': lines_of(PY), 'totalLines': 18}
read_zh = {'label': '设置/启动.ts', 'lang': 'typescript', 'lines': lines_of(ZH_TS, 8), 'totalLines': 40}
read_text = {'label': 'notes.txt', 'lines': lines_of(TEXT), 'totalLines': 5}

rc = read_case('window-ts', 'Read window of a TypeScript file (status note, three-digit gutter)', read_ts)
rc += read_case('python-full', 'Whole Python file, two-digit numbers', read_py)
long_props = {'layout': LAYOUT, 'block': read_long}
rc += read_case('capped-long', 'More lines than the cap: head, fold row, tail; then expanded', read_long, variants=[
    ('default', 'Capped', long_props, None),
    ('expanded', 'Expanded by the fold row', long_props,
     [{'type': 'click', 'target': 'read-fold'}, {'type': 'hover', 'target': 'read-block'}])])
READ_WRAP = [{'type': 'click', 'target': 'code-wrap'}, {'type': 'hover', 'target': 'read-block'}]
rc += read_case('wrapped', 'Wrap toggled on a window with long lines', read_ts, READ_WRAP)
rc += read_case('plain-text', 'Read window without a language', read_text)
rc += read_case('zh-cn', 'Chinese label, status and source', read_zh, locale='zh-CN')
replace_cases('components.code.read.', rc)

zh_text = ZH_TS + read_zh['label'] + ''.join(l['text'] for l in read_zh['lines'])
missing = fonts.uncovered_cjk(zh_text)
if missing:
    sys.exit('Chinese cases use characters outside the pinned CJK subset: %s' % ''.join(missing))
