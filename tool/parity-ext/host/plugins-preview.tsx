import {PluginManagerPage} from '@dsh/ui-plugin-manager/src/client/PluginManagerPage.tsx'
import {en as managerEn,zh as managerZh} from '@dsh/ui-plugin-manager/src/client/locales.ts'
import {PluginInventorySettingsTab} from '@dsh/ui-settings-plugin-inventory/src/client/PluginInventorySettingsTab.tsx'
import {en as inventoryEn,zh as inventoryZh} from '@dsh/ui-settings-plugin-inventory/src/client/locales.ts'
import {DiscoverSection} from '@dsh/ui-plugin-market/src/client/DiscoverSection.tsx'
import {en as marketEn,zh as marketZh} from '@dsh/ui-plugin-market/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
const noop=()=>{},asyncNoop=async()=>{},resolveText=(text:any)=>typeof text==='string'?text:(text.en??Object.values(text)[0]??'')
const pkg={name:'@synthetic/preview-bundle',official:false,availability:'profile',installed:true,enabled:true,optional:false,removable:true,version:'1.0.0',meta:{title:'Synthetic preview bundle',description:'Synthetic package for native interaction checks.'},rows:[{rowId:'reader',moduleName:'@synthetic/reader',entryId:'synthetic-entry',enabled:true,phase:'active'}]}
const entry={entryId:'synthetic-entry',moduleName:'@synthetic/reader',enabled:true,fiberPhase:'active'}
function Surface({family,props,ctx}:any){
 const dictionaries:any={manager:[managerEn,managerZh],inventory:[inventoryEn,inventoryZh],market:[marketEn,marketZh]}
 const [en,zh]=dictionaries[family],t=createTranslator(ctx.case.locale,{en,zh}),name=props.name
 let body:any
 if(family==='manager'){
  const install={open:name==='install',spec:'',registries:{registry:null,resolved:'https://registry.npmjs.org/',fallbackRegistries:[]},registry:{kind:'offered',registry:null},registryOpen:false,registryError:false,attempts:null,phase:'idle',inputError:null,subject:null,runs:[],detailsOpen:false,installed:null,installedVersion:null,restartRequired:false,failure:null,approvedBuilds:[],enabling:false}
  const state={status:name==='unavailable'?'unavailable':'ready',refreshStatus:'idle',packages:name==='populated'?[pkg]:[],busy:[],notice:null,install,confirm:null,highlight:null}
  const actions=Object.fromEntries(['ensure','refresh','openInstall','installFrom','closeInstall','editInstallSpec','runInstall','update','cancelInstall','reconcileInstall','toggleInstallDetails','toggleRegistryOptions','chooseRegistry','changeRegistry','useGithubMirror','approveBuildsAndRetry','enableInstalled','clearHighlight','setEnabled','uninstall','confirm','cancelConfirm','setRowEnabled','dismissNotice'].map(key=>[key,noop]))
  body=<PluginManagerPage {...{...actions,t,resolveText,renderSlot:()=>null,usePluginManager:(s:any)=>s(state),useConfigLedger:(s:any)=>s({items:[],bundles:new Set(),rows:new Set()}),useConfigurations:(s:any)=>s({view:null}),usePluginTabs:(s:any)=>s([{id:'discover',label:createTranslator(ctx.case.locale,{en:marketEn,zh:marketZh})('title')}]),useStore:(s:any)=>s({view:{kind:'list'},tab:'installed'}),actions:{setView:noop,setTab:noop}} as any}/>
 }
 if(family==='inventory')body=<PluginInventorySettingsTab {...{t,resolveText,list:async()=>({managementAvailable:true,entries:name==='empty'?[]:[entry],agentPresets:[]}),presetName:(p:any)=>p.id,useClientSync:(s:any)=>s({syncing:false,failures:[],entries:[]}),retryClient:noop} as any}/>
 if(family==='market'){
  const index={url:'https://synthetic.example/index.json',status:'ready',name:'Synthetic market',title:'Synthetic market',description:'Synthetic index',entryCount:0,fetchedAt:1000}
  const query={text:'',category:null,labels:[],sort:{kind:'index'}}
  const state={status:'ready',indexes:name==='noindexes'?[]:[index],selected:name==='noindexes'?null:index.url,listing:name==='noindexes'?null:{url:index.url,query,status:'ready',value:{url:index.url,title:'Synthetic market',metadata:{categories:{},labels:{},sortKeys:{}},entries:[],total:0,nextOffset:null,fetchedAt:1000},answered:query,failure:null},editing:false,draft:'',saving:false,sourceFailure:null}
  body=<DiscoverSection {...{t,resolveText,useDiscover:(s:any)=>s(state),useLocale:(s:any)=>s({active:ctx.case.locale}),ensure:noop,reload:noop,select:noop,search:noop,more:noop,refresh:noop,retry:noop,toggleSources:noop,editDraft:noop,addSource:asyncNoop,removeSource:asyncNoop,install:noop,openPackage:noop} as any}/>
 }
 return <div data-parity-id="plugins-preview-surface" style={{width:props.width,height:props.height,overflow:'auto',color:'var(--dsw-alias-label-primary)'}}>{body}</div>
}
export const kinds:Record<string,KindRenderer>=Object.fromEntries(['manager','inventory','market'].map(f=>[`plugins-preview.${f}`,(props:any,ctx:any)=><Surface family={f} props={props} ctx={ctx}/>]))
