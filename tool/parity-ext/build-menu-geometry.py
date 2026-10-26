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
for device,viewport,density in [('desktop',800,1),('phone',390,2.625)]:
 for locale,label in [('en','Close tab'),('zh-CN','关闭标签页')]:
  c=base_case(f"components.menu-geometry.screen-{device}-{locale.split('-')[0]}",'Actual dock surface with context menu','menu-geometry.screen',{'width':viewport,'height':600,'density':density},[
   ('default','Open context menu',{'width':720 if device=='desktop' else 326,'label':label},None),
  ],locale=locale,category='extension/menu-geometry',react_hint='packages/client/ui-dockkit/src/components/DockSurface.tsx',flutter_hint='apps/dsh_flutter/test/parity/cases/menu_geometry.dart')
  c['capture']={'selector':'[data-parity-target]','crop':'viewport'}
  cases+=themed(c)
replace_cases('components.menu-geometry.',cases)
