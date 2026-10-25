// Real upstream rows and action dialogs; only Host/state hooks are fixtures.
import {useEffect} from 'react'
import {SessionNodeItem,ProjectRowItem} from '@dsh/ui-workspace/src/client/rows/Rows.tsx'
import {SessionRenameDialog,RenameSessionMenuItem} from '@dsh/ui-workspace/src/client/session-actions/RenameSession.tsx'
import {SessionArchiveConfirmDialog,ArchiveSessionMenuItem,ArchiveSessionRowButton} from '@dsh/ui-workspace/src/client/session-actions/ArchiveSession.tsx'
import {PinSessionMenuItem,PinSessionRowButton} from '@dsh/ui-workspace/src/client/session-actions/PinSession.tsx'
import {ForkSessionMenuItem} from '@dsh/ui-workspace/src/client/session-actions/ForkSession.tsx'
import {SessionIdMenuItem} from '@dsh/ui-workspace/src/client/session-actions/SessionId.tsx'
import {en,zh} from '@dsh/ui-workspace/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
const NOW=Date.UTC(2026,9,1,12)
const activity=[{kind:'turn'},{kind:'job',items:[{id:'check',label:'Synthetic check'}]}]
const wait=()=>new Promise<void>(()=>{})
function Tags(){useEffect(()=>{
 const update=()=>{
  const row=document.querySelector('[role="treeitem"]')
  row?.setAttribute('data-parity-id','session-row-s1')
  row?.querySelector('button')?.setAttribute('data-parity-id','session-row-menu-s1')
  const hover=document.querySelector('div[role="button"][tabindex="0"]')
  if(hover?.getAttribute('data-parity-id')!=='workspace-hover-card')hover?.setAttribute('data-parity-id','workspace-hover-card')
  const dialog=document.querySelector('[role="dialog"]')
  const buttons=dialog?.querySelectorAll('button')
  if(buttons?.length)buttons[buttons.length-1]?.setAttribute('data-parity-id','workspace-action-confirm')
 }
 update();const observer=new MutationObserver(update);observer.observe(document.body,{childList:true,subtree:true});return()=>observer.disconnect()
},[]);return null}
function Row({props,ctx}:any){
 const t=createTranslator(ctx.case.locale,{en,zh})
 const pinned=props.name==='pinned',archived=props.name==='archived'
 const node={id:'s1',title:props.long?'Synthetic session title that continues well beyond the available width':'Synthetic session',blank:false,updatedAt:NOW-300000,running:props.name==='running',runningSubagentCount:0,completed:false,pinned,archived,...props.name==='pending'?{pendingInteraction:'question'}:{}}
 const common={usePinned:(sel:any)=>sel(new Set(pinned?['s1']:[])),useArchived:(sel:any)=>sel(new Set(archived?['s1']:[])),pinSession:()=>{},unpinSession:()=>{},archiveSession:()=>{},unarchiveSession:()=>{},useShortcuts:(sel:any)=>sel([]),useSessionAccess:()=>true,forkSession:()=>{},requestSessionRename:()=>{},copySessionId:async()=>{},t}
 const renderSlot=(seat:string,owner:any,options:any)=>{
  if(seat==='sidebar.workspaces.session.menu.item'){
   const injected={...common,...owner,useMenuOpenState:()=>options.hookContext}
   return <><PinSessionMenuItem {...injected}/><RenameSessionMenuItem {...injected}/><ForkSessionMenuItem {...injected}/><ArchiveSessionMenuItem {...injected}/><SessionIdMenuItem {...injected}/></>
  }
  if(seat==='sidebar.workspaces.session.row.action')return <><ArchiveSessionRowButton {...common as any} {...owner}/><PinSessionRowButton {...common as any} {...owner}/></>
  return null
 }
 return <div style={{width:props.width}}><Tags/><SessionNodeItem node={node as any} currentId={undefined} now={NOW} onOpen={()=>{}} onRenameRequest={()=>{}} renderSlot={renderSlot as any} t={t as any}/></div>
}
function Group({props,ctx}:any){
 const t=createTranslator(ctx.case.locale,{en,zh})
 const group={key:'a',workspaceId:'a',cwd:'/synthetic/a',createdAt:NOW, label:'Synthetic project',expanded:true,containsCurrent:false,sessions:[],sessionCount:1}
 return <div data-parity-id="workspace-row-a" style={{width:props.width}}><ProjectRowItem group={group as any} onToggle={()=>{}} onCreate={()=>{}} actions={{rename:()=>{},delete:()=>{}}} t={t as any}/></div>
}
function Dialog({props,ctx}:any){
 const t=createTranslator(ctx.case.locale,{en,zh})
 const submit=async()=>{if(props.name==='pending')await wait();if(props.name==='refused')throw Error('Synthetic refusal')}
 const request={sessionId:'s1',currentTitle:'Synthetic session',displayTitle:'Synthetic session',activity}
 return <><Tags/>{props.archive?
  <SessionArchiveConfirmDialog useArchiveRequest={((sel:any)=>sel(request)) as any} settleSessionArchive={()=>{}} stopAndArchiveSession={submit} t={t as any} {...{} as any}/>:
  <SessionRenameDialog useRenameRequest={((sel:any)=>sel(request)) as any} settleSessionRename={()=>{}} renameSession={submit} t={t as any} {...{} as any}/>}</>
}
export const kinds:Record<string,KindRenderer>={
 'workspace-management.row':(p,c)=><Row props={p} ctx={c}/>,
 'workspace-management.group':(p,c)=><Group props={p} ctx={c}/>,
 'workspace-management.dialog':(p,c)=><Dialog props={p} ctx={c}/>,
}
