"""Actual upstream Agent, Skill, Goal, Jobs and retained-task surfaces."""
from builders_api import base_case,replace_cases,themed
ORDER=465
cases=[]
for family,names in {'preset':['coding','basic'],'goal':['active','paused','blocked'],'skill':['ok','error','running'],'jobs':['closed'],'manager':['populated','empty']}.items():
 for name in names:
  for device,viewport,density in [('desktop',800,1),('phone',390,2.625)]:
   for locale in ['en','zh-CN']:
    width=600 if device=='desktop' else 326
    height={'preset':1250,'manager':600,'goal':100,'skill':100,'jobs':60}[family]
    c=base_case(f'components.agents-tasks.{family}-{name}-{device}-{locale.split("-")[0]}',f'{family} {name}',f'agents-tasks.{family}',{'width':viewport,'height':1600,'density':density},[('default',name,{'width':width,'height':height,'name':name},None)],locale=locale,category='extension/agents-tasks',react_hint='packages/client/ui-'+{'preset':'agent-preset','goal':'goal','skill':'skill','jobs':'jobs','manager':'schedule'}[family]+'/src/client',flutter_hint='apps/dsh_flutter/test/parity/cases/agents_tasks.dart')
    c['capture']={'selector':'[data-parity-id="agents-tasks-surface"]','flutterKey':'agents-tasks-surface','crop':'element'}
    cases+=themed(c)
replace_cases('components.agents-tasks.',cases)
