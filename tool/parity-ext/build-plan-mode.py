"""Interactive plan controls and review documents against actual upstream views."""
from builders_api import base_case,replace_cases,themed
ORDER=461
cases=[]
variants={'chip':{
 'active':{},'hover':{'hover':True},'locked':{'locked':True},
 'pending-on':{'projection':{'active':False,'pending':True}},
 'leaving':{'busy':True},'refused':{'failure':True}},
 'review':{'ready':{},'busy':{'busy':True},'refused':{'failure':True}},
 'preview':{'temporary':{},'expired':{},'not-found':{},'failed':{}}}
for family,rows in variants.items():
 for name,data in rows.items():
  for device,viewport,density in [('desktop',800,1),('phone',390,2.625)]:
   width=480 if device=='desktop' else 294 if family=='review' else 326
   for locale in ['en','zh-CN']:
    steps=None
    if data.get('hover'):steps=[{'type':'hover','target':'plan-chip'}]
    if data.get('busy') or data.get('failure'):steps=[{'type':'click','target':'plan-chip' if family=='chip' else 'plan-review-approve'}]
    if family=='chip' and data.get('failure'):steps.append({'type':'hover','target':'plan-chip'})
    c=base_case(f'components.plan-mode.{family}-{name}-{device}-{locale.split("-")[0]}',f'{family} {name}',f'plan-mode.{family}',
      {'width':viewport,'height':900,'density':density},[('default',name,{'width':width,'height':240,'name':name,**data},steps)],locale=locale,
      category=f'extension/plan-mode-{family}',react_hint='packages/client/ui-plan/src/client',
      flutter_hint='apps/dsh_flutter/test/parity/cases/plan_mode.dart')
    target='plan-chip-surface' if family=='chip' else 'plan-review-card' if family=='review' else 'plan-preview-surface'
    c['capture']={'selector':f'[data-parity-id="{target}"]','flutterKey':target,'crop':'element'}
    cases+=themed(c)
replace_cases('components.plan-mode.',cases)
