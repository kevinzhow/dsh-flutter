// Source the absolute pr16 environment. Exact published ESM/CSS; no component
// body/style rewrite or source-TS fallback. Output must be fresh.
import {readFile,writeFile,mkdir,access} from 'node:fs/promises'
import {resolve,join,dirname,extname} from 'node:path'
import {fileURLToPath,pathToFileURL} from 'node:url'
import {createHash} from 'node:crypto'
import {execFileSync} from 'node:child_process'
import {createServer} from 'node:http'
import assert from 'node:assert/strict'

const argv=Object.fromEntries(process.argv.slice(2).reduce((out,arg,i,args)=>{if(arg.startsWith('--'))out.push([arg.slice(2),args[i+1]]);return out},[]))
for(const key of ['repo','archives','plan','out'])assert(argv[key],`Missing --${key}`)
const repo=resolve(argv.repo),out=resolve(argv.out),archives=resolve(argv.archives),source=resolve(process.env.DSH_SRC)
const reference=argv.reference??'native';assert(['native','emulated'].includes(reference))
const runBehavior=argv.behavior==='run';assert(argv.behavior===undefined||['run','skip'].includes(argv.behavior))
try{await access(out);throw Error('Refusing to overwrite source evidence')}catch(error){if(error.code!=='ENOENT')throw error}
await mkdir(out,{recursive:true})
const sha=bytes=>createHash('sha256').update(bytes).digest('hex'),json=async p=>JSON.parse(await readFile(p,'utf8'))
const gitEnv={...process.env,GIT_OPTIONAL_LOCKS:'0'}
const git=(root,...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8',env:gitEnv}).trim()
const lockPath=join(repo,'tool/design-system/sources.lock.json'),lockBytes=await readFile(lockPath),lock=JSON.parse(lockBytes)
assert.equal(git(source,'rev-parse','HEAD'),lock.referenceCommit);assert.equal(git(source,'status','--porcelain','--untracked-files=all'),'')
const pkg=lock.packages.find(p=>p.name==='@deepseek-ai/dsh-client-ui-primitives');assert.equal(pkg.version,'0.2.1-rc.2')
const archive=join(archives,`deepseek-ai-dsh-client-ui-primitives-${pkg.version}.tgz`),archiveBytes=await readFile(archive)
assert.equal('sha512-'+createHash('sha512').update(archiveBytes).digest('base64'),pkg.integrity)
const host=join(out,'host'),dist=join(out,'dist');await mkdir(host)
const extracted=JSON.parse(execFileSync('python3',['-c',`
import pathlib,tarfile,hashlib,json,sys
archive,target=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]);records={}
with tarfile.open(archive) as tar:
 for member in tar.getmembers():
  path=pathlib.PurePosixPath(member.name)
  if not member.isfile() or path.parts[:2]!=('package','lib'):continue
  if '..' in path.parts or path.is_absolute():raise ValueError('unsafe published path')
  relative=pathlib.Path(*path.parts[1:]);file=target/relative
  if relative.as_posix() in records:raise ValueError('duplicate archive path')
  data=tar.extractfile(member).read();file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(data)
  records[relative.as_posix()]=hashlib.sha256(data).hexdigest()
print(json.dumps(records))
`,archive,join(host,'published')],{encoding:'utf8',maxBuffer:1024*1024}))
const bundlePath=join(host,'published/lib/index.js'),bundle=await readFile(bundlePath)
const behaviorPath=join(repo,'tool/design-system/upstream/ui-primitives/toast-behavior.json'),behavior=await json(behaviorPath)
const recipePath=join(repo,'tool/design-system/recipes.generated.json'),recipeBytes=await readFile(recipePath),recipe=JSON.parse(recipeBytes).metrics.DshToastRecipe
assert.equal(sha(bundle),behavior.bundleSha256)
assert.equal(sha(await readFile(join(host,'published/lib/Toast.module.css'))),pkg.files['Toast.module.css'])
assert(bundle.toString().includes(behavior.region),'whole locked Toast body must occur unchanged in published module')
const fixturePath=join(repo,'apps/dsh_flutter/test/parity/helpers/toast_fixture.dart'),fixtureBytes=await readFile(fixturePath)
const literals=[...fixtureBytes.toString().matchAll(/const toastScenarioJson = r'''\n([\s\S]*?)\n''';/g)];assert.equal(literals.length,1)
const fixture=JSON.parse(literals[0][1]);assert.equal(fixture.schema,'dsh-toast-scenarios/1')
const scenarios=Object.fromEntries(fixture.scenarios.map(s=>[s.id,s]))
const planPath=resolve(argv.plan),planBytes=await readFile(planPath),plan=JSON.parse(planBytes)
const entries=plan.cases.flatMap(c=>c.variants.map(v=>({key:v.id==='default'?c.id:c.id+'~'+v.id,case:c,variant:v})))
assert(entries.length>0);assert.equal(new Set(entries.map(e=>e.key)).size,entries.length)
for(const e of entries){assert.equal(e.case.kind,'toast.source');assert.deepEqual(e.variant.props.scenario,scenarios[e.variant.props.scenarioId]);assert.equal(e.variant.props.holdMs,fixture.stableHoldMs)}
const provenance={schema:'dsh-published-toast-inputs/1',referenceCommit:lock.referenceCommit,version:pkg.version,integrity:pkg.integrity,
 archiveSha256:sha(archiveBytes),bundleSha256:sha(bundle),archiveFiles:extracted,bodySha256:sha(behavior.region),
 behaviorLockSha256:sha(await readFile(behaviorPath)),recipeSha256:sha(recipeBytes),sourceLockSha256:sha(lockBytes),fixtureHelperSha256:sha(fixtureBytes),
 planSha256:sha(planBytes),producerSha256:sha(await readFile(fileURLToPath(import.meta.url))),sourceFiles:{},fonts:[],
 preparationRepository:{head:git(repo,'rev-parse','HEAD'),tree:git(repo,'rev-parse','HEAD^{tree}'),sourceOnly:true},
 moduleInstrumentation:'none: Toast and real icons are actual published ESM exports',bodyAndStylesRewritten:false}
for(const name of ['packages/client/ui-primitives/src/Toast.tsx','packages/client/ui-primitives/src/icons/index.tsx','packages/client/web/src/base.css']){
 const value=sha(await readFile(join(source,name))),expected=pkg.referenceSourceSha256?.[name];if(expected)assert.equal(value,expected)
 provenance.sourceFiles[name]=value
}
const modules=join(process.env.PARITY_WEB_DEPS,'node_modules'),{build}=await import(pathToFileURL(join(modules,'vite/dist/node/index.js')))
const {chromium}=await import(pathToFileURL(join(modules,'playwright-core/index.mjs')))
const theme=lock.packages.find(p=>p.snapshotFolder==='ui-theme'),order=await json(join(repo,'tool/design-system/upstream/ui-theme/styles-order.json'))
let styles=''
for(const name of order){const file=join(repo,'tool/design-system/upstream/ui-theme',name);assert.equal(sha(await readFile(file)),theme.files[name]);styles+=`import ${JSON.stringify(file)};\n`}
styles+=`import ${JSON.stringify(join(source,'packages/client/web/src/base.css'))};\n`
const fontManifest=await json(join(repo,'tool/parity-fonts/manifest.json')),fonts=new Map();let fontCss=''
for(const family of fontManifest.families)for(const face of family.faces){
 const file=join(repo,'tool/parity-fonts',face.file),id=String(fonts.size)+extname(file);assert.equal(sha(await readFile(file)),face.sha256);fonts.set(id,file)
 provenance.fonts.push({file:face.file,sha256:face.sha256})
 for(const name of family.names)fontCss+=`@font-face{font-family:'${name}';font-weight:${face.weight};font-style:${face.style};src:url('/fonts/${id}');font-display:block}`
}
await writeFile(join(host,'index.html'),'<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/fonts.css"></head><body><div id="root"></div><script type="module" src="/entry.tsx"></script></body></html>')
await writeFile(join(host,'entry.tsx'),`${styles}
import * as React from 'react';import {createRoot} from 'react-dom/client';import {flushSync} from 'react-dom';
import {Toast,IconWarningOutlineRegular} from './published/lib/index.js';
const initial=(window as any).__toastEntry,root=createRoot(document.getElementById('root')!);
const events:any[]=[];(window as any).__toastEvents=events;let started=0;
function Scene(props:any){return <div data-transformed-owner style={props.transformed?{transform:'translate(120px,170px)'}:undefined}><Toast {...props}/></div>}
function render(options:any={}){const scenario=options.scenario??initial.variant.props.scenario,locale=initial.case.locale.split('-')[0],label=options.callback??'default';
 const props={text:scenario.text[locale]??scenario.text.en,icon:scenario.icon==='warning'?<IconWarningOutlineRegular/>:undefined,tone:scenario.tone??undefined,
  ...(options.defaultHold?{}:{holdMs:options.holdMs??initial.variant.props.holdMs}),transformed:options.transformed,
  onDone:()=>events.push({type:'done',label,elapsed:performance.now()-started})};
 flushSync(()=>root.render(<Scene {...props}/>));}
(window as any).__toastRender=render;(window as any).__toastRemount=(options:any={})=>{flushSync(()=>root.render(null));events.splice(0);started=performance.now();render(options)};
(window as any).__toastClear=()=>flushSync(()=>root.render(null));
document.documentElement.style.colorScheme=initial.case.theme;document.documentElement.dataset.dsThemeSource=initial.case.theme;
document.documentElement.lang=initial.case.locale;document.body.toggleAttribute('data-ds-dark-theme',initial.case.theme==='dark');
document.body.style.margin='0';document.body.style.background='var(--dsw-alias-bg-base)';
started=performance.now();render();(window as any).__toastReady=true;
`)
const installed=name=>join(modules,name)
await build({root:host,base:'./',configFile:false,logLevel:'warn',define:{'process.env.NODE_ENV':'"production"'},
 plugins:[{name:'pinned-external-dependencies',enforce:'pre',async resolveId(id,importer,options){
  if(!importer||!(importer.startsWith(host+'/')||importer.startsWith(source+'/'))||id.startsWith('.')||id.startsWith('/'))return null
  return this.resolve(id,join(modules,'.toast-importer.js'),{...options,skipSelf:true})
 }}],
 resolve:{alias:[
 {find:'@deepseek-ai/dsh-util-workspace-path',replacement:join(source,'packages/util/workspace-path/src/index.ts')},
 {find:'@deepseek-ai/dsh-util-code-language',replacement:join(source,'packages/util/code-language/src/index.ts')},
 {find:'@deepseek-ai/dsh-client-store',replacement:join(repo,'tool/parity-web/host/mocks/client-store.ts')},
 {find:/^react\/jsx-runtime$/,replacement:join(installed('react'),'jsx-runtime.js')},
 {find:/^react-dom\/client$/,replacement:join(installed('react-dom'),'client.js')},
 {find:/^react-dom$/,replacement:join(installed('react-dom'),'index.js')},
 {find:/^react$/,replacement:join(installed('react'),'index.js')},
 ]},oxc:{jsx:{runtime:'automatic'}},build:{outDir:dist,emptyOutDir:true,minify:false,sourcemap:false,cssCodeSplit:false,target:'es2022'}})
await writeFile(join(out,'provenance.json'),JSON.stringify(provenance,null,2)+'\n')
const server=createServer(async(req,res)=>{try{
 const path=new URL(req.url,'http://127.0.0.1').pathname;if(path==='/fonts.css'){res.setHeader('Content-Type','text/css');res.end(fontCss);return}
 let file;if(path.startsWith('/fonts/')){file=fonts.get(path.slice(7));if(!file)throw Error('font')}else{file=resolve(dist,'.'+(path==='/'?'/index.html':path));if(!file.startsWith(dist+'/'))throw Error('path')}
 res.setHeader('Content-Type',{'.html':'text/html','.js':'text/javascript','.css':'text/css','.ttf':'font/ttf','.otf':'font/otf'}[extname(file)]??'application/octet-stream');res.end(await readFile(file))
}catch{res.writeHead(404);res.end()}})
await new Promise(done=>server.listen(0,'127.0.0.1',done))
const origin=`http://127.0.0.1:${server.address().port}`,results=join(out,'visual-testing-results'),reactDir=join(results,'react')
await mkdir(reactDir,{recursive:true})
await writeFile(join(out,'flutter-plan.json'),JSON.stringify({reference,resultsDir:results,fontsManifest:join(repo,'tool/parity-fonts/manifest.json'),fixturesDirs:[],entries,coverage:plan.cases.map(c=>({id:c.id,kind:c.kind})),runInfo:{source:'actual published Toast ESM',sourcePlanSha256:provenance.planSha256}},null,2)+'\n')
const traces=[],behaviorTraces=[]
const measure=()=>{const el=document.querySelector('[role=alert]');if(!el)return null;const read=node=>{if(!node)return null;const b=node.getBoundingClientRect(),s=getComputedStyle(node);return{bounds:[b.x,b.y,b.width,b.height],tag:node.tagName,text:node.textContent,color:s.color,background:s.backgroundColor,fontSize:s.fontSize,lineHeight:s.lineHeight,whiteSpace:s.whiteSpace,overflowWrap:s.overflowWrap}};
 const s=getComputedStyle(el),icon=el.querySelector('[aria-hidden]'),text=el.lastElementChild;
 return{schema:'dsh-toast-geometry/1',toast:read(el),text:read(text),icon:read(icon),iconPresent:Boolean(icon),role:el.getAttribute('role'),portalToBody:el.parentElement===document.body,
  opacity:Number(s.opacity),visibility:s.visibility,pointerEvents:s.pointerEvents,zIndex:s.zIndex,transform:s.transform,
  contentBox:{width:s.width,maxWidth:s.maxWidth,boxSizing:s.boxSizing,padding:[s.paddingTop,s.paddingRight,s.paddingBottom,s.paddingLeft],gap:s.gap},
  animations:el.getAnimations().map(a=>({name:a.animationName,currentTime:a.currentTime,timing:a.effect.getTiming(),computed:a.effect.getComputedTiming()})),
  focusedTag:document.activeElement?.tagName,layoutViewport:{width:document.documentElement.getBoundingClientRect().width,height:document.documentElement.getBoundingClientRect().height}}}
try{
 for(const density of [...new Set(entries.map(e=>e.case.viewport.density))]){
  const browser=await chromium.launch({args:['--disable-lcd-text','--font-render-hinting=none',...(reference==='native'?[`--force-device-scale-factor=${density}`]:[])]})
  try{for(const entry of entries.filter(e=>e.case.viewport.density===density)){
   const c=entry.case,props=entry.variant.props,context=await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height},deviceScaleFactor:density,colorScheme:c.theme,reducedMotion:props.reducedMotion?'reduce':'no-preference'})
   await context.route('**/*',route=>route.request().url().startsWith(origin+'/')||route.request().url().startsWith('data:')?route.continue():route.abort())
   const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(String(error)))
   await page.addInitScript(entry=>{window.__toastEntry=entry},entry);await page.goto(origin);await page.waitForFunction(()=>window.__toastReady);await page.evaluate(()=>document.fonts.ready)
   await page.evaluate(()=>{window.__toastRemount();return new Promise(requestAnimationFrame)})
   const before=await page.evaluate(measure),fade=before.animations.find(a=>a.name.includes('toast-fade')),enter=before.animations.find(a=>a.name.includes('toast-in'))
   assert(fade);assert.equal(fade.timing.delay,props.holdMs);assert.equal(Boolean(enter),!props.reducedMotion)
   const entryDuration=enter?.timing.duration??recipe.enterMs
   assert.equal(entryDuration,recipe.enterMs)
   await page.waitForTimeout(entryDuration);await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))))
   const actual=await page.evaluate(measure),checks=[]
   assert(actual.portalToBody);assert.equal(actual.role,'alert');assert.equal(actual.pointerEvents,'none');assert.equal(actual.opacity,1);assert.equal(actual.visibility,'visible');assert.equal(Number(actual.zIndex),1100)
   const iconExpected=props.scenario.tone==='success'||props.scenario.icon!=='none';assert.equal(actual.iconPresent,iconExpected)
   assert.equal(actual.toast.bounds[1],recipe.top);assert(Math.abs(actual.toast.bounds[0]+actual.toast.bounds[2]/2-actual.layoutViewport.width/2)<1/64)
   assert.equal(actual.contentBox.boxSizing,'content-box');assert.equal(parseFloat(actual.contentBox.gap),recipe.gap)
   assert.deepEqual(errors,[]);checks.push({check:'actual portal/alert/click-through/content-box/icon/steady-phase',passed:true})
   if(props.scenarioId.startsWith('long-')){assert(Math.abs(actual.toast.bounds[2]-(Math.min(recipe.maxContentWidth,actual.layoutViewport.width-recipe.viewportInset)+recipe.horizontalPadding*2))<1/64);checks.push({check:'actual outer cap is content cap plus source padding within CSS layout-unit precision',passed:true})}
   const file=entry.key+'.png';await page.screenshot({path:join(reactDir,file)})
   const metadata={provider:'react',source:'actual published ui-primitives0.2.1-rc.2 ESM Toast',caseId:c.id,variantId:entry.variant.id,captureKey:entry.key,
    theme:c.theme,locale:c.locale,viewport:c.viewport,react:{dshCommit:lock.referenceCommit,publishedBundleSha256:provenance.bundleSha256},pixelModel:reference,
    chromium:browser.version(),componentGeometry:actual,fixtureInputs:{holdMs:props.holdMs,reducedMotion:props.reducedMotion,entrySourceDurationMs:entryDuration,settledAnimationFrames:3,ownerRemountAfterPinnedFonts:true},
    pending:props.scenario.pending??null}
   await writeFile(join(reactDir,entry.key+'.metadata.json'),JSON.stringify(metadata,null,2)+'\n')
   traces.push({key:entry.key,file:'visual-testing-results/react/'+file,sha256:sha(await readFile(join(reactDir,file))),actual,checks,errors})
   await writeFile(join(out,'source-trace.partial.json'),JSON.stringify({passed:false,provenance,traces},null,2)+'\n')
   await context.close()
  }}finally{await browser.close()}
 }
 assert.equal(traces.length,entries.length)
 if(runBehavior){
  const browser=await chromium.launch({args:['--disable-lcd-text','--font-render-hinting=none']})
  try{
   const entry=entries[0],context=await browser.newContext({viewport:{width:800,height:600},reducedMotion:'no-preference'})
   await context.route('**/*',route=>route.request().url().startsWith(origin+'/')||route.request().url().startsWith('data:')?route.continue():route.abort())
   const page=await context.newPage();await page.addInitScript(entry=>window.__toastEntry=entry,entry);await page.goto(origin);await page.waitForFunction(()=>window.__toastReady)
   await page.evaluate(()=>window.__toastRemount({defaultHold:true,callback:'original'}))
   const original=await page.evaluate(measure),defaultDelay=original.animations.find(a=>a.name.includes('toast-fade')).timing.delay
   assert.equal(defaultDelay,recipe.holdMs)
   await page.waitForTimeout(recipe.holdMs/2)
   await page.evaluate(()=>window.__toastRender({defaultHold:true,callback:'latest'}))
   await page.waitForFunction(()=>window.__toastEvents.length===1)
   const events=await page.evaluate(()=>window.__toastEvents.slice());assert.equal(events[0].label,'latest')
   assert(events[0].elapsed>=recipe.holdMs+recipe.fadeMs-5)
   assert(events[0].elapsed<recipe.holdMs+recipe.fadeMs+recipe.holdMs/3,'same-hold rerender must not extend original deadline')
   behaviorTraces.push({check:'actual default hold and latest callback preserve original deadline',passed:true,defaultDelay,events,original})
   await page.evaluate(()=>window.__toastRemount({holdMs:200,callback:'old-hold'}));await page.waitForTimeout(100)
   await page.evaluate(()=>{window.__toastHoldUpdatedAt=performance.now();window.__toastRender({holdMs:2000,callback:'changed-hold'})})
   await page.waitForFunction(()=>window.__toastEvents.length===1)
   const changed=await page.evaluate(()=>({events:window.__toastEvents.slice(),sinceUpdate:performance.now()-window.__toastHoldUpdatedAt}));assert.equal(changed.events[0].label,'changed-hold');assert(changed.sinceUpdate>=2000+recipe.fadeMs-5)
   behaviorTraces.push({check:'changed hold reschedules source effect with latest callback',passed:true,...changed})
   await page.evaluate(()=>{window.__toastRemount({holdMs:0,callback:'cancelled'});window.__toastClear()});await page.waitForTimeout(recipe.fadeMs+50)
   assert.deepEqual(await page.evaluate(()=>window.__toastEvents),[])
   behaviorTraces.push({check:'unmount cancels actual source completion timer',passed:true})
   await page.evaluate(()=>window.__toastRemount({holdMs:60000,transformed:true}));await page.waitForTimeout(recipe.enterMs)
   const transformed=await page.evaluate(measure);assert(transformed.portalToBody);assert.equal(transformed.toast.bounds[1],recipe.top)
   behaviorTraces.push({check:'actual body portal escapes transformed owner',passed:true,actual:transformed})
   await context.close()
  }finally{await browser.close()}
  await writeFile(join(out,'behavior-probes.json'),JSON.stringify({schema:'dsh-published-toast-behavior-probes/1',passed:true,defaultHoldWasNotOverridden:true,behaviorTraces},null,2)+'\n')
 }
 for(const[file,value]of Object.entries(provenance.sourceFiles))assert.equal(sha(await readFile(join(source,file))),value)
 for(const[file,value]of Object.entries(provenance.archiveFiles))assert.equal(sha(await readFile(join(host,'published',file))),value)
 assert.equal(sha(await readFile(archive)),provenance.archiveSha256);assert.equal(sha(await readFile(fixturePath)),provenance.fixtureHelperSha256)
 assert.equal(sha(await readFile(planPath)),provenance.planSha256);assert.equal(sha(await readFile(fileURLToPath(import.meta.url))),provenance.producerSha256)
 assert.equal(sha(await readFile(recipePath)),provenance.recipeSha256)
 const receipt={schema:'whalee-published-toast-source/1',passed:true,provenance,captures:traces.length,traces,behaviorTraces,defaultLifecycleProbed:runBehavior,
  limits:['source captures require exact integrated runtime binding for final acceptance','raw whitespace and unbroken-token inputs are retained without fixture normalization','mixed oversized runs, complex Unicode, shadow coordinates/inner-contour raster and native announcement remain pending']}
 await writeFile(join(out,'source-trace.json'),JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify({passed:true,captures:traces.length,planSha256:provenance.planSha256}))
}finally{await new Promise(done=>server.close(done))}
