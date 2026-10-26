import fs from 'node:fs'
import {loadDsh,settle} from './settings_loader.mjs'
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh({extraNodeDirs:[process.env.PARITY_WEB_DEPS,process.env.PARITY_VT_DEPS].filter(Boolean)})
const manager=await load('packages/client/ui-plugin-manager/src/client/manager-store.ts')
const display=await load('packages/client/ui-plugin-manager/src/client/presentation.ts')
const market=await load('packages/client/ui-plugin-market/src/client/presentation.ts')
const ok=value=>({ok:true,value})
function controller(remote) {
 const source={getSnapshot:()=>[],subscribe:()=>()=>{}}
 const ctx={get:()=>undefined,remote:{pluginManager:remote,pluginRegistryProbe:{fastest:async()=>ok(null)},pluginInventory:{list:async()=>ok({managementAvailable:true,entries:[]})}},configForms:{describe:()=>source,get:()=>null}}
 const model=new manager.PluginManagerController(ctx)
 const face=model.inject(source,source,text=>typeof text==='string'?text:text.en)
 return {model,face}
}
const base={registries:async()=>ok({registry:null,resolved:null,fallbackRegistries:[]}),inspect:async()=>ok({status:'accepted',kind:'registry',name:'package',bundle:true,registry:null}),listBundles:async()=>ok([]),listPlugins:async()=>ok([])}
const phases=[]
let finish
const held=new Promise(resolve=>{finish=resolve})
let cancelled=0
const {model,face}=controller({...base,installBundle:async()=>held,cancelInstall:async()=>ok({status:++cancelled===1?'not-running':'too-late'})})
face.openInstall();await settle();face.editInstallSpec('package');face.runInstall();await settle()
phases.push(model.getSnapshot().install.phase)
face.cancelInstall();await settle();phases.push(model.getSnapshot().install.phase)
model.installProgress({requestId:model.getSnapshot().install.requestId,phase:'installing'});await settle();phases.push(model.getSnapshot().install.phase)
model.installProgress({requestId:model.getSnapshot().install.requestId,phase:'installing'});await settle();phases.push(model.getSnapshot().install.phase)
finish(ok({changed:true,application:'restart-required',stage:'install',target:'package'}));await settle();phases.push(model.getSnapshot().install.phase)
model.dispose()
const lost=controller({...base,installBundle:async()=>({ok:false,error:{code:'transport/lost',message:'lost'}}),waitForInstall:async()=>ok(null)})
lost.face.openInstall();await settle();lost.face.editInstallSpec('package');lost.face.runInstall();await settle()
const lostPhase=lost.model.getSnapshot().install.phase;lost.model.dispose()
process.stdout.write(JSON.stringify({
 shortNames:input.names.map(display.shortName),
 registryKeys:input.keys.map(v=>manager.registryKey(v.registry,v.resolved)),
 offers:input.registries.map(manager.offeredRegistries),
 packages:manager.sortPackages(input.bundles.map(b=>manager.packageView(b,input.plugins))),
 queries:input.queries.map(q=>market.withText(q.query,q.text)),
 declared:input.queries.map(q=>market.declaredQuery(q.query,input.metadata)),
 pending:input.phases.map(manager.isInstallPending),
 cancellation:{phases,calls:cancelled},lostPhase,
}))
