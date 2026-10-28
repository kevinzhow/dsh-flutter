import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/base.css";
import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/corner-shape.css";
import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/design-platform.css";
import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/focus.css";
import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/onboarding.css";
import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/scrollbar.css";
import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/gradient-shadow-text.css";
import "[workspace]/scratch/whalee-plugin-cards/tool/design-system/upstream/ui-theme/shiki.css";
import "[workspace]/dsh-flutter/.local/dsh-src/packages/client/web/src/base.css";

import * as React from 'react';
import * as Jsx from 'react/jsx-runtime';
import * as ReactDOM from 'react-dom';
import {createRoot} from 'react-dom/client';
import * as primitives from "[workspace]/scratch/whalee-plugin-cards/tool/parity-web/host/mocks/primitives.ts";
import {en,zh} from "[workspace]/dsh-flutter/.local/dsh-src/packages/client/ui-plugin-manager/src/client/locales.ts";
import {en as marketEn,zh as marketZh} from "[workspace]/dsh-flutter/.local/dsh-src/packages/client/ui-plugin-market/src/client/locales.ts";
import {createTranslator} from "[workspace]/scratch/whalee-plugin-cards/tool/parity-web/host/mocks/locale.ts";
const deps={'react':React,'react/jsx-runtime':Jsx,'react-dom':ReactDOM,
 '@deepseek-ai/dsh-client-ui-primitives':primitives,'@deepseek-ai/dsh-client-store':{},'@deepseek-ai/dsh-client-ui-slots':{}};
window.__ModuleLoader__={load:({factory}:any)=>factory((id:string)=>{if(!(id in deps))throw Error(id);return deps[id]})};
await import('./plugin-manager.js');
const Manager=(window as any).__PublishedManager,entry=(window as any).__pluginCardEntry;
const scenario=entry.variant.props.scenario,pkg=scenario.package,noop=()=>{};
const t=createTranslator(entry.case.locale,{en,zh});(window as any).__cardTranslate=t;
const resolveText=(value:any)=>typeof value==='string'?value:value?.[entry.case.locale]??value?.[entry.case.locale.split('-')[0]]??value?.en??Object.values(value??{})[0]??'';
const calls={attempts:0,refusals:0,opens:0,requestedValues:[] as boolean[]};(window as any).__cardCalls=calls;
function Scene(){
 const[enabled,setEnabled]=React.useState(pkg.enabled),[view,setView]=React.useState({kind:'list'}),[tab,setTab]=React.useState('installed');
 const actions=Object.fromEntries(['ensure','refresh','openInstall','installFrom','closeInstall','editInstallSpec','runInstall','update','cancelInstall','reconcileInstall','toggleInstallDetails','toggleRegistryOptions','chooseRegistry','changeRegistry','useGithubMirror','approveBuildsAndRetry','enableInstalled','clearHighlight','setEnabled','uninstall','confirm','cancelConfirm','setRowEnabled','dismissNotice'].map(key=>[key,noop]));
 actions.setEnabled=(name:string,value:boolean)=>{calls.attempts++;calls.requestedValues.push(value);if(scenario.refuseToggle){calls.refusals++;return}setEnabled(value)};
 const state={status:'ready',refreshStatus:'idle',packages:[{...pkg,enabled}],busy:scenario.busy?[pkg.name]:[],notice:null,confirm:null,highlight:null,
 install:{open:false,spec:'',registries:{registry:null,resolved:'https://registry.npmjs.org/',fallbackRegistries:[]},registry:{kind:'offered',registry:null},registryOpen:false,registryError:false,attempts:null,phase:'idle',inputError:null,subject:null,runs:[],detailsOpen:false,installed:null,installedVersion:null,restartRequired:false,failure:null,approvedBuilds:[],enabling:false}};
 return <div data-plugin-cards-capture><Manager {...actions} t={t} resolveText={resolveText} renderSlot={()=>null}
 usePluginManager={(s:any)=>s(state)} useConfigLedger={(s:any)=>s({items:[],bundles:new Set(),rows:new Set()})}
 useConfigurations={(s:any)=>s({view:null})} usePluginTabs={(s:any)=>s([{id:'discover',label:createTranslator(entry.case.locale,{en:marketEn,zh:marketZh})('title')}])}
 useStore={(s:any)=>s({view,tab})} actions={{setView:(next:any)=>{calls.opens++;setView(next)},setTab}} /></div>;
}
document.documentElement.style.colorScheme=entry.case.theme;
document.documentElement.dataset.dsThemeSource=entry.case.theme;
document.documentElement.lang=entry.case.locale;
document.body.toggleAttribute('data-ds-dark-theme',entry.case.theme==='dark');
document.body.style.margin='0';document.body.style.background='var(--dsw-alias-bg-base)';
createRoot(document.getElementById('root')!).render(<Scene/>);
