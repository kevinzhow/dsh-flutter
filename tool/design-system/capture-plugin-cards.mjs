// Source scripts/pr16-env.sh, then run with --archives and a NEW --out.
// Render the real published loaded PluginManagerPage using shared compiled scenarios.
// The sole bundle instrumentation exposes private component bindings at the
// factory's final return; their bodies, styles, events and native buttons stay
// byte-for-byte published. Supporting primitives are pinned upstream modules.
import {readFile, writeFile, mkdir, access} from 'node:fs/promises'
import {resolve, join, dirname, extname} from 'node:path'
import {fileURLToPath, pathToFileURL} from 'node:url'
import {createHash} from 'node:crypto'
import {execFileSync} from 'node:child_process'
import {createServer} from 'node:http'
import assert from 'node:assert/strict'

const argv = Object.fromEntries(process.argv.slice(2).reduce((all, a, i, args) => {
  if (a.startsWith('--')) all.push([a.slice(2), args[i + 1]])
  return all
}, []))
for (const key of ['archives', 'out', 'repo', 'plan']) if (!argv[key]) throw Error(`Missing --${key}`)
const repo = resolve(argv.repo)
const out = resolve(argv.out), archives = resolve(argv.archives)
try {await access(out); throw Error('Refusing to overwrite a source trace')}
catch (error) {if (error.code !== 'ENOENT') throw error}
await mkdir(out, {recursive: true})
const sha = bytes => createHash('sha256').update(bytes).digest('hex')
const json = async path => JSON.parse(await readFile(path, 'utf8'))
const lock = await json(join(repo, 'tool/design-system/sources.lock.json'))
const source = resolve(process.env.DSH_SRC)
assert.equal(execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), lock.referenceCommit)
assert.equal(execFileSync('git', ['-C', source, 'status', '--porcelain', '--untracked-files=all'], {encoding:'utf8'}).trim(), '')
const modules = join(process.env.PARITY_WEB_DEPS, 'node_modules')
const {build} = await import(pathToFileURL(join(modules, 'vite/dist/node/index.js')))
const {chromium} = await import(pathToFileURL(join(modules, 'playwright-core/index.mjs')))
const host = join(out, 'host'), dist = join(out, 'dist')
await mkdir(host)
const provenance = {referenceCommit: lock.referenceCommit, packages: {}, sourceFiles: {}}
provenance.preparationRepository={head:execFileSync('git',['-C',repo,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),
 tree:execFileSync('git',['-C',repo,'rev-parse','HEAD^{tree}'],{encoding:'utf8'}).trim(),sourceOnly:true}
for (const file of [
  'packages/client/ui-primitives/src/Tooltip.tsx',
  'packages/client/ui-primitives/src/input-modality.ts',
  'packages/client/ui-primitives/src/Button.tsx',
  'packages/client/ui-plugin-manager/src/client/PluginManagerPage.tsx',
  'packages/client/ui-plugin-market/src/client/locales.ts',
  'packages/client/ui-sidebar/src/client/HeaderLeadingControls.tsx',
  'packages/client/web/src/base.css',
]) {
  const actual = sha(await readFile(join(source, file)))
  const pinned = lock.packages.map(p => p.referenceSourceSha256?.[file]).find(Boolean)
  if (pinned) assert.equal(actual, pinned)
  provenance.sourceFiles[file] = {sha256: actual, explicitHashLock: Boolean(pinned)}
}
for (const [name, binding, exposed] of [
  ['plugin-manager', 'PluginManagerPage', '__PublishedManager'],
]) {
  const pkg = lock.packages.find(p => p.name === `@deepseek-ai/dsh-client-ui-${name}`)
  assert.equal(pkg.version, '0.2.1-rc.2')
  const archive = join(archives, `deepseek-ai-dsh-client-ui-${name}-${pkg.version}.tgz`)
  const bytes = await readFile(archive)
  assert.equal('sha512-' + createHash('sha512').update(bytes).digest('base64'), pkg.integrity)
  const body = execFileSync('tar', ['-xOf', archive, 'package/lib/client.js'], {encoding: 'utf8', maxBuffer: 10 * 1024 * 1024})
  assert.equal(sha(body), pkg.publishedBundleSha256)
  const end = '\t\treturn module.exports;\n\t}\n});'
  assert.equal(body.split(end).length, 2)
  const hook = `\t\tglobalThis.${exposed} = ${binding};\n\t\tglobalThis.__CardCss = PluginManagerPage_module_css_default;\n`;
  const instrumented = body.replace(end, `${hook}${end}`)
  await writeFile(join(host, `${name}.js`), instrumented)
  provenance.packages[name] = {version: pkg.version, archiveSha256: sha(bytes), integrity: pkg.integrity,
    publishedBundleSha256: sha(body), instrumentedSha256: sha(instrumented), instrumentation: 'Expose PluginManagerPage and its static CSS class map before factory return only'}
}
const theme = lock.packages.find(p => p.snapshotFolder === 'ui-theme')
const order = await json(join(repo, 'tool/design-system/upstream/ui-theme/styles-order.json'))
let styles = ''
for (const file of order) {
  const path = join(repo, 'tool/design-system/upstream/ui-theme', file)
  assert.equal(sha(await readFile(path)), theme.files[file])
  styles += `import ${JSON.stringify(path)};\n`
}
styles += `import ${JSON.stringify(join(source,'packages/client/web/src/base.css'))};\n`
const fontManifest=await json(join(repo,'tool/parity-fonts/manifest.json'))
const fontFiles=new Map();let fontCss=''
provenance.fonts=[]
for(const family of fontManifest.families)for(const face of family.faces){
 const id=String(fontFiles.size)+extname(face.file),path=join(repo,'tool/parity-fonts',face.file)
 assert.equal(sha(await readFile(path)),face.sha256);fontFiles.set(id,path)
 provenance.fonts.push({file:face.file,sha256:face.sha256})
 for(const name of family.names)fontCss+=`@font-face{font-family:'${name}';font-weight:${face.weight};font-style:${face.style};src:url('/proof-fonts/${id}');font-display:block}`
}
await writeFile(join(host, 'index.html'), '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/proof-fonts.css"></head><body><div id="root"></div><script type="module" src="/entry.tsx"></script></body></html>')

const planBytes=await readFile(resolve(argv.plan)),plan=JSON.parse(planBytes)
const fixturePath=join(repo,'apps/dsh_flutter/test/parity/helpers/plugin_card_fixture.dart')
const fixtureBytes=await readFile(fixturePath),fixtureText=fixtureBytes.toString()
const literals=[...fixtureText.matchAll(/const pluginCardScenarioJson = r'''\n([\s\S]*?)\n''';/g)]
assert.equal(literals.length,1,'single compiled fixture data source required')
const fixture=JSON.parse(literals[0][1]);assert.equal(fixture.schema,'dsh-plugin-card-scenarios/1')
const scenarios=Object.fromEntries(fixture.scenarios.map(s=>[s.id,{...s,package:{...fixture.basePackage,...s.package}}]))
const entries=plan.cases.flatMap(c=>c.variants.map(v=>({key:v.id==='default'?c.id:c.id+'__'+v.id,case:c,variant:v})))
assert(entries.length>0);assert.equal(new Set(entries.map(e=>e.key)).size,entries.length)
for(const e of entries){
 assert.equal(e.case.kind,'plugin-cards.manager');assert(e.case.reactPathHint.startsWith('published @deepseek-ai/dsh-client-ui-plugin-manager@0.2.1-rc.2/'))
 assert.deepEqual(e.variant.props.scenario,scenarios[e.variant.props.scenarioId]);assert.equal(e.case.capture.crop,'viewport')
}
provenance.scenarioJsonSha256=sha(literals[0][1]);provenance.fixtureHelperSha256=sha(fixtureBytes)
provenance.planSha256=sha(planBytes);provenance.sourceLockSha256=sha(await readFile(join(repo,'tool/design-system/sources.lock.json')))
provenance.loadedRegionsSha256=sha(await readFile(join(repo,'tool/design-system/upstream/ui-plugin-manager/loaded-card-behavior.json')))
provenance.captureToolSha256=sha(await readFile(fileURLToPath(import.meta.url)))
provenance.scope='Actual published PluginManagerPage with shared offline scenario data; no source component body or stylesheet rewrite'
await writeFile(join(host, 'entry.tsx'), `${styles}
import * as React from 'react';
import * as Jsx from 'react/jsx-runtime';
import * as ReactDOM from 'react-dom';
import {createRoot} from 'react-dom/client';
import * as primitives from ${JSON.stringify(join(repo,'tool/parity-web/host/mocks/primitives.ts'))};
import {en,zh} from ${JSON.stringify(join(source,'packages/client/ui-plugin-manager/src/client/locales.ts'))};
import {en as marketEn,zh as marketZh} from ${JSON.stringify(join(source,'packages/client/ui-plugin-market/src/client/locales.ts'))};
import {createTranslator} from ${JSON.stringify(join(repo,'tool/parity-web/host/mocks/locale.ts'))};
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
`)
const installed = name => join(modules, name)
const npmPackage = name => name.split('/', name.startsWith('@') ? 2 : 1).join('/')
const sourcePrefix = source + '/'
await build({root: host, base: './', configFile: false, logLevel: 'warn',
  define: {'process.env.NODE_ENV': '"production"'},
  plugins: [{name:'source-dependencies',enforce:'pre',async resolveId(id, importer, options){
    if(!importer?.startsWith(sourcePrefix)||id.startsWith('.')||id.startsWith('/'))return null;
    try{await access(installed(npmPackage(id)))}catch{return null}
    return this.resolve(id,join(modules,'.proof-importer.js'),{...options,skipSelf:true});
  }}],
  resolve:{alias:[
    {find:'@dsh',replacement:join(source,'packages/client')},
    {find:/^@deepseek-ai\/dsh-client-store$/,replacement:join(repo,'tool/parity-web/host/mocks/client-store.ts')},
    {find:/^@deepseek-ai\/dsh-util-workspace-path$/,replacement:join(source,'packages/util/workspace-path/src/index.ts')},
    {find:/^@deepseek-ai\/dsh-util-code-language$/,replacement:join(source,'packages/util/code-language/src/index.ts')},
    {find:/^@deepseek-ai\/dsh-util-values$/,replacement:join(source,'packages/util/values/src/index.ts')},
    {find:/^react\/jsx-runtime$/,replacement:join(installed('react'),'jsx-runtime.js')},
    {find:/^react-dom\/client$/,replacement:join(installed('react-dom'),'client.js')},
    {find:/^react-dom$/,replacement:join(installed('react-dom'),'index.js')},
    {find:/^react$/,replacement:join(installed('react'),'index.js')},
    {find:/^clsx$/,replacement:join(installed('clsx'),'dist/clsx.mjs')},
  ]},oxc:{jsx:{runtime:'automatic'}},
  build:{outDir:dist,emptyOutDir:true,minify:false,sourcemap:false,cssCodeSplit:false,target:'es2022'},
})
await writeFile(join(out,'provenance.json'),JSON.stringify(provenance,null,2)+'\n')
const server=createServer(async(req,res)=>{
 try{const name=new URL(req.url,'http://127.0.0.1').pathname;
 if(name==='/fixture-icon.svg'){res.setHeader('Content-Type','image/svg+xml');res.end(await readFile(join(repo,'tool/icons/charcoal/images.svg')));return}
 if(name==='/proof-fonts.css'){res.setHeader('Content-Type','text/css');res.end(fontCss);return}
 if(name.startsWith('/proof-fonts/')){const file=fontFiles.get(name.slice('/proof-fonts/'.length));if(!file)throw Error('font');res.setHeader('Content-Type','font/ttf');res.end(await readFile(file));return}
 const file=resolve(dist,'.'+(name==='/'?'/index.html':name));if(!file.startsWith(dist+'/'))throw Error('outside');
 res.setHeader('Content-Type',{'.html':'text/html','.js':'text/javascript','.css':'text/css'}[extname(file)]??'application/octet-stream');res.end(await readFile(file));
 }catch{res.writeHead(404);res.end()}
})
await new Promise(done=>server.listen(0,'127.0.0.1',done))

const url=`http://127.0.0.1:${server.address().port}/`,traces=[]
const results=join(out,'visual-testing-results'),reference=join(results,'react')
await mkdir(reference,{recursive:true})
const capturePlan={reference:'native',resultsDir:results,fontsManifest:join(repo,'tool/parity-fonts/manifest.json'),
 fixturesDirs:[],runInfo:{source:'actual published 0.2.1-rc.2',sourcePlanSha256:provenance.planSha256},
 entries,coverage:plan.cases.map(c=>({id:c.id,kind:c.kind}))}
await writeFile(join(out,'flutter-plan.json'),JSON.stringify(capturePlan,null,2)+'\n')
const sourceInputs={};for(const [file,info] of Object.entries(provenance.sourceFiles))sourceInputs[join(source,file)]=info.sha256
const expectedHashes={plan:sha(planBytes),helper:sha(fixtureBytes),lock:provenance.sourceLockSha256}
try{
 for(const density of [...new Set(entries.map(e=>e.case.viewport.density))]){
  const browser=await chromium.launch({args:['--disable-lcd-text','--font-render-hinting=none',`--force-device-scale-factor=${density}`]})
  try{
   const selected=entries.filter(e=>e.case.viewport.density===density)
   const groups=new Map()
   for(const entry of selected){const c=entry.case,key=JSON.stringify([c.theme,c.locale,c.viewport.width,c.viewport.height]);if(!groups.has(key))groups.set(key,[]);groups.get(key).push(entry)}
   for(const group of groups.values()){
    const first=group[0].case,viewport={width:first.viewport.width,height:first.viewport.height}
    const context=await browser.newContext({viewport,deviceScaleFactor:density,colorScheme:first.theme,reducedMotion:'reduce',
     hasTouch:viewport.width<600,isMobile:viewport.width<600})
    for(const entry of group){
     const page=await context.newPage(),errors=[]
     page.on('pageerror',e=>errors.push(String(e)))
     await page.addInitScript(entry=>{window.__pluginCardEntry=entry},entry)
     await page.goto(url);await page.evaluate(()=>document.fonts.ready)
     assert.equal(await page.evaluate(()=>devicePixelRatio),density,'native Chromium density must match the plan')
     const scenario=entry.variant.props.scenario,pkg=scenario.package
     const card=page.locator('[data-plugin-package='+JSON.stringify(pkg.name)+']');await card.waitFor()
     await card.evaluate((el,id)=>el.setAttribute('data-parity-id',id),'plugin-card-'+pkg.name)
     for(const step of entry.variant.interactions??[]){
      const target=page.locator('[data-parity-id='+JSON.stringify(step.target)+']')
      if(step.type==='hover')await target.hover()
      else if(step.type==='press'){await target.hover();await page.mouse.down()}
      else if(step.type==='focus-by-tab'){
       let reached=false
       for(let i=0;i<40&&!reached;i++){await page.keyboard.press('Tab');reached=await target.evaluate(el=>el===document.activeElement||el.contains(document.activeElement))}
       assert(reached,'ordinary keyboard traversal must reach the actual card')
      }else throw Error('Unsupported card interaction '+step.type)
     }
     await page.evaluate(()=>new Promise(requestAnimationFrame))
     const actual=await card.evaluate(el=>{
      const css=window.__CardCss,read=node=>{if(!node)return null;const r=node.getBoundingClientRect(),s=getComputedStyle(node);return{bounds:[r.x,r.y,r.width,r.height],tag:node.tagName,text:node.textContent,color:s.color,background:s.backgroundColor,font:s.font,whiteSpace:s.whiteSpace,overflow:s.overflow,boxSizing:s.boxSizing}}
      const title=el.querySelector('.'+css.cardOpen),sw=el.querySelector('[role=switch]'),frame=el.querySelector('.'+css.cardIcon),artwork=frame?.firstElementChild
      return{card:read(el),title:read(title),description:read(el.querySelector('.'+css.cardDesc)),artworkFrame:read(frame),artwork:read(artwork),
       tags:[...el.querySelectorAll('.'+css.statusTag)].map(read),metadataError:read(el.querySelector('[data-package-meta-error]')),
       switch:{...read(sw),disabled:sw.disabled,checked:sw.getAttribute('aria-checked')},hover:el.matches(':hover'),focusedTitle:document.activeElement===title,
       titleFocusVisible:title.matches(':focus-visible'),titleOutline:{width:getComputedStyle(title,'::after').outlineWidth,style:getComputedStyle(title,'::after').outlineStyle},
       calls:{...window.__cardCalls}}
     })
     assert.equal(actual.switch.checked,String(scenario.expected.enabled));assert.equal(actual.switch.disabled,scenario.expected.locked)
     assert.deepEqual(actual.tags.map(tag=>tag.text),await page.evaluate(keys=>keys.map(k=>window.__cardTranslate(k)),scenario.expected.tagKeys))
     assert.equal(Boolean(actual.metadataError),Boolean(scenario.expected.metadataError))
     if(scenario.id==='no-description')assert.equal(actual.description,null)
     if(scenario.id==='image-failed')assert.equal(actual.artwork.tag,'svg')
     if(entry.variant.name==='focus')assert.equal(actual.titleFocusVisible,true)
     assert.deepEqual(errors,[])
     const file=entry.key+'.png';await page.screenshot({path:join(reference,file)})
     const image=await readFile(join(reference,file))
     const metadata={provider:'react',source:'actual published DSH 0.2.1-rc.2 PluginManagerPage',caseId:entry.case.id,
      variantId:entry.variant.id,captureKey:entry.key,theme:entry.case.theme,locale:entry.case.locale,viewport:entry.case.viewport,
      react:{dshCommit:lock.referenceCommit,publishedBundleSha256:provenance.packages['plugin-manager'].publishedBundleSha256},
      chromium:browser.version(),pixelModel:'native',actual,provenanceSha256:sha(JSON.stringify(provenance))}
     await writeFile(join(reference,entry.key+'.metadata.json'),JSON.stringify(metadata,null,2)+'\n')
     const checks=[{check:'actual source state, localized tags and errors',passed:true}],postCaptureProbes=[]
     if(scenario.expected.locked||scenario.refuseToggle){
      const sw=card.locator('[role=switch]'),bounds=await sw.boundingBox(),before=await sw.getAttribute('aria-checked')
      await page.mouse.click(bounds.x+bounds.width/2,bounds.y+bounds.height/2)
      const calls=await page.evaluate(()=>({...window.__cardCalls})),after=await sw.getAttribute('aria-checked')
      assert.equal(calls.attempts,scenario.refuseToggle?1:0);assert.equal(calls.refusals,scenario.refuseToggle?1:0)
      assert.equal(calls.opens,0);assert.equal(after,before)
      postCaptureProbes.push({input:'one actual switch click',bounds,before,after,calls})
      checks.push({check:'disabled absorption or refused controlled toggle does not open or change accepted state',passed:true})
     }
     traces.push({key:entry.key,scenarioId:scenario.id,state:entry.variant.name,theme:entry.case.theme,locale:entry.case.locale,viewport:entry.case.viewport,
      file:'visual-testing-results/react/'+file,sha256:sha(image),actual,checks,postCaptureProbes,errors})
     await writeFile(join(out,'source-trace.partial.json'),JSON.stringify({passed:false,provenance,traces},null,2)+'\n')
     if(entry.variant.name==='press')await page.mouse.up()
     await page.close()
    }
    await context.close()
   }
  }finally{await browser.close()}
 }
 assert.equal(traces.length,entries.length)
 assert.equal(sha(await readFile(resolve(argv.plan))),expectedHashes.plan)
 assert.equal(sha(await readFile(fixturePath)),expectedHashes.helper)
 assert.equal(sha(await readFile(join(repo,'tool/design-system/sources.lock.json'))),expectedHashes.lock)
 assert.equal(sha(await readFile(fileURLToPath(import.meta.url))),provenance.captureToolSha256)
 for(const [file,hash]of Object.entries(sourceInputs))assert.equal(sha(await readFile(file)),hash)
 for(const[name,packageInfo]of Object.entries(provenance.packages)){
  const archive=join(archives,`deepseek-ai-dsh-client-ui-${name}-${packageInfo.version}.tgz`)
  assert.equal(sha(await readFile(archive)),packageInfo.archiveSha256)
 }
 const receipt={schema:'whalee-plugin-card-published-source/1',passed:true,provenance,traces,
  captures:traces.length,sourceBodiesUnchanged:true,stylesUnchanged:true,
  pending:['SVG metadata image formats are not certified on native','highlight lifecycle and Chromium sticky touch hover remain pending','Source controlled-store callback probes are not production network parity']}
 await writeFile(join(out,'source-trace.json'),JSON.stringify(receipt,null,2)+'\n')
 console.log(JSON.stringify({passed:true,captures:traces.length,scenarios:Object.keys(scenarios).length,planSha256:provenance.planSha256}))
}finally{await new Promise(done=>server.close(done))}
