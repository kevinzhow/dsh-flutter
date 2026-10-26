"""Actual source Menu normal/dense/compact profiles, alongside real page cases."""
from builders_api import base_case,replace_cases,themed
ORDER=471
cases=[]
for profile in ['standard','dense','compact']:
 for device,density in [('desktop',1),('phone',2.625)]:
  c=base_case(f'components.menu.family-{profile}-{device}',f'Menu {profile}','menu-family.profiles',{'width':400,'height':360,'density':density},[('default',profile,{'profile':profile},None)],category='extension/menu',react_hint='packages/client/ui-primitives/src/Menu.tsx',flutter_hint='apps/dsh_flutter/test/parity/cases/menu_family.dart')
  c['capture']={'selector':'[role="menu"]','flutterKey':'menu-family-card','crop':'element'}
  cases+=themed(c)
replace_cases('components.menu.family-',cases)
