#!/usr/bin/env python3
"""Tool rows (bash, edit, write) and the todo panel: dsh's real ui-tool toolviews and ui-conversation TodoPanel.

React host: host/tools.tsx mounts the real rows with the mocks in tool/parity-web/host/mocks/ (session store,
disclosure hook, a translator over the real conversation dictionary). Kinds and props:

  tool.card         {layout, items: [{id, toolName, phase: preparing|start|result, callId, argsRaw (JSON text of the
                    tool arguments), result: {content, isError, error, meta} (phase result only), cwd, home, expanded}]}
                    parity ids: <id> (the whole row), <id>-row (the header, present while the row is expandable)
  plan.todo-panel   {todos: [{content, status: pending|in_progress|completed}]}; parity ids: todo-panel, todo-header

Ids: components.<area>.<surface>.<name>.<theme>. All content is invented (no real paths, names or conversations).
"""
import json

from builders_api import base_case, replace_cases, themed

ORDER = 300
UI_TOOL = 'packages/client/ui-tool/src/client/tool/toolviews/'
COLUMN = {'direction': 'column', 'gap': 8, 'align': 'stretch'}
CWD = '/home/user/project'
HOME = '/home/user'
PHONE = 390


def row(item_id, tool, args, *, phase='result', text=None, meta=None, is_error=False, expanded=False):
    """One `tool.card` item. `args` is the tool's argument object (serialised the way the model emits it)."""
    item = {'id': item_id, 'toolName': tool, 'phase': phase, 'callId': 'call-' + item_id,
            'argsRaw': json.dumps(args), 'cwd': CWD, 'home': HOME, 'expanded': expanded}
    if phase == 'result':
        result = {'content': [{'type': 'text', 'text': text}] if text is not None else [], 'isError': is_error}
        if meta is not None:
            result['meta'] = meta
        item['result'] = result
    return item


def bash(item_id, command, description, **kw):
    return row(item_id, 'bash', {'command': command, 'description': description}, **kw)


LS_OUTPUT = '\n'.join([
    'total 32',
    'drwxr-xr-x 4 user 4096 Oct  2 .',
    'drwxr-xr-x 7 user 4096 Oct  2 ..',
    '-rw-r--r-- 1 user 1204 Oct  2 app.ts',
    '-rw-r--r-- 1 user  873 Oct  1 config.ts',
    'drwxr-xr-x 2 user 4096 Sep 29 utils'])

# A failing command settles as a completed call whose text ends with the `[exit code: N]` marker the bash tool renders
# (shell/tool-bash/src/render.ts: stderr under a `[stderr]` header, the marker last).
CAT_ERROR = '[stderr]\ncat: missing.txt: No such file or directory\n[exit code: 1]'

bash_items = [
    bash('bash-ok', 'npm test', 'Run the unit tests', text='Tests: 12 passed, 12 total'),
    bash('bash-ok-open', 'ls -la src', 'List the source directory', text=LS_OUTPUT, expanded=True),
    bash('bash-exit', 'cat missing.txt', 'Print a missing file', text=CAT_ERROR, expanded=True),
    bash('bash-running', 'npm run build', 'Build the project', phase='start'),
]
replace_cases('components.tool.bash.', themed(base_case(
    'components.tool.bash.row.states', 'Bash tool row states', 'tool.card', {'width': PHONE, 'height': 440, 'density': 2},
    [('default', 'Settled, expanded, failed and running rows', {'layout': COLUMN, 'items': bash_items}, None),
     ],
    category='extension/tool', react_hint=UI_TOOL + 'bash-sample.tsx')))

# ---- edit / write: the DiffBlock through ToolRow ---------------------------------------------------------------
APP_OLD = '\n'.join([
    "import { load } from './config'", '', 'export function start(port: number) {', '  const settings = load()',
    '  return listen(port, settings)', '}', ''])
APP_NEW = APP_OLD.replace('  const settings = load()\n',
                          "  const settings = load({ strict: true })\n  log('starting on port ' + port)\n")
README_OLD = '# Sample project\n\nRun the app with `npm start`.\n\nSee the docs folder for details.\n'
README_NEW = README_OLD.replace('npm start', 'npm run dev')
FORMAT_TEXT = '\n'.join([
    'export function pad(n: number): string {', "  return String(n).padStart(2, '0')", '}', '',
    "export const SEPARATOR = ':'", ''])


def mutation(item_id, tool, path, args, old, new, text, **kw):
    """edit/write row. The call names the file relative to the workspace; the settled result records the absolute
    path and the applied diff in its metadata (ui-tool diff-card-model.ts: meta.diffs [{path, oldText, newText}])."""
    absolute = CWD + '/' + path
    meta = {'path': absolute, 'diffs': [{'path': absolute, 'oldText': old, 'newText': new}]}
    return row(item_id, tool, dict(args, file_path=path), text=text, meta=meta, **kw)


def edit(item_id, path, old, new, snippet_old, snippet_new, **kw):
    return mutation(item_id, 'edit', path, {'old_string': snippet_old, 'new_string': snippet_new}, old, new,
                    'The file %s has been updated.' % path, **kw)


diff_items = [
    edit('edit-ok', 'README.md', README_OLD, README_NEW, 'npm start', 'npm run dev'),
    edit('edit-ok-open', 'src/app.ts', APP_OLD, APP_NEW, '  const settings = load()',
         "  const settings = load({ strict: true })\n  log('starting on port ' + port)", expanded=True),
    mutation('write-ok-open', 'write', 'src/utils/format.ts', {'content': FORMAT_TEXT}, None, FORMAT_TEXT,
             'Created src/utils/format.ts', expanded=True),
]
replace_cases('components.tool.diff.', themed(base_case(
    'components.tool.diff.row.states', 'Edit and write tool row states', 'tool.card',
    {'width': PHONE, 'height': 562, 'density': 2},
    [('default', 'Edit collapsed, edit expanded, write expanded', {'layout': COLUMN, 'items': diff_items}, None),
     ],
    category='extension/tool', react_hint=UI_TOOL + 'file-mutation-row.tsx')))

# ---- todo panel ------------------------------------------------------------------------------------------------
TODOS = [
    {'content': 'Write the release notes', 'status': 'completed'},
    {'content': 'Review the open pull requests', 'status': 'in_progress'},
    {'content': 'Update the install guide', 'status': 'pending'},
    {'content': 'Tag the release candidate', 'status': 'pending'},
]
replace_cases('components.plan.todo.', themed(base_case(
    'components.plan.todo.panel.states', 'Todo panel', 'plan.todo-panel', {'width': PHONE, 'height': 180, 'density': 2},
    [('default', 'Collapsed', {'todos': TODOS}, None),
     ('expanded', 'Expanded by a click on the header', {'todos': TODOS}, [{'type': 'click', 'target': 'todo-header'}])],
    category='extension/plan',
    react_hint='packages/client/ui-conversation/src/client/skeleton/TodoPanel.tsx')))

# ---- plan cards and the plan document --------------------------------------------------------------------------
PLAN_MARKDOWN = """# Release checklist

A short plan for shipping the next version.

## Steps

1. Update the changelog with the **notable** changes.
2. Run `npm test` and fix any failures.
3. Tag the release and publish the notes.

## Risks

- A flaky integration test may need a retry.
- The install guide still mentions the old command.
"""
PLANS = [
    {'callId': 'plan-1', 'title': 'Release checklist', 'markdown': PLAN_MARKDOWN},
    {'callId': 'plan-2', 'title': 'Move the settings screen to the new layout and refresh every related test',
     'markdown': '# Settings layout\n\nMove the screen and update its tests.\n'},
]
replace_cases('components.plan.card.', themed(base_case(
    'components.plan.card.list.states', 'Plan cards', 'plan.card', {'width': PHONE, 'height': 162, 'density': 2},
    [('default', 'Two submitted plans, the second with a long title', {'plans': PLANS}, None)],
    category='extension/plan', react_hint='packages/client/ui-plan/src/client/PlanCard.tsx')))
replace_cases('components.plan.preview.', themed(base_case(
    'components.plan.preview.document.states', 'Plan document preview', 'plan.preview',
    {'width': PHONE, 'height': 480, 'density': 2},
    [('default', 'A plan rendered as Markdown', {'plan': PLANS[0]}, None)],
    category='extension/plan', react_hint='packages/client/ui-plan/src/client/PlanPreview.tsx')))
