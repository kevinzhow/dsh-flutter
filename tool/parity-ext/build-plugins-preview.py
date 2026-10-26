"""Pinned upstream plugin manager, installer, inventory and Discover components."""
from builders_api import base_case, replace_cases, themed
ORDER = 470
cases = []
for family, names in {'manager':['populated','empty','unavailable','add-menu'], 'inventory':['populated','empty'], 'market':['noindexes','empty']}.items():
 for name in names:
  for device, viewport, density in [('desktop',800,1),('phone',390,2.625)]:
   for locale in ['en','zh-CN']:
    width = 720 if device == 'desktop' else 326
    c = base_case(f'components.plugins-preview.{family}-{name}-{device}-{locale.split("-")[0]}', f'{family} {name}', f'plugins-preview.{family}', {'width':viewport,'height':1100,'density':density}, [('default',name,{'width':width,'height':900,'name':name},[{'type':'click','target':'plugin-add-more'}] if name=='add-menu' else None)], locale=locale, category='extension/plugins-preview',react_hint='packages/client/ui-plugin-manager,ui-plugin-market,ui-settings-plugin-inventory/src/client',flutter_hint='apps/dsh_flutter/test/parity/cases/plugins_preview.dart')
    c['capture']={'selector':'[data-parity-id="plugins-preview-surface"]','flutterKey':'plugins-preview-surface','crop':'element'}
    cases += themed(c)
replace_cases('components.plugins-preview.', cases)
