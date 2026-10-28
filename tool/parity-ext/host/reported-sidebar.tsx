// Actual upstream sidebar root, workspace browser, settings shell and account
// launcher. Only slots, stores and network actions carry synthetic fixture data.
import {useLayoutEffect, useMemo, useRef, useState} from 'react'
import {SidebarRoot} from '@dsh/ui-sidebar/src/client/SidebarRoot.tsx'
import {WorkspaceBrowser} from '@dsh/ui-workspace/src/client/rows/WorkspaceBrowser.tsx'
import {SettingsRoot} from '@dsh/ui-settings-general/src/client/SettingsRoot.tsx'
import {AccountMenu} from '@dsh/ui-settings-account/src/client/AccountMenu.tsx'
import {IconClockOutlineRegular, IconPersonalizationOutlineRegular, IconProjectAddOutlineRegular} from '@deepseek-ai/dsh-client-ui-primitives'
import {en as sidebarEn,zh as sidebarZh} from '@dsh/ui-sidebar/src/client/locales.ts'
import {en as workspaceEn,zh as workspaceZh} from '@dsh/ui-workspace/src/client/locales.ts'
import {en as settingsEn,zh as settingsZh} from '@dsh/ui-settings-general/src/client/locales.ts'
import {en as accountEn,zh as accountZh} from '@dsh/ui-settings-account/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
const noop=()=>{}, asyncNoop=async()=>{}, release=()=>noop
const fixed=(state:any)=>(selector:any)=>selector(state)
function ReportedSidebar({props,ctx}:any){
 const darwin=props.platform==='darwin', rail=props.collapsed===true
 const originalPlatform=useRef(document.documentElement.getAttribute('data-platform'))
 // The real component reads the preload mark during its render.
 if(darwin)document.documentElement.dataset.platform='darwin';else document.documentElement.removeAttribute('data-platform')
 useLayoutEffect(()=>()=>{const value=originalPlatform.current;if(value===null)document.documentElement.removeAttribute('data-platform');else document.documentElement.setAttribute('data-platform',value)},[])
 const tSidebar=createTranslator(ctx.case.locale,{en:sidebarEn,zh:sidebarZh})
 const tWorkspace=createTranslator(ctx.case.locale,{en:workspaceEn,zh:workspaceZh})
 const tSettings=createTranslator(ctx.case.locale,{en:settingsEn,zh:settingsZh})
 const tAccount=createTranslator(ctx.case.locale,{en:accountEn,zh:accountZh})
 const zh=ctx.case.locale.startsWith('zh')
 const [current,setCurrent]=useState<string|undefined>('s2')
 const [panel,setPanel]=useState<string|null>(null)
 const [settingsOpen,setSettingsOpen]=useState(false)
 const [view,setView]=useState({groupBy:'workspace',orderBy:'updated',groupExpansion:{w1:true} as Record<string,boolean>,sessionOrderByAccount:{},archivedFilter:'default'})
 const useStore=fixed(view)
 const actions={setGroupExpanded:(key:string,value:boolean)=>setView(v=>({...v,groupExpansion:{...v.groupExpansion,[key]:value}})),
  setGroupBy:(groupBy:string)=>setView(v=>({...v,groupBy})),setOrderBy:(orderBy:string)=>setView(v=>({...v,orderBy})),
  setArchivedFilter:(archivedFilter:string)=>setView(v=>({...v,archivedFilter})),retainAccountKeys:noop,syncSessionOrders:noop,setSessionOrder:noop}
 const now=useMemo(()=>Date.now(),[])
 const sessions=useMemo(()=>({phase:'ready',ids:['s1','s2'],projectionsBySession:{},byId:Object.fromEntries([1,2].map(i=>[`s${i}`,{id:`s${i}`,displayTitle:i===1?'分析合成项目进展':'分析下一步合成任务',title:i===1?'分析合成项目进展':'分析下一步合成任务',blank:false,running:false,updatedAt:now-(i+2)*86400000,retainedBy:{mainView:current===`s${i}`?1:0}}]))}),[current,now])
 const workspaces=useMemo(()=>({phase:'ready',state:'idle',error:null,archivedSessionIds:[],pinnedSessionIds:[],items:[
  {workspaceId:'w1',title:'synthetic',path:'/synthetic',createdAt:'2026-01-01T00:00:00.000Z',updatedAt:'2026-01-01T00:00:00.000Z',sessionIds:['s1','s2']},
  {workspaceId:'w2',title:'default-workspace',path:'/default',createdAt:'2026-01-01T00:00:00.000Z',updatedAt:'2026-01-01T00:00:00.000Z',sessionIds:[]},
 ]}),[])
 const useSessions=fixed(sessions),usePanelInfo=fixed({activePanelId:panel})
 const sidebarProps={collapsed:rail,width:rail?56:props.width,startSession:()=>setCurrent(undefined),toggleSidebar:noop,selectPanel:setPanel,usePanels:fixed([{id:'plugins',label:zh?'插件':'Plugins'},{id:'schedule',label:zh?'自动化任务':'Automation tasks'}]),useShortcuts:fixed([]),usePanelInfo,t:tSidebar}
 const render=(seat:string,owner:any,options:any):any=>{
  if(seat==='sidebar.brand.mark')return <span style={{display:'inline-flex',width:24,height:24,alignItems:'center',justifyContent:'center',fontSize:24,lineHeight:'24px'}}>🐳</span>
  if(seat==='sidebar.brand.name')return 'Whalee'
  if(seat==='sidebar.panellist')return options.only==='plugins'?<IconPersonalizationOutlineRegular size={owner.size}/>:<IconClockOutlineRegular size={owner.size}/>
  if(seat==='sidebar.workspaces')return <WorkspaceBrowser {...{
   ...owner,useStore,actions,useSessions,usePanelInfo,useSessionStatus:fixed(new Map()),useWorkspaces:fixed(workspaces),
   useShortcuts:fixed([]),useWorkspaceShortcuts:fixed({addRequested:false,searchRequested:0}),useHostInfo:fixed({home:undefined,isLoopback:true}),
   useDirectoryFlow:fixed(true),requestSearch:noop,requestAddWorkspace:noop,closeAddWorkspace:noop,setDirectoryBusy:noop,
   useSessionRetainInfo:()=>undefined,useSessionAccess:()=>true,useResource:()=>({status:'none'}),
   startSession:()=>setCurrent(undefined),open:setCurrent,requestSessionRename:noop,notifyArchivedNotOpenable:noop,
   renameWorkspace:asyncNoop,deleteWorkspace:asyncNoop,insertWorkspaceBefore:asyncNoop,unarchiveSession:asyncNoop,createWorkspace:asyncNoop,
   searchSessions:async()=>({items:[],hasMore:false}),searchResultLimit:20,renderSlot:()=>null,t:tWorkspace,
  } as any}/>
  if(seat==='sidebar.settings')return <SettingsRoot {...{
   ...owner,useConnectionState:fixed('connected'),reconnect:asyncNoop,useSections:fixed([]),useOnboardingSteps:fixed([]),
   useSessions,useDesktopUpdate:fixed({presentation:undefined}),openDesktopUpdate:noop,
   useStore:fixed({open:settingsOpen,activeId:undefined}),actions:{open:()=>setSettingsOpen(true),close:()=>setSettingsOpen(false),select:noop},useShortcuts:fixed([]),t:tSettings,
   renderSlot:(slot:string,share:any)=>{
    if(slot==='settings.launcher')return <AccountMenu {...{
     ...share,useAccount:fixed({view:{status:'none'},loginVisible:false}),useTheme:fixed({active:{colorScheme:ctx.case.theme}}),
     subscribeSessionExpired:release,subscribeModelSignInRequired:release,refreshAccount:asyncNoop,
     signOut:asyncNoop,hasRunningAccountTasks:async()=>false,bonusNoticeShown:noop,bonusNoticeDismissed:noop,
     contactUs:noop,showLogin:noop,start:asyncNoop,cancel:noop,avatarFailed:noop,t:tAccount,
    } as any}/>
    if(slot==='settings.header')return tSettings('title')
    if(slot==='settings.close')return tSettings('close')
    return null
   },
  } as any}/>
  return null
 }
 const root=useRef<HTMLDivElement>(null)
 useLayoutEffect(()=>{
  const tag=()=>{
   const box=root.current
   box?.querySelector(`button[aria-label="${CSS.escape(tAccount('menu'))}"]`)?.setAttribute('data-parity-id','settings-trigger')
   box?.querySelector(`button[aria-label="${CSS.escape(tSidebar('session.new.label'))}"]`)?.setAttribute('data-parity-id','sidebar-new-session')
   box?.querySelectorAll('[role="treeitem"]').forEach((row,i)=>row.setAttribute('data-parity-id',`reported-sidebar-row-${i}`))
  }
  tag();const observer=new MutationObserver(tag);observer.observe(document.body,{childList:true,subtree:true});return()=>observer.disconnect()
 },[])
 return <div ref={root} data-parity-id="reported-sidebar-frame" style={{width:rail?56:props.width,height:props.height,background:'var(--dsw-specific-sidebar-fill)',color:'var(--dsw-alias-label-primary)'}}>
  <SidebarRoot {...sidebarProps as any} renderSlot={render as any}/>
 </div>
}
export const kinds:Record<string,KindRenderer>={'reported-sidebar.root':(props,ctx)=><ReportedSidebar props={props} ctx={ctx}/>}
