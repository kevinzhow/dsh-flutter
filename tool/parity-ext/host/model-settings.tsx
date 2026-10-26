import {useLayoutEffect,useRef} from 'react'
import {SettingsSchemaService} from '@dsh/ui-settings/src/client/schema.ts'
import {ProviderEditor} from '@dsh/ui-settings-models/src/client/ProviderEditor.tsx'
import {CustomProviderCard} from '@dsh/ui-settings-models/src/client/CustomProviderCard.tsx'
import {en as modelEn,zh as modelZh} from '@dsh/ui-settings-models/src/client/locales.ts'
import {AgentLoopCard} from '@dsh/ui-settings-agent-loop/src/client/AgentLoopCard.tsx'
import {en as agentEn,zh as agentZh} from '@dsh/ui-settings-agent-loop/src/client/locales.ts'
import {ShellCard} from '@dsh/ui-settings-shell/src/client/ShellCard.tsx'
import {en as shellEn,zh as shellZh} from '@dsh/ui-settings-shell/src/client/locales.ts'
import {SubagentCard} from '@dsh/ui-settings-subagent/src/client/SubagentCard.tsx'
import {en as subEn,zh as subZh} from '@dsh/ui-settings-subagent/src/client/locales.ts'
import {WebSearchCard} from '@dsh/ui-settings-web-search/src/client/WebSearchCard.tsx'
import {en as webEn,zh as webZh} from '@dsh/ui-settings-web-search/src/client/locales.ts'
import {UploadRow} from '@dsh/ui-settings-session-log/src/client/UploadRow.tsx'
import {en as uploadEn,zh as uploadZh} from '@dsh/ui-settings-session-log/src/client/locales.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
const noop=()=>{},asyncNoop=async()=>{}
const schema=Object.create(SettingsSchemaService.prototype)
const serialized={uid:9,refs:{'1':{type:'string',meta:{}},'2':{type:'const',value:'openai-completions',meta:{}},'3':{type:'union',list:[2],meta:{}},'4':{type:'any',meta:{}},'5':{type:'array',inner:4,meta:{default:[]}},'6':{type:'object',dict:{api:3,baseURL:1,apiKeyEnv:1,models:5},meta:{}},'8':{type:'dict',inner:6,sKey:1,meta:{}},'9':{type:'object',dict:{providers:8},meta:{}}}}
const value={providers:{openai:{apiKeyEnv:'OPENAI_API_KEY',api:'openai-completions',models:[{id:'demo',name:'Demo model',contextWindow:256000}]}}}
const namespace={ns:'llm-pi-ai',schema:serialized,value,base:value,user:{},revision:1,applies:'live',autoGenerate:true,secrets:[]}
const operations={storeCredential:async()=>undefined,removeCredential:async()=>undefined,writeSettings:async()=>({kind:'refused',message:'Synthetic write disabled'}),discoverModels:async()=>({kind:'found',models:[]})}
const field=(text:string)=>({text,overridden:false,invalid:false})
function Surface({family,props,ctx}:any){
 const ref=useRef<HTMLDivElement>(null)
 const dictionaries:any={provider:[modelEn,modelZh],custom:[modelEn,modelZh],agent:[agentEn,agentZh],shell:[shellEn,shellZh],limits:[subEn,subZh],web:[webEn,webZh],upload:[uploadEn,uploadZh]}
 const [en,zh]=dictionaries[family],t=createTranslator(ctx.case.locale,{en,zh})
 const shell={available:true,writable:props.name!=='readonly',dirty:false,invalid:false,saving:false,failed:false}
 const actions={edit:noop,resetField:noop,save:noop,discard:noop}
 let body:any
 if(family==='provider')body=<ProviderEditor {...{provider:'openai',displayName:'OpenAI',namespace,schema,settingsPath:['providers','openai'],operations,t,readOnly:false,onClose:noop} as any}/>
 if(family==='custom')body=<CustomProviderCard {...{taken:['openai','anthropic'],protocols:['openai-completions'],reasoningLevels:[],revision:1,operations,t,readOnly:false,onClose:noop} as any}/>
 if(family==='agent'){const state={...shell,maxParallelToolCalls:field('2')};body=<><h3 style={{fontSize:16,lineHeight:'24px',fontWeight:400,margin:'0 0 12px'}}>{t('title')}</h3><AgentLoopCard {...{view:'config',useAgentLoopCard:(s:any)=>s(state),...actions,t} as any}/></>}
 if(family==='shell'){const state={...shell,timeoutMs:field('30000'),maxOutputBytes:field('65536')};body=<><h3 style={{fontSize:16,lineHeight:'24px',fontWeight:400,margin:'0 0 12px'}}>{t('title')}</h3><ShellCard {...{view:'config',useShellCard:(s:any)=>s(state),...actions,t} as any}/></>}
 if(family==='limits'){const state={...shell,maxDepth:field('1'),maxActiveSubagents:field('2')};body=<SubagentCard {...{view:'config',useSubagentLimitsCard:(s:any)=>s(state),useSubagentModelSelectionCard:(s:any)=>s({...shell,available:false,enabled:false,candidates:[],catalogStatus:'idle',catalogPartial:false,conflicted:false}),editLimit:noop,resetLimit:noop,toggleEnabled:noop,toggleModel:noop,retryCatalog:noop,...actions,t} as any}/>}
 if(family==='web'){const state={...shell,apiSwitchAvailable:true,apiSwitchBlocked:false,useSearchApi:props.name==='api',baseURL:field(props.name==='api'?'https://api.example/v1/tools':'https://api.example/anthropic/v1'),maxUses:field('5'),count:field('10'),apiKey:field(''),apiKeyConfigured:false,apiKeyWritable:true};body=<><h3 style={{fontSize:16,lineHeight:'24px',fontWeight:400,margin:0}}>{t('title')}</h3><WebSearchCard {...{view:'config',useWebSearchCard:(s:any)=>s(state),...actions,setSearchApi:noop,t} as any}/></>}
 if(family==='upload'){const state={status:'ready',value:{enabled:props.name==='on'},writable:true};body=<UploadRow {...{useUpload:(s:any)=>s(state),useMutation:(s:any)=>s({busy:false,notice:null,sequence:0}),setEnabled:asyncNoop,dismiss:noop,t} as any}/>}
 useLayoutEffect(()=>{const host=ref.current;if(!host)return;host.querySelector('summary')?.setAttribute('data-parity-id','provider-customized');host.querySelector('input[type="password"]')?.setAttribute('data-parity-id','provider-api-key')},[])
 return <div ref={ref} data-parity-id="model-settings-surface" style={{width:props.width,color:'var(--dsw-alias-label-primary)'}}>{body}</div>
}
export const kinds:Record<string,KindRenderer>=Object.fromEntries(['provider','custom','agent','shell','limits','web','upload'].map(f=>[`model-settings.${f}`,(props:any,ctx:any)=><Surface family={f} props={props} ctx={ctx}/>]))
