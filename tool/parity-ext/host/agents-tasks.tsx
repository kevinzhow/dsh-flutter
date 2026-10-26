import {AgentPresetSection} from '@dsh/ui-agent-preset/src/client/AgentPresetSection.tsx'
import {en as presetEn,zh as presetZh} from '@dsh/ui-agent-preset/src/client/locales.ts'
import {GoalBar} from '@dsh/ui-goal/src/client/GoalBar.tsx'
import {en as goalEn,zh as goalZh} from '@dsh/ui-goal/src/client/locales.ts'
import {SkillRow} from '@dsh/ui-skill/src/client/SkillRow.tsx'
import {en as skillEn,zh as skillZh} from '@dsh/ui-skill/src/client/locales.ts'
import {JobListAction} from '@dsh/ui-jobs/src/client/JobListAction.tsx'
import {en as jobEn,zh as jobZh} from '@dsh/ui-jobs/src/client/locales.ts'
import {TaskManagerPage} from '@dsh/ui-schedule/src/client/TaskManagerPage.tsx'
import {en as taskEn,zh as taskZh} from '@dsh/ui-schedule/src/client/task-manager-locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
const noop=()=>{},asyncNoop=async()=>{},release=()=>noop
const presets=[{id:'standard',isDefault:true},{id:'ptc',isDefault:false},{id:'cordis',isDefault:false},{id:'reviewer',name:'Synthetic reviewer',description:'Synthetic review preset',isDefault:false},{id:'broken',broken:'Synthetic dependency missing',isDefault:false}]
const tasks=[{id:'synthetic-daily',sessionId:'synthetic-session',title:'Synthetic daily task',prompt:'Review the synthetic project each morning.',kind:'daily',time:'09:00:00.123',timeZone:'Asia/Tokyo',scheduledAt:'2026-10-27T00:00:00.123Z',status:'active'},{id:'synthetic-ended',sessionId:'second-session',title:'Synthetic ended task',prompt:'Retained inactive instruction',kind:'at',scheduledAt:'2026-10-25T00:00:00.000Z',status:'inactive'}]
function Surface({family,props,ctx}:any){
 const dictionaries:any={preset:[presetEn,presetZh],goal:[goalEn,goalZh],skill:[skillEn,skillZh],jobs:[jobEn,jobZh],manager:[taskEn,taskZh]}
 const [en,zh]=dictionaries[family],t=createTranslator(ctx.case.locale,{en,zh})
 let body:any
 if(family==='preset')body=<AgentPresetSection {...{useAgentPresetSection:(s:any)=>s({rows:presets,loading:false,saving:false,error:null,view:null}),useDeveloperTools:(s:any)=>s(props.name==='coding'),load:asyncNoop,view:asyncNoop,closeView:noop,makeDefault:asyncNoop,startCreatorDraft:noop,close:noop,t} as any}/>
 if(family==='goal')body=<GoalBar {...{goal:{id:'synthetic-goal',revision:1,objective:'Synthetic objective',phase:props.name,maxGoalRounds:12,...(props.name==='blocked'?{blockedReason:{message:'Synthetic blocked reason'}}:{})},activation:'armed',onEdit:asyncNoop,onPause:asyncNoop,onResume:asyncNoop,onClear:asyncNoop,t} as any}/>
 if(family==='skill'){
  const call={callId:'synthetic-skill',name:'skill',argsRaw:'{"name":"review"}',phase:'start'}
  const block=props.name==='running'?call:{kind:'tool-result',seq:10,time:1000,callId:call.callId,name:'skill',call:{name:'skill',argsRaw:call.argsRaw},content:[{type:'text',text:props.name==='error'?'Synthetic failure\nFurther details':'Synthetic review instructions\nCheck the diff and report findings.'}],isError:props.name==='error',subCalls:[]}
  body=<SkillRow {...{block,toolName:'skill',t} as any}/>
 }
 if(family==='jobs')body=<JobListAction {...{sessionId:'synthetic-session',useJobs:(s:any)=>s({rows:{'synthetic-session':[{id:'synthetic-job',kind:'shell',label:'synthetic command',status:'running',startedAt:1000,output:{earliest:0,total:39}}]},observed:{}}),watchRows:release,observe:release,killJob:async()=>true,t} as any}/>
 if(family==='manager')body=<TaskManagerPage {...{useCatalog:(s:any)=>s({records:props.name==='empty'?[]:tasks,status:'ready',deleting:[],settled:true,readRequest:1,readSettled:1}),onNewTask:noop,onRetry:asyncNoop,onUpdateTiming:asyncNoop,onDelete:async()=> 'deleted',loadHistory:asyncNoop,onOpenSession:noop,useSessions:(s:any)=>s({phase:'ready',ids:[],byId:{}}),useWorkspaces:(s:any)=>s({phase:'ready',state:'ready',items:[],archivedSessionIds:[]}),t} as any}/>
 return <div data-parity-id="agents-tasks-surface" style={{width:props.width,height:props.height,overflow:family==='preset'?'auto':undefined,color:'var(--dsw-alias-label-primary)'}}>{body}</div>
}
export const kinds:Record<string,KindRenderer>=Object.fromEntries(['preset','goal','skill','jobs','manager'].map(f=>[`agents-tasks.${f}`,(props:any,ctx:any)=><Surface family={f} props={props} ctx={ctx}/>]))
