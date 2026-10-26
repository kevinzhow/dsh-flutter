"""Actual WorkspacePickFlow long-list screens, with and without its pinned add action."""
from builders_api import base_case,replace_cases,themed
ORDER=474
cases=[]
for device,width,height,density in [('desktop',520,760,1),('phone',390,420,2.625)]:
 for locale in ['en','zh-CN']:
  for footer in [True,False]:
   workspaces=[{'id':f'w{i}','title':f'Workspace {i:02d}' if locale=='en' else f'工作区 {i:02d}'} for i in range(40)]
   c=base_case(f'components.menu-viewport.long-{device}-{locale.split("-")[0]}-{int(footer)}','Actual workspace long menu','workspace.picker',{'width':width,'height':height,'density':density},[
    ('default','Long list with footer' if footer else 'Long list without footer',{'workspaces':workspaces,'selectedId':'w0','flow':footer},None)],locale=locale,category='extension/menu-viewport',react_hint='packages/client/ui-workspace/src/client/WorkspacePicker.tsx',flutter_hint='features/dsh_feature_workspace/test/parity/cases/workspace.dart')
   c['capture']={'selector':'[role="menu"]','flutterKey':'workspace-menu','crop':'element'}
   cases+=themed(c)
replace_cases('components.menu-viewport.',cases)
