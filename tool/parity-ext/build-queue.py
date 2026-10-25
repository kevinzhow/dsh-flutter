"""QueueDock and busy-Enter settings against the pinned upstream components."""
from builders_api import base_case, replace_cases, themed
ORDER = 460
rows = [dict(id=i, source={'kind': 'user'}, content=[{'type': 'text', 'text': text}])
        for i, text in [('a', 'Keep the first synthetic message'), ('b', 'Then check the second result')]]
file = dict(id='file', source={'kind': 'user'}, content=[{'type': 'text', 'text': 'Read this'},
    {'type': 'file', 'attachment': {'attachmentId': 'f', 'name': 'design.pdf', 'bytes': 12345}}])
variants = {
    'single': {'rows': rows[:1]}, 'collapsed': {'rows': rows}, 'expanded': {'rows': rows, 'expanded': True},
    'editing': {'rows': rows[:1], 'editing': True}, 'file': {'rows': [file]},
    'pending': {'rows': [], 'pending': [{'requestId': 'local', 'text': 'Sending synthetic text', 'placement': 'queued', 'attachments': []}]},
    'idle': {'rows': rows[:1], 'running': False}, 'readonly': {'rows': rows[:1], 'mutable': False},
}
cases=[]
for device,width,viewport,density in [('desktop',480,800,1), ('phone',326,390,2.625)]:
    for locale in ['en','zh-CN']:
        for name,props in variants.items():
            steps = [{'type':'click','target':'queue-header'}] if props.get('expanded') else [{'type':'click','target':'queue-edit-a'}] if props.get('editing') else None
            c=base_case(f'components.queue.{name}-{device}-{locale.split('-')[0]}', f'Queue {name}', 'conversation.queue',
                {'width':viewport,'height':900,'density':density}, [('default',name,dict(width=width,**props),steps)], locale=locale,
                category='extension/queue', react_hint='packages/client/ui-conversation/src/client/queue/QueueDock.tsx',
                flutter_hint='features/dsh_feature_conversation/test/parity/cases/queue.dart')
            c['capture']={'selector':'[data-parity-id="queue-panel"]','flutterKey':'queue-panel','crop':'element'}
            cases+=themed(c)
        for value in ['queue','steer']:
            c=base_case(f'components.enter-setting.{value}-{device}-{locale.split('-')[0]}',f'Busy Enter {value}', 'conversation.enter-setting',
                {'width':viewport,'height':900,'density':density}, [('default',value,{'width':width,'value':value},None)],locale=locale,
                category='extension/enter-setting',react_hint='packages/client/ui-conversation/src/client/settings/EnterBehaviorRow.tsx',
                flutter_hint='features/dsh_feature_conversation/test/parity/cases/queue.dart')
            c['capture']={'selector':'[data-parity-id="settings-enter"]','flutterKey':'settings-enter','crop':'element'}
            cases+=themed(c)
replace_cases('components.queue.',[c for c in cases if c['kind']=='conversation.queue'])
replace_cases('components.enter-setting.',[c for c in cases if c['kind']=='conversation.enter-setting'])
