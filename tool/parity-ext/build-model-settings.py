"""Provider and common settings: real pinned components, synthetic Host state."""
from builders_api import base_case,replace_cases,themed
ORDER=464
cases=[]
for family,names in {
 'provider':['default','advanced','invalid'], 'custom':['empty'],
 'agent':['default','readonly'], 'shell':['default'], 'limits':['default'],
 'web':['messages','api'], 'upload':['off','on'],
}.items():
 for name in names:
  for device,viewport,density in [('desktop',800,1),('phone',390,2.625)]:
   for locale in ['en','zh-CN']:
    width=600 if device=='desktop' else 326
    steps=[{'type':'click','target':'provider-customized'}] if name=='advanced' else [{'type':'type','target':'provider-api-key','text':'NAME=value'}] if name=='invalid' else None
    c=base_case(f'components.model-settings.{family}-{name}-{device}-{locale.split("-")[0]}',f'{family} {name}',f'model-settings.{family}',{'width':viewport,'height':1600,'density':density},[('default',name,{'width':width,'name':name},steps)],locale=locale,category='extension/model-settings',react_hint='packages/client/ui-settings-models/src/client',flutter_hint='apps/dsh_flutter/test/parity/cases/model_settings.dart')
    c['capture']={'selector':'[data-parity-id="model-settings-surface"]','flutterKey':'model-settings-surface','crop':'element'}
    cases+=themed(c)
replace_cases('components.model-settings.',cases)
