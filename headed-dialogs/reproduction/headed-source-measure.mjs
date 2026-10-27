// Actual controlled RiskConfirmation DOM, focus and scroll ownership. No styling mutations.
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import {createRequire} from 'node:module'
const require=createRequire(process.env.PARITY_WEB_DEPS+'/package.json')
const {chromium}=require('playwright-core')
const plan=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const fontsDir=path.dirname(plan.fontsManifest)
const fonts=JSON.parse(fs.readFileSync(plan.fontsManifest,'utf8'))
const faces=fonts.families.flatMap(f=>f.faces.flatMap(face=>f.names.map(name=>({name,...face}))))
const fontCss=faces.map(f=>`@font-face{font-family:'${f.name}';font-weight:${f.weight};font-style:${f.style};src:url('/fonts/${path.basename(f.file)}');font-display:block}`).join('\n')
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.ttf':'font/ttf','.otf':'font/otf'}
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://localhost')
 if(url.pathname==='/parity-fonts.css'){res.writeHead(200,{'content-type':'text/css'});res.end(fontCss);return}
 const face=url.pathname.startsWith('/fonts/')?faces.find(f=>path.basename(f.file)===path.basename(url.pathname)):null
 const file=face?path.join(fontsDir,face.file):path.resolve(plan.hostDist,url.pathname==='/'?'index.html':url.pathname.slice(1))
 if((!face&&!file.startsWith(path.resolve(plan.hostDist)+path.sep))||!fs.existsSync(file)){res.writeHead(404);res.end();return}
 res.writeHead(200,{'content-type':mime[path.extname(file)]??'application/octet-stream'});fs.createReadStream(file).pipe(res)
})
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve))
const origin=`http://127.0.0.1:${server.address().port}`
const browsers=new Map(),rows=[]
async function settle(page){await page.evaluate(async()=>{await document.fonts.ready;await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame)})}
async function measure(page){return page.evaluate(()=>{
 const nodes={}
 for(const id of ['risk-dialog','risk-content','risk-header','risk-title','risk-close','risk-body','risk-warning','risk-description','risk-acknowledge','risk-checkbox','risk-footer','risk-cancel','risk-confirm']){
  const el=document.querySelector(`[data-parity-id="${id}"]`);if(!el)continue
  const r=el.getBoundingClientRect(),s=getComputedStyle(el)
  nodes[id]={tag:el.tagName,rect:{x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom},clientWidth:el.clientWidth,offsetWidth:el.offsetWidth,clientHeight:el.clientHeight,scrollHeight:el.scrollHeight,scrollTop:el.scrollTop,
   css:{display:s.display,position:s.position,boxSizing:s.boxSizing,overflowY:s.overflowY,overscrollBehaviorY:s.overscrollBehaviorY,scrollbarGutter:s.scrollbarGutter,width:s.width,maxHeight:s.maxHeight,paddingTop:s.paddingTop,paddingRight:s.paddingRight,paddingBottom:s.paddingBottom,paddingLeft:s.paddingLeft,marginTop:s.marginTop,gap:s.gap,font:s.font,color:s.color},
   ...('checked'in el?{checked:el.checked}:{}),...('disabled'in el?{disabled:el.disabled}:{})}
 }
 const active=document.activeElement,style=active?getComputedStyle(active):null
 const focus={tag:active?.tagName,type:active?.getAttribute('type'),id:active?.getAttribute('data-parity-id'),inDialog:!!active?.closest('[role="dialog"]'),automatic:active?.hasAttribute('data-dsh-automatic-focus'),focusVisible:active?.matches(':focus-visible'),outline:style?.outline,body:active===document.body}
 const dialog=document.querySelector('[data-parity-id="risk-dialog"]'),content=document.querySelector('[data-parity-id="risk-content"]'),footer=document.querySelector('[data-parity-id="risk-footer"]')
 return {dpr:devicePixelRatio,viewport:{width:innerWidth,height:innerHeight},supportsDvh:CSS.supports('height','100dvh'),focus,nodes,footerOutsideContent:!content.contains(footer),dialogChildren:[...dialog.children].map(el=>el.getAttribute('data-parity-id'))}
})}
try{
 const entries=plan.entries.filter(e=>e.case.capture.flutterKey==='risk-dialog')
 for(const entry of entries){
  const c=entry.case,density=c.viewport.density
  if(!browsers.has(density))browsers.set(density,await chromium.launch({args:[...(plan.chromiumArgs??[]),...(density===1?[]:[`--force-device-scale-factor=${density}`])]}))
  const browser=browsers.get(density),context=await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height},deviceScaleFactor:density,colorScheme:c.theme,locale:c.locale,reducedMotion:'reduce'})
  try{
   const page=await context.newPage()
   await page.addInitScript(ctx=>{window.__PARITY__=ctx},{case:c,variant:entry.variant})
   await page.goto(origin);await page.waitForSelector('body[data-parity-ready="true"]');await page.evaluate(()=>window.__parityReady);await settle(page)
   const initial=await measure(page)
   const content=page.locator('[data-parity-id="risk-content"]')
   const row={key:entry.key,browser:browser.version(),props:entry.variant.props,initial}
   if(entry.variant.props.repeat>1){
    await content.evaluate(el=>{el.scrollTop=0});await settle(page);row.top=await measure(page)
    await content.evaluate(el=>{el.scrollTop=1000000});await settle(page);row.bottom=await measure(page)
    const a=row.top.nodes,b=row.bottom.nodes
    if(!(a['risk-content'].scrollTop===0&&b['risk-content'].scrollTop>0&&a['risk-footer'].rect.y===b['risk-footer'].rect.y&&a['risk-header'].rect.y>b['risk-header'].rect.y))throw new Error(`scroll ownership failed ${entry.key}`)
   }
   if(c.theme==='light'&&c.locale==='en'&&c.viewport.density===1&&entry.variant.props.repeat===1){
    await page.keyboard.press('Tab');await settle(page);row.afterTab=await measure(page)
   }
   rows.push(row)
  }finally{await context.close()}
 }
 if(rows.length!==48)throw new Error(`expected48rows,got${rows.length}`)
 const commandSession=await browsers.get(2.625).newBrowserCDPSession()
 const command=await commandSession.send('Browser.getBrowserCommandLine')
 process.stdout.write(JSON.stringify({implicitScrollbarHidden:command.arguments.includes('--hide-scrollbars'),rows},null,2)+'\n')
}finally{await Promise.all([...browsers.values()].map(b=>b.close()));await new Promise(resolve=>server.close(resolve))}
