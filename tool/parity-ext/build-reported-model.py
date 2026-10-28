"""The actual ModelSelect root/list/effort menu opened from its trigger."""
from builders_api import base_case, replace_cases, themed

ORDER = 483
cases = []
for device, width, density in [('desktop', 1100, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for pane in ['root', 'model', 'effort']:
            steps = [{'type': 'click', 'target': 'model-chip'}]
            if pane != 'root':
                steps.append({'type': 'click', 'target': 'model-root-' + pane})
            for capture in ['card', 'viewport']:
                case = base_case(
                    f'components.reported-model.{pane}-{capture}-{device}-{locale.split("-")[0]}',
                    f'ModelSelect {pane} {capture}', 'reported-model.menu',
                    {'width': width, 'height': 800, 'density': density},
                    [('default', pane, {'platform': 'darwin' if device == 'desktop' else 'other'}, steps)], locale=locale,
                    category='extension/reported-model',
                    react_hint='packages/client/ui-model-selection/src/client/ModelSelect.tsx',
                    flutter_hint='features/dsh_feature_model_selection/lib/src/model_select.dart')
                target = 'model-sheet' if capture == 'card' else 'reported-model-viewport'
                case['capture'] = {'selector': f'[data-parity-id="{target}"]',
                                   'flutterKey': target, 'crop': 'element'}
                cases += themed(case)
replace_cases('components.reported-model.', cases)
