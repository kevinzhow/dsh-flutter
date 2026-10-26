import fs from 'node:fs'
import {register} from 'node:module'
import {loadDsh,settle} from './settings_loader.mjs'
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh({extraNodeDirs:[process.env.PARITY_WEB_DEPS]})
register(new URL('./ignore-css-loader.mjs',import.meta.url),import.meta.url)
const {WebSearchCardController}=await load('packages/client/ui-settings-web-search/src/client/web-search-card-controller.ts')
const {SubagentModelSelectionCardController}=await load('packages/client/ui-settings-subagent/src/client/subagent-model-selection-card-controller.ts')
const clone=x=>JSON.parse(JSON.stringify(x))
function scope(initial,ns,calls){
 let snapshot={status:'ready',value:clone(initial),base:clone(initial),user:{},writable:true,revision:3};const listeners=new Set()
 let fail=false
 return {getSnapshot:()=>snapshot,subscribe:fn=>{listeners.add(fn);return()=>listeners.delete(fn)},
  setFailure:()=>{fail=true},replace:value=>{snapshot={...snapshot,value:clone(value),revision:snapshot.revision+1};for(const fn of listeners)fn()},
  mutate:async(ops,revision)=>{calls.push({ns,ops,revision:revision??null});if(fail){fail=false;return false}
   const user={...snapshot.user};for(const op of ops){if(op.op==='set')user[op.path[0]]=clone(op.value);else delete user[op.path[0]]}
   snapshot={...snapshot,user,value:{...snapshot.base,...user},revision:snapshot.revision+1};for(const fn of listeners)fn();return true},
 }
}
const web=[]
for(const c of input.web){
 const calls=[],keys=[]
 const scopes={web:scope(c.web,'web',calls),messages:scope(c.messages,'web-search-deepseek',calls),api:scope(c.api,'web-deepseek-api',calls)}
 const controller=new WebSearchCardController(scopes,{remote:{credentials:{describe:async refs=>({ok:true,value:Object.fromEntries(refs.map(ref=>[ref,{configured:keys.some(k=>k.ref===ref),writable:true}]))}),set:async(ref,value)=>{keys.push({ref,value});return{ok:true,value:undefined}}}}})
 const face=controller.inject();const trace=[]
 for(const action of [{op:'initial'},...c.actions]){
  // The actual WebSearchCard disables this gesture for invalid/failed or busy forms.
  if(action.op==='select'){const s=face.hooks.webSearchCard.getSnapshot();if(s.apiSwitchAvailable&&!s.apiSwitchBlocked&&s.writable&&!s.saving)face.setSearchApi(action.value)}
  if(action.op==='edit')face.edit(action.field,action.value)
  if(action.op==='reset')face.resetField(action.field)
  if(action.op==='save')face.save()
  if(action.op==='fail')scopes[action.scope].setFailure()
  if(action.op==='discard')face.discard()
  await settle()
  trace.push({state:face.hooks.webSearchCard.getSnapshot(),calls:clone(calls),keys:clone(keys)})
 }
 controller.dispose();web.push(trace)
}
const subagent=[]
for(const c of input.subagent){
 const calls=[],form=scope(c.initial,'subagent-model-selection-settings',calls)
 const controller=new SubagentModelSelectionCardController(form,{remote:{session:{modelCatalog:async()=>({ok:true,value:c.catalog})}}})
 const face=controller.inject();const trace=[]
 for(const action of [{op:'initial'},...c.actions]){
  if(action.op==='enable')face.toggleEnabled()
  if(action.op==='toggle')face.toggleModel(action.provider+'\0'+action.model)
  if(action.op==='save')face.save()
  if(action.op==='replace')form.replace(action.value)
  if(action.op==='discard')face.discard()
  await settle()
  trace.push({state:face.hooks.subagentModelSelectionCard.getSnapshot(),calls:clone(calls)})
 }
 controller.dispose();subagent.push(trace)
}
process.stdout.write(JSON.stringify({web,subagent}))
