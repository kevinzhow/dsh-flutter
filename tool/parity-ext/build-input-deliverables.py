"""Sent references, masked credentials, declared files and recorded comparisons."""
from builders_api import base_case,replace_cases,themed
ORDER=463
cases=[]
for family,names in {
 'reference':['file','folder','session','long'],
 'secret':['masked','revealed','readonly','block'],
 'card':['ready','opening','opened','error'],
 'changes':['single','multiple'],
 'diff':['unified','split','wrap','binary','oversized','missing','error'],
}.items():
 for name in names:
  for device,viewport,density in [('desktop',800,1),('phone',390,2.625)]:
   for locale in ['en','zh-CN']:
    width=600 if device=='desktop' else 326
    steps=[{'type':'click','target':'secret-toggle'}] if name=='revealed' else None
    c=base_case(f'components.input-deliverables.{family}-{name}-{device}-{locale.split("-")[0]}',f'{family} {name}',f'input-deliverables.{family}',{'width':viewport,'height':700,'density':density},[('default',name,{'width':width,'name':name},steps)],locale=locale,category='extension/input-deliverables',react_hint='packages/client/ui-deliverables/src/client',flutter_hint='apps/dsh_flutter/test/parity/cases/input_deliverables.dart')
    c['capture']={'selector':'[data-parity-id="input-deliverables-surface"]','flutterKey':'input-deliverables-surface','crop':'element'}
    cases+=themed(c)
replace_cases('components.input-deliverables.',cases)
