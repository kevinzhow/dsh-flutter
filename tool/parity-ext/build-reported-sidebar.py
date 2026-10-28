#!/usr/bin/env python3
"""Real sidebar root + browsing region + signed-out launcher, fixed synthetic data."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed
cases=[]
for platform,form,viewport_width,height in [('darwin','desktop',1280,800),('linux','desktop',1280,800),('linux','phone',390,800)]:
    for locale in ('en','zh-CN'):
        tag='zh' if locale=='zh-CN' else 'en'
        case=base_case(f'components.reported-sidebar.{platform}-{form}-{tag}',f'Real sidebar ({platform}, {form}, {tag})','reported-sidebar.root',
            {'width':viewport_width,'height':height,'density':2}, [('default','full-root',{'width':280,'height':height,'platform':platform},None)],
            locale=locale,category='extension/reported-sidebar',
            react_hint='packages/client/ui-sidebar/src/client/SidebarRoot.tsx + ui-workspace rows/WorkspaceBrowser.tsx + ui-settings-general SettingsRoot.tsx + ui-settings-account AccountMenu.tsx',
            flutter_hint='features/dsh_feature_sidebar/test/parity/cases/reported_sidebar.dart reportedSidebarCases')
        case['capture']={'selector':'[data-parity-id="reported-sidebar-frame"]','flutterKey':'reported-sidebar-frame','crop':'element'}
        cases.extend(themed(case))
replace_cases('components.reported-sidebar.',cases)
