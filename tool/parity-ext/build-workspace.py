#!/usr/bin/env python3
"""Workspace surfaces (dsh ui-workspace WorkspacePickFlow, ui-directory-picker-browse DirectoryBrowser) over the same
fixture data on both providers: the anchored menu, the adoption error dialog, and the directory dialog. Every case runs at
a wide window and at a phone width (390px): Whalee renders what dsh web renders at the same width (docs/parity.md, owner
decisions), so the phone cases carry the same bar as the wide ones.

React host: host/workspace.tsx mounts dsh's real WorkspacePickFlow and DirectoryBrowser. Flutter:
features/dsh_feature_workspace/test/parity/cases/workspace.dart and
features/dsh_feature_directory_picker_browse/test/parity/cases/directory_browser.dart.

  workspace.picker      {workspaces, selectedId?}                parity id: workspace-menu
  workspace.error       {message}                                 parity id: folder-error
  workspace.directory   {variant}                                 parity id: directory-dialog

Ids: components.workspace.<name>-<locale>.<theme>, components.directory-browser.<name>-<locale>.<theme>.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

WS = [{'id': 'atlas', 'title': 'atlas'}, {'id': 'harbor', 'title': 'harbor'}, {'id': 'meadow', 'title': 'meadow'}]
WS_ZH = [{'id': 'atlas', 'title': '阿特拉斯'}, {'id': 'harbor', 'title': '港湾'}, {'id': 'meadow', 'title': '草地'}]
FLUTTER_WS = 'features/dsh_feature_workspace/test/parity/cases/workspace.dart workspaceCases'
FLUTTER_DIR = 'features/dsh_feature_directory_picker_browse/test/parity/cases/directory_browser.dart directoryBrowserCases'

cases = []


def add(case_id, title, kind, viewport, props, locale, capture, react_hint, flutter_hint, category):
    case = base_case(case_id, title, kind, viewport, [('default', props.get('_name', 'default'), {k: v for k, v in props.items() if k != '_name'}, None)],
                     locale=locale, category=category, react_hint=react_hint, flutter_hint=flutter_hint)
    case['capture'] = capture
    cases.extend(themed(case))


MENU = {'selector': '[role="menu"]', 'flutterKey': 'workspace-menu', 'crop': 'element'}
DIALOG = {'selector': '[role="dialog"]', 'flutterKey': 'folder-error-dialog', 'crop': 'element'}
BROWSER = {'selector': '[role="dialog"]', 'flutterKey': 'directory-dialog', 'crop': 'element'}
HINT_PICK = 'packages/client/ui-workspace/src/client/WorkspacePicker.tsx'
HINT_DIR = 'packages/client/ui-directory-picker-browse/src/client/DirectoryBrowser.tsx'
# (tag, viewport width) of the two forms; the heights fit the tallest case of each surface.
FORMS = (('wide', None), ('phone', 390))


def size(width, wide_width, height):
    return {'width': width or wide_width, 'height': height, 'density': 2}


for form, width in FORMS:
    suffix = '' if form == 'wide' else '-phone'
    for name, props, locale in [
        ('list', {'workspaces': WS, 'selectedId': 'harbor'}, 'en'),
        ('default-title', {'workspaces': [{'id': 'd', 'title': 'default-workspace'}] + WS, 'selectedId': 'd'}, 'en'),
        ('long-title', {'workspaces': [{'id': 'l', 'title': 'a-rather-long-workspace-folder-name-that-keeps-on-going-well-past-the-limit-of-the-menu'}] + WS}, 'en'),
        ('list', {'workspaces': WS_ZH, 'selectedId': '港湾'}, 'zh-CN'),
    ]:
        tag = 'zh' if locale == 'zh-CN' else 'en'
        add('components.workspace.menu-%s%s-%s' % (name, suffix, tag), 'Workspace picker menu: %s (%s, %s)' % (name, form, tag),
            'workspace.picker', size(width, 520, 380), props, locale, MENU, HINT_PICK, FLUTTER_WS + '[workspace.picker]',
            'extension/workspace')
    for locale, message in (('en', 'Not a directory'), ('zh-CN', '路径不是目录')):
        tag = 'zh' if locale == 'zh-CN' else 'en'
        add('components.workspace.folder-error%s-%s' % (suffix, tag), 'Adoption error dialog (%s, %s)' % (form, tag),
            'workspace.error', size(width, 460, 420), {'message': message}, locale, DIALOG, HINT_PICK, FLUTTER_WS + '[workspace.error]',
            'extension/workspace')
    for name, locale in [('home', 'en'), ('two-pane', 'en'), ('empty', 'en'), ('truncated', 'en'), ('error', 'en'),
                         ('home', 'zh-CN'), ('two-pane', 'zh-CN')]:
        tag = 'zh' if locale == 'zh-CN' else 'en'
        add('components.directory-browser.%s%s-%s' % (name, suffix, tag), 'Directory browser: %s (%s, %s)' % (name, form, tag),
            'workspace.directory', size(width, 740, 560), {'variant': name}, locale, BROWSER, HINT_DIR,
            FLUTTER_DIR + '[workspace.directory]', 'extension/directory-browser')

replace_cases('components.workspace.', [c for c in cases if c['id'].startswith('components.workspace.')])
replace_cases('components.directory-browser.', [c for c in cases if c['id'].startswith('components.directory-browser.')])
