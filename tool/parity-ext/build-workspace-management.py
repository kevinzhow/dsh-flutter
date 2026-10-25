"""Session rows, their menus/hover cards and real upstream action dialogs."""
from builders_api import base_case,replace_cases,themed
ORDER=462
cases=[]
for family,variants in {
 'row':['idle','hover','pinned','archived','running','pending','long'],
 'menu':['idle','pinned','archived'],
 'hover':['idle','archived','running'],
 'group':['idle','hover'],
 'rename':['ready','pending','refused'],
 'archive':['ready','pending','refused']}.items():
 for name in variants:
  for device,width,density in [('desktop',800,1),('phone',390,2.625)]:
   for locale in ['en','zh-CN']:
    kind='dialog' if family in ['rename','archive'] else 'group' if family=='group' else 'row'
    steps=[]
    if name in ['hover','long'] or family in ['menu','hover']:
     steps=[{'type':'hover','target':'workspace-row-a' if family=='group' else 'session-row-s1'}]
    if family=='menu':steps.append({'type':'click','target':'session-row-menu-s1'})
    if family=='hover':steps.append({'type':'wait','ms':900})
    if kind=='dialog' and name in ['pending','refused']:steps=[{'type':'click','target':'workspace-action-confirm'}]
    props={'width':256,'name':name,'long':name=='long','archive':family=='archive'}
    c=base_case(f'components.workspace-management.{family}-{name}-{device}-{locale.split("-")[0]}',f'{family} {name}',f'workspace-management.{kind}',{'width':width,'height':600,'density':density},[('default',name,props,steps or None)],locale=locale,category='extension/workspace-management',react_hint='packages/client/ui-workspace/src/client',flutter_hint='apps/dsh_flutter/test/parity/cases/workspace_management.dart')
    if family in ['rename','archive']:c['capture']={'selector':'[role="dialog"]','flutterKey':'workspace-management-dialog','crop':'element'}
    elif family=='menu':c['capture']={'selector':'[role="menu"]','flutterKey':'dsh-menu','crop':'element'}
    else:
     target='workspace-hover-card' if family=='hover' else 'workspace-row-a' if family=='group' else 'session-row-s1'
     c['capture']={'selector':f'[data-parity-id="{target}"]','flutterKey':'workspace-row-a' if family=='group' else target,'crop':'element'}
    cases+=themed(c)
replace_cases('components.workspace-management.',cases)
