"""The real dockkit TabMenu, with source-managed material and menu-item CSS."""
from builders_api import base_case,replace_cases,themed
ORDER=472
cases=[]
for device,density in [('desktop',1),('phone',2.625)]:
 for locale,label in [('en','Close tab'),('zh-CN','关闭标签页')]:
  c=base_case(f'components.menu-geometry.dock-{device}-{locale.split('-')[0]}','Dock tab menu','menu-geometry.dock',{'width':400,'height':240,'density':density},[
   ('default','At rest',{'label':label},None),
   ('hover','Hovered close row',{'label':label},[{'type':'hover','target':'dock-menu-close'}]),
   ('focus','Keyboard focus',{'label':label},[{'type':'tab','count':2}]),
  ],locale=locale,category='extension/menu-geometry',react_hint='packages/client/ui-dockkit/src/components/TabMenu.tsx',flutter_hint='apps/dsh_flutter/test/parity/cases/menu_geometry.dart')
  c['capture']={'selector':'[data-dockkit-tab-menu]','flutterKey':'dock-menu-surface','crop':'element'}
  cases+=themed(c)
replace_cases('components.menu-geometry.',cases)
