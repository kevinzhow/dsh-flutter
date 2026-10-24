#!/usr/bin/env python3
"""Composer overlays (dsh ui-input-trigger MenuView, ui-commands PopupSelectView): the `/` and `@` candidate menu and the
command popup, over the same fixture data on both providers.

React host: host/input-trigger.tsx mounts dsh's real MenuView and PopupSelectView over fixture stores and crops to the menu
surface. Flutter: TriggerMenuOverlay / PopupSelectOverlay
(features/dsh_feature_input_trigger/test/parity/cases/input_trigger.dart, features/dsh_feature_commands/test/parity/cases/command_popup.dart).

  input.menu    {groups, highlight, crumbs}     parity id: menu
  input.popup   {command, options, active, ...} parity id: menu

Ids: components.input-trigger.<name>-<locale>.<theme> and components.command-popup.<name>-<locale>.<theme>. A phone width (390) and a
wide window width (760, the composer column) are separate cases: both are scored against dsh web at the same width
(docs/parity.md, owner decisions: no phone adaptation).
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 450
HINT = 'packages/client/ui-input-trigger/src/client/MenuView.tsx'
FLUTTER_MENU = 'features/dsh_feature_input_trigger/test/parity/cases/input_trigger.dart inputTriggerCases[input.menu]'
FLUTTER_POPUP = 'features/dsh_feature_commands/test/parity/cases/command_popup.dart commandPopupCases[input.popup]'


def item(name, **kw):
    return {'name': name, **kw}


COMMANDS = [
    item('file', label='File', icon='paperclip', section='Add'),
    item('goal', label='Goal', description='Set or view the goal for a long-running task', icon='goal', section='Add'),
    item('plan', label='Plan', description='Enter or leave plan mode', icon='plan', section='Add'),
    item('feedback', label='Feedback', description='Record feedback about this session', icon='feedback', section='Add'),
    item('compact', label='Compact', description='Compact older conversation history', icon='compact', section='Commands'),
    item('permission', label='Permission', description='Switch the permission preset (sandbox mode + approval policy)',
         icon='permission', section='Commands'),
    item('model', label='Model', description='Select the model for this conversation', icon='model', section='Commands'),
    item('export', label='Export', description='Download this Session log as a ZIP archive', icon='export', section='Commands'),
]
COMMANDS_ZH = [
    item('file', label='文件', icon='paperclip', section='添加'),
    item('goal', label='目标', description='设置或查看长期任务目标', icon='goal', section='添加'),
    item('plan', label='计划', description='进入或退出计划模式', icon='plan', section='添加'),
    item('feedback', label='反馈', description='发送关于当前会话的反馈', icon='feedback', section='添加'),
    item('compact', label='压缩', description='压缩以上对话内容', icon='compact', section='指令'),
    item('permission', label='权限', description='切换权限预设（沙箱模式与审批策略）', icon='permission', section='指令'),
    item('model', label='模型', description='选择此对话的模型', icon='model', section='指令'),
    item('export', label='下载日志', description='将当前会话内容导出为 ZIP', icon='export', section='指令'),
]
# The workspace of the live checks (docs/, src/, README.md, notes.txt as the host lists them): the phone captures and the
# parity cases show the same rows.
FILES = [
    item('docs/', icon='folder', drill=True, section='Files & folders'),
    item('src/', icon='folder', drill=True, section='Files & folders'),
    item('README.md', icon='file', section='Files & folders'),
    item('notes.txt', icon='file', section='Files & folders'),
]
SESSIONS = [
    item('Planning chat', description='2h', icon='session', section='Sessions'),
    item('Release checklist', description='~/work · 3d', icon='session', section='Sessions'),
]
FILES_ZH = [
    item('docs/', icon='folder', drill=True, section='文件与文件夹'),
    item('src/', icon='folder', drill=True, section='文件与文件夹'),
    item('README.md', icon='file', section='文件与文件夹'),
    item('notes.txt', icon='file', section='文件与文件夹'),
    item('规划对话', description='2小时', icon='session', section='对话'),
    item('发布清单', description='3天', icon='session', section='对话'),
]
DRILLED = [item('guide.md', icon='file', section='Files & folders')]
DRILLED_DEEP = [
    item('main.dart', icon='file', section='Files & folders'),
    item('util/', icon='folder', drill=True, section='Files & folders'),
]


def menu(name, groups, highlight, crumbs=None, **extra):
    return (name, {'groups': groups, 'highlight': highlight, 'crumbs': crumbs, **extra})


CASES_EN = [
    menu('slash', [{'source': 'command', 'items': COMMANDS}], {'source': 'command', 'index': 0}),
    menu('slash-mid', [{'source': 'command', 'items': COMMANDS}], {'source': 'command', 'index': 5}),
    menu('at', [{'source': 'reference', 'showGroupTitle': False, 'items': FILES}], {'source': 'reference', 'index': 0}),
    menu('at-sessions', [{'source': 'reference', 'showGroupTitle': False, 'items': FILES + SESSIONS}], {'source': 'reference', 'index': 2}),
    menu('at-drilled', [{'source': 'reference', 'showGroupTitle': False, 'items': DRILLED}], {'source': 'reference', 'index': 0},
         {'reference': [{'label': 'Workspace', 'value': 'w'}, {'label': 'docs', 'value': 's', 'current': True}]}),
    menu('at-drilled-deep', [{'source': 'reference', 'showGroupTitle': False, 'items': DRILLED_DEEP}], {'source': 'reference', 'index': 0},
         {'reference': [{'label': 'Workspace', 'value': 'w'}, {'label': 'src', 'value': 's'}, {'label': 'util', 'value': 'u', 'current': True}]}),
    menu('loading', [{'source': 'command', 'status': 'pending', 'items': []}], None),
]
CASES_ZH = [
    menu('slash', [{'source': 'command', 'items': COMMANDS_ZH}], {'source': 'command', 'index': 0}),
    menu('at', [{'source': 'reference', 'showGroupTitle': False, 'items': FILES_ZH}], {'source': 'reference', 'index': 0}),
]
MODELS = [
    {'id': 'a/flash', 'label': 'deepseek-flash', 'group': {'name': 'a', 'label': 'DeepSeek Account'}, 'active': True},
    {'id': 'a/pro', 'label': 'deepseek-pro', 'group': {'name': 'a', 'label': 'DeepSeek Account'}},
    {'id': 'b/mini', 'label': 'mini-1', 'group': {'name': 'b', 'label': 'Local Provider'}},
]
# The host of the live checks lists three presets and no description (as the phone capture shows them).
PRESETS = [
    {'id': 'read-only', 'label': 'Read Only'},
    {'id': 'workspace-write', 'label': 'Workspace Write', 'active': True},
    {'id': 'danger-full-access', 'label': 'Full access'},
]
PRESETS_DETAILED = [
    {'id': 'read-only', 'label': 'Read Only', 'detail': 'Read files; no writes.'},
    {'id': 'workspace-write', 'label': 'Workspace Write', 'detail': 'Write inside the workspace.', 'active': True},
    {'id': 'auto', 'label': 'Auto review', 'badge': 'EXP', 'detail': 'A reviewer approves each action.'},
    {'id': 'danger-full-access', 'label': 'Full access', 'detail': 'No approval prompts.'},
]
POPUPS = [
    ('model', {'command': 'model', 'options': MODELS, 'active': 0, 'searchMode': 'fuzzy-label',
               'searchLabels': {'placeholder': 'Search models…', 'empty': 'No models available.', 'noResults': 'No matching models.'}}),
    ('permission', {'command': 'permission', 'options': PRESETS, 'active': 1}),
    ('permission-detailed', {'command': 'permission', 'options': PRESETS_DETAILED, 'active': 1}),
    ('error', {'command': 'model', 'options': [], 'status': 'failed', 'error': 'models/list failed: gateway/internal'}),
]

cases = []
for width, tag in ((390, 'phone'), (760, 'wide')):
    for name, props in CASES_EN:
        case = base_case('components.input-trigger.%s-%s-en' % (name, tag), 'Candidate menu: %s (%s)' % (name, tag), 'input.menu',
                         {'width': width + 40, 'height': 520, 'density': 2},
                         [('default', name, dict(props, width=width), None)], locale='en',
                         category='extension/input-trigger', react_hint=HINT, flutter_hint=FLUTTER_MENU)
        case['capture'] = {'selector': '[data-trigger-menu]', 'flutterKey': 'trigger-menu-surface', 'crop': 'element'}
        cases += themed(case)
    for name, props in CASES_ZH:
        case = base_case('components.input-trigger.%s-%s-zh' % (name, tag), 'Candidate menu: %s (%s, zh)' % (name, tag), 'input.menu',
                         {'width': width + 40, 'height': 520, 'density': 2},
                         [('default', name, dict(props, width=width), None)], locale='zh-CN',
                         category='extension/input-trigger', react_hint=HINT, flutter_hint=FLUTTER_MENU)
        case['capture'] = {'selector': '[data-trigger-menu]', 'flutterKey': 'trigger-menu-surface', 'crop': 'element'}
        cases += themed(case)
    for name, props in POPUPS:
        case = base_case('components.command-popup.%s-%s-en' % (name, tag), 'Command popup: %s (%s)' % (name, tag), 'input.popup',
                         {'width': width + 40, 'height': 420, 'density': 2},
                         [('default', name, dict(props, width=width), None)], locale='en',
                         category='extension/command-popup',
                         react_hint='packages/client/ui-commands/src/client/PopupSelectView.tsx', flutter_hint=FLUTTER_POPUP)
        case['capture'] = {'selector': '[class*="card"]', 'flutterKey': 'command-popup-surface', 'crop': 'element'}
        cases += themed(case)
replace_cases('components.input-trigger.', [c for c in cases if c['id'].startswith('components.input-trigger.')])
replace_cases('components.command-popup.', [c for c in cases if c['id'].startswith('components.command-popup.')])
