import fs from 'node:fs'
import {loadDsh} from './settings_loader.mjs'
const fixture=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh()
const lib=await load('packages/client/ui-deliverables/src/client/turn-deliverables.ts')
const presented=await load('packages/client/ui-deliverables/src/presented.ts')
const changes=await load('packages/client/ui-deliverables/src/changes.ts')
const native=await load('packages/util/native-command/src/types.ts')
const def=lib.deliverablesDefinition
const stateJson=state=>({produced:state.produced,...state.presented===undefined?{}:{presented:state.presented},...state.changes===undefined?{}:{changes:state.changes}})
const sequences=fixture.sequences.map(c=>{
 const states=new Map()
 return c.events.map(event=>{
  const match=def.match(event)
  if(match){
   const full={...match,event}
   if(match.role==='start')states.set(match.id,def.start({},full))
   else if(states.has(match.id))states.set(match.id,def.update({state:states.get(match.id)},full))
  }
  const state=states.get(String(c.turn)),data=state===undefined?undefined:stateJson(state)
  const owner={seq:c.closing,turn:{data:{get:()=>data}}}
  return {data:data??null,produced:lib.producedForClosing(data,c.closing),presented:lib.presentedForClosing(owner),changes:lib.changesForClosing(owner)}
 })
})
const mutations=fixture.mutations.map(c=>{
 let state=def.start({},{event:{type:'turn/start',data:{turn:1}}})
 state=def.update({state},{event:{type:'tool/call',seq:1,data:{turn:1,callId:'synthetic',name:c.name,arguments:c.raw??JSON.stringify(c.args)}}})
 state=def.update({state},{event:{type:'tool/result',seq:2,surfaceOp:c.surface??'append',data:{turn:1,message:{isError:c.error??false,source:{callId:'synthetic'}},...Object.hasOwn(c,'meta')?{meta:c.meta}:{}}}})
 return state.produced
})
const mentions=fixture.mentions.map(c=>lib.producedFileMentions(c.paths,()=>{},path=>path,c.operations??[]).resolve(c.value)?.title??null)
const validation={files:fixture.files.map(presented.isPresentedFile),deliveries:fixture.deliveries.map(presented.isPresentedData),changes:fixture.changes.map(changes.isChangesEvent)}
const records={changedFiles:fixture.changedFiles.map(changes.isChangedFile),summaries:fixture.summaries.map(changes.isChangesSummary),diffs:fixture.diffs.map(changes.isChangesDiff),hosts:fixture.hosts.map(presented.isPresentedHost),applications:fixture.applications.map(value=>{try{native.parseNativeFileApplications(value);return true}catch{return false}})}
process.stdout.write(JSON.stringify({sequences,mutations,mentions,validation,records}))
