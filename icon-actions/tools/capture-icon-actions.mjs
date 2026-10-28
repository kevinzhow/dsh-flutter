// Source scripts/pr16-env.sh, then run with --archives and a NEW --out.
// Render the real published PluginManagerPage and HeaderLeadingControls.
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
for (const key of ['archives', 'out']) if (!argv[key]) throw Error(`Missing --${key}`)
const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const out = resolve(argv.out), archives = resolve(argv.archives)
try {await access(out); throw Error('Refusing to overwrite a source trace')}
catch (error) {if (error.code !== 'ENOENT') throw error}
await mkdir(out, {recursive: true})
const sha = bytes => createHash('sha256').update(bytes).digest('hex')
const json = async path => JSON.parse(await readFile(path, 'utf8'))
const lock = await json(join(repo, 'tool/design-system/sources.lock.json'))
const source = resolve(process.env.DSH_SRC)
assert.equal(execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), lock.referenceCommit)
const modules = join(process.env.PARITY_WEB_DEPS, 'node_modules')
const {build} = await import(pathToFileURL(join(modules, 'vite/dist/node/index.js')))
const {chromium} = await import(pathToFileURL(join(modules, 'playwright-core/index.mjs')))
const host = join(out, 'host'), dist = join(out, 'dist')
await mkdir(host)
const provenance = {referenceCommit: lock.referenceCommit, packages: {}, sourceFiles: {}}
for (const file of [
  'packages/client/ui-primitives/src/Tooltip.tsx',
  'packages/client/ui-primitives/src/input-modality.ts',
  'packages/client/ui-primitives/src/Button.tsx',
  'packages/client/ui-plugin-manager/src/client/PluginManagerPage.tsx',
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
  ['sidebar', 'HeaderLeadingControls', '__PublishedHeader'],
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
  const instrumented = body.replace(end, `\t\tglobalThis.${exposed} = ${binding};\n${end}`)
  await writeFile(join(host, `${name}.js`), instrumented)
  provenance.packages[name] = {version: pkg.version, archiveSha256: sha(bytes), integrity: pkg.integrity,
    publishedBundleSha256: sha(body), instrumentedSha256: sha(instrumented), instrumentation: `Expose ${binding} before factory return only`}
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
await writeFile(join(host, 'entry.tsx'), `${styles}
import * as React from 'react';
import * as Jsx from 'react/jsx-runtime';
import * as ReactDOM from 'react-dom';
import {createRoot} from 'react-dom/client';
import * as primitives from ${JSON.stringify(join(repo, 'tool/parity-web/host/mocks/primitives.ts'))};
const deps = {'react':React,'react/jsx-runtime':Jsx,'react-dom':ReactDOM,
 '@deepseek-ai/dsh-client-ui-primitives':primitives,
 '@deepseek-ai/dsh-client-store':{}, '@deepseek-ai/dsh-client-ui-slots':{}};
window.__ModuleLoader__={load:({factory}:any)=>factory((id:string)=>{if(!(id in deps))throw Error(id);return deps[id]})};
await import('./plugin-manager.js'); await import('./sidebar.js');
const Manager=(window as any).__PublishedManager,Header=(window as any).__PublishedHeader;
const noop=()=>{},calls={refresh:0,toggle:0,session:0};
(window as any).__traceCalls=calls;
function Scene(){
 const [mode,setMode]=React.useState('ready');(window as any).__traceMode=setMode;
 const actions=Object.fromEntries(['ensure','refresh','openInstall','installFrom','closeInstall','editInstallSpec','runInstall','update','cancelInstall','reconcileInstall','toggleInstallDetails','toggleRegistryOptions','chooseRegistry','changeRegistry','useGithubMirror','approveBuildsAndRetry','enableInstalled','clearHighlight','setEnabled','uninstall','confirm','cancelConfirm','setRowEnabled','dismissNotice'].map(key=>[key,noop]));
 actions.refresh=()=>{calls.refresh++};
 const state={status:mode==='disabled'?'unavailable':'ready',refreshStatus:'idle',packages:[],busy:[],notice:null,confirm:null,highlight:null,
 install:{open:false,spec:'',registries:{registry:null,resolved:'https://registry.npmjs.org/',fallbackRegistries:[]},registry:{kind:'offered',registry:null},registryOpen:false,registryError:false,attempts:null,phase:'idle',inputError:null,subject:null,runs:[],detailsOpen:false,installed:null,installedVersion:null,restartRequired:false,failure:null,approvedBuilds:[],enabling:false}};
 return <><div data-proof-manager style={{height:350}}><Manager {...actions} t={(key:string)=>key} resolveText={(s:any)=>s} renderSlot={()=>null}
 usePluginManager={(s:any)=>s(state)} useConfigLedger={(s:any)=>s({items:[],bundles:new Set(),rows:new Set()})}
 useConfigurations={(s:any)=>s({view:null})} usePluginTabs={(s:any)=>s([])}
 useStore={(s:any)=>s({view:{kind:'list'},tab:'installed'})} actions={{setView:noop,setTab:noop}} /></div>
 <div data-proof-header style={{position:'absolute',left:24,top:400}}><Header toggleSidebar={()=>{calls.toggle++}} startSession={()=>{calls.session++}}
 useShortcuts={(s:any)=>s([])} t={(key:string)=>key}/></div></>;
}
document.documentElement.style.colorScheme=(window as any).__traceTheme;
document.documentElement.dataset.dsThemeSource=(window as any).__traceTheme;
document.body.toggleAttribute('data-ds-dark-theme',(window as any).__traceTheme==='dark');
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
 try{const name=new URL(req.url,'[local-runtime-url]').pathname;
 if(name==='/proof-fonts.css'){res.setHeader('Content-Type','text/css');res.end(fontCss);return}
 if(name.startsWith('/proof-fonts/')){const file=fontFiles.get(name.slice('/proof-fonts/'.length));if(!file)throw Error('font');res.setHeader('Content-Type','font/ttf');res.end(await readFile(file));return}
 const file=resolve(dist,'.'+(name==='/'?'/index.html':name));if(!file.startsWith(dist+'/'))throw Error('outside');
 res.setHeader('Content-Type',{'.html':'text/html','.js':'text/javascript','.css':'text/css'}[extname(file)]??'application/octet-stream');res.end(await readFile(file));
 }catch{res.writeHead(404);res.end()}
})
await new Promise(done=>server.listen(0,'127.0.0.1',done))
const url=`[local-runtime-url]
try{
 for(const density of [1,2.625]){
  const browser=await chromium.launch({args:['--disable-lcd-text','--font-render-hinting=none',`--force-device-scale-factor=${density}`]})
  try{for(const themeName of ['light','dark'])for(const input of ['mouse','touch']){
   const viewport={width:input==='touch'?390:640,height:540}
   const outside={x:viewport.width-20,y:viewport.height-20}
   const context=await browser.newContext({viewport,deviceScaleFactor:density,hasTouch:input==='touch',isMobile:input==='touch',colorScheme:themeName,reducedMotion:'reduce'})
   const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(String(e)))
   await page.addInitScript(theme=>{window.__traceTheme=theme;window.__traceEvents=[];
    for(const type of ['pointerdown','pointerup','pointerenter','pointerleave','mousedown','mouseup','mouseover','mouseout','touchstart','touchend','click','focus','blur','keydown','keyup']){
     document.addEventListener(type,event=>{const el=event.target?.closest?.('button');if(!el)return;
      const c=getComputedStyle(el);window.__traceEvents.push({type,key:event.key,pointerType:event.pointerType,label:el.getAttribute('aria-label'),text:el.textContent,
       hover:el.matches(':hover'),active:el.matches(':active'),focusVisible:el.matches(':focus-visible'),background:c.backgroundColor,color:c.color,time:performance.now()});},true)
    }
   },themeName)
   await page.goto(url);const icon=page.locator('[data-proof-manager] button[aria-label="refresh"]');await icon.waitFor();await page.evaluate(()=>document.fonts.ready)
   assert.deepEqual(errors,[])
   const header=page.locator('[data-proof-header] button').first()
   const row={theme:themeName,density,input,viewport,chromium:browser.version(),snapshots:[],events:[],checks:[]}
   const read=locator=>locator.evaluate(el=>{const c=getComputedStyle(el),b=el.getBoundingClientRect(),svg=el.querySelector('svg')?.getBoundingClientRect();
    return {bounds:{x:b.x,y:b.y,width:b.width,height:b.height},icon:svg?{width:svg.width,height:svg.height}:null,
    disabled:el.disabled,hover:el.matches(':hover'),active:el.matches(':active'),focused:document.activeElement===el,focusVisible:el.matches(':focus-visible'),modality:document.documentElement.dataset.inputModality,
    background:c.backgroundColor,color:c.color,opacity:c.opacity,borderRadius:c.borderRadius,outlineColor:c.outlineColor,outlineWidth:c.outlineWidth,outlineStyle:c.outlineStyle,outlineOffset:c.outlineOffset,cursor:c.cursor}})
   const snap=async(profile,state,locator)=>{await page.evaluate(()=>new Promise(requestAnimationFrame));const actual=await read(locator);
    const file=`${themeName}-dpr${density}-${input}-${profile}-${state}.png`;await page.screenshot({path:join(out,file)});
    row.snapshots.push({profile,state,file,actual,calls:await page.evaluate(()=>({...window.__traceCalls}))});return actual}
   for(const [profile,locator] of [['iconAction',icon],['headerAction',header]]){
    await snap(profile,'idle',locator)
    const b=await locator.boundingBox(),point={x:b.x+b.width/2,y:b.y+b.height/2}
    if(input==='mouse'){
     await page.mouse.move(point.x,point.y);await snap(profile,'hover',locator)
     await page.mouse.down();await snap(profile,'held',locator)
     await page.mouse.move(b.x-1,point.y);await snap(profile,'held-away',locator)
     await page.mouse.move(point.x,point.y);await snap(profile,'held-return',locator)
     await page.mouse.up();await snap(profile,'released',locator)
     await page.mouse.move(outside.x,outside.y);await snap(profile,'pointer-away',locator)
    }else{
     const cdp=await context.newCDPSession(page)
     await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point]});await snap(profile,'touch-down',locator)
     await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await snap(profile,'touch-up',locator)
     // Observe Chromium's settled synthetic hover as well as the immediate
     // touch-up frame. This delay is observation only, never a product value.
     await page.waitForTimeout(500);await snap(profile,'touch-settled',locator)
     await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[outside]});
     await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await snap(profile,'outside-touch',locator)
     await cdp.detach()
    }
    await locator.focus();await page.keyboard.press('Home');await snap(profile,'home-focus',locator)
    await page.keyboard.press('Enter');await snap(profile,'enter-focus',locator)
    await locator.evaluate(el=>el.blur())
    const states=Object.fromEntries(row.snapshots.filter(s=>s.profile===profile).map(s=>[s.state,s.actual]))
    const sameFill=(a,b)=>{assert.equal(a.background,b.background);assert.equal(a.color,b.color)}
    assert.equal(states.idle.bounds.width,28);assert.equal(states.idle.bounds.height,28)
    if(input==='mouse'){
     assert.notEqual(states.hover.background,states.idle.background)
     sameFill(states.held,states.hover);sameFill(states['held-away'],states.idle)
     sameFill(states['held-return'],states.hover);sameFill(states['pointer-away'],states.idle)
    }else{
     sameFill(states['touch-down'],states.idle)
     assert.equal(states['touch-settled'].hover,true)
     assert.notEqual(states['touch-settled'].background,states.idle.background)
     sameFill(states['outside-touch'],states.idle)
    }
    assert.equal(states['home-focus'].focusVisible,true)
    assert.equal(states['home-focus'].outlineStyle,profile==='iconAction'?'solid':'auto')
    row.checks.push({profile,check:'source-hover-held-leave-or-touch-and-navigation',passed:true})
   }
   await page.evaluate(()=>window.__traceMode('disabled'));await page.waitForFunction(()=>document.querySelector('[data-proof-manager] button[aria-label="refresh"]').disabled)
   await snap('iconAction','disabled',icon)
   const before=await page.evaluate(()=>window.__traceCalls.refresh),b=await icon.boundingBox()
   if(input==='mouse'){await page.mouse.click(b.x+b.width/2,b.y+b.height/2)}else{await page.touchscreen.tap(b.x+b.width/2,b.y+b.height/2)}
   await snap('iconAction','disabled-after-input',icon)
   assert.equal(await page.evaluate(()=>window.__traceCalls.refresh),before)
   row.events=await page.evaluate(()=>window.__traceEvents);row.errors=errors;assert.deepEqual(errors,[])
   traces.push(row);await writeFile(join(out,'source-trace.partial.json'),JSON.stringify({provenance,traces},null,2)+'\n')
   await context.close()
  }}finally{await browser.close()}
 }
 await writeFile(join(out,'source-trace.json'),JSON.stringify({passed:true,provenance,traces},null,2)+'\n')
 console.log(JSON.stringify({passed:true,traces:traces.length,screenshots:traces.reduce((n,t)=>n+t.snapshots.length,0),out}))
}finally{await new Promise(done=>server.close(done))}
