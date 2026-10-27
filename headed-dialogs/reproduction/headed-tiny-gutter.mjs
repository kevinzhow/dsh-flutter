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
const diagnosticOut=path.resolve(process.argv[3]);fs.mkdirSync(diagnosticOut,{recursive:true})
const {PNG}=require('pngjs')
async function inspect(page){
 const result=await measure(page)
 result.additional=await page.evaluate(()=>{
  const dialog=document.querySelector('[data-parity-id="risk-dialog"]'),content=document.querySelector('[data-parity-id="risk-content"]'),header=document.querySelector('[data-parity-id="risk-header"]'),footer=document.querySelector('[data-parity-id="risk-footer"]'),root=dialog.parentElement
  const d=getComputedStyle(dialog),s=getComputedStyle(content),bar=getComputedStyle(content,'::-webkit-scrollbar'),thumb=getComputedStyle(content,'::-webkit-scrollbar-thumb'),track=getComputedStyle(content,'::-webkit-scrollbar-track')
  const rect=el=>{const r=el.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom}}
  const dr=rect(dialog),cr=rect(content),hr=rect(header),fr=rect(footer)
  return {rootRect:rect(root),dialogHeight:d.height,dialogMaxHeight:d.maxHeight,dialogPaddingBottom:d.paddingBottom,dialogGap:d.gap,dialogOverflow:d.overflow,footerHeight:fr.height,gapFromContentToFooter:fr.y-cr.bottom,footerClippedHeight:Math.max(0,Math.min(fr.bottom,dr.bottom)-Math.max(fr.y,dr.y)),headerLayoutOffsetBeforeScrolling:hr.y-cr.y+content.scrollTop,
   contentOffsetMinusClient:content.offsetWidth-content.clientWidth,actualGutterCssPx:cr.width-hr.width,actualGutterDevicePx:(cr.width-hr.width)*devicePixelRatio,contentScrollbarGutter:s.scrollbarGutter,contentOverflowY:s.overflowY,
   webkitScrollbarWidth:bar.width,thumbBackground:thumb.backgroundColor,thumbBorderLeft:thumb.borderLeftWidth,thumbBorderRight:thumb.borderRightWidth,trackBackground:track.backgroundColor,trackMarginBlockStart:track.marginBlockStart,trackMarginBlockEnd:track.marginBlockEnd,thumbVariable:s.getPropertyValue('--dsh-scrollbar-thumb').trim(),l1Variable:s.getPropertyValue('--dsw-alias-scrollbar-bg-l1').trim(),l2Variable:s.getPropertyValue('--dsw-alias-scrollbar-bg-l2').trim()}
 })
 return result
}
async function preload(page){
 await page.route('**/assets/index-*.js',async route=>{
  await page.waitForFunction(()=>[...document.fonts].length>0)
  await page.evaluate(async()=>{await Promise.all([document.fonts.load('400 14px "-apple-system"','Full access'),document.fonts.load('500 16px "-apple-system"','Full access'),document.fonts.load('400 14px "PingFang SC"','确认风险'),document.fonts.load('500 16px "PingFang SC"','确认风险')]);await document.fonts.ready})
  await route.continue()
 })
}
try{
 for(const device of ['desktop','phone']){
  for(const theme of ['light','dark']){
   for(const scenario of ['short','long','tiny']){
    if(scenario==='tiny'&&theme!=='light')continue
    for(const mode of scenario==='tiny'?['parity-default']:['parity-default','diagnostic-visible']){
     const entry=plan.entries.find(e=>e.key===`components.headed-dialogs.risk-${device}-en-${scenario==='long'?'long-card-top':'card-on'}.${theme}`)
     const c=structuredClone(entry.case),density=c.viewport.density
     if(scenario==='tiny')c.viewport.height=80
     const id=`${density}-${mode}`
     if(!browsers.has(id))browsers.set(id,await chromium.launch({args:[...(plan.chromiumArgs??[]),...(density===1?[]:[`--force-device-scale-factor=${density}`])],...(mode==='diagnostic-visible'?{ignoreDefaultArgs:['--hide-scrollbars']}:{})}))
     const browser=browsers.get(id),context=await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height},deviceScaleFactor:density,colorScheme:c.theme,locale:c.locale,reducedMotion:'reduce'})
     try{
      const page=await context.newPage();await preload(page)
      await page.addInitScript(ctx=>{window.__PARITY__=ctx},{case:c,variant:entry.variant})
      await page.goto(origin);await page.waitForSelector('body[data-parity-ready="true"]');await page.evaluate(()=>window.__parityReady);await settle(page)
      const state=await inspect(page)
      const session=await browser.newBrowserCDPSession(),command=await session.send('Browser.getBrowserCommandLine')
      const name=`${device}-${theme}-${scenario}-${mode}`,png=PNG.sync.read(await page.screenshot({animations:'disabled',caret:'hide',scale:'device'}))
      fs.writeFileSync(path.join(diagnosticOut,name+'.png'),PNG.sync.write(png))
      const row={device,theme,scenario,mode,implicitScrollbarHidden:command.arguments.includes('--hide-scrollbars'),state,image:name+'.png'}
      if(state.additional.actualGutterDevicePx>0.1){
       const r=state.nodes['risk-content'].rect,gr=state.additional.actualGutterDevicePx,w=Math.round(gr),x1=Math.round(r.right*density),y0=Math.max(0,Math.ceil(r.y*density)),y1=Math.min(png.height,Math.floor(r.bottom*density)),strip=new PNG({width:w,height:y1-y0}),colors=new Map()
       for(let y=0;y<strip.height;y++)for(let x=0;x<w;x++){
        const src=((y+y0)*png.width+(x+x1-w))*4,dst=(y*w+x)*4;for(let ch=0;ch<4;ch++)strip.data[dst+ch]=png.data[src+ch]
        const rgb=[...strip.data.subarray(dst,dst+4)].join(',');colors.set(rgb,(colors.get(rgb)??0)+1)
       }
       fs.writeFileSync(path.join(diagnosticOut,name+'.gutter.png'),PNG.sync.write(strip));row.gutter={widthDevicePx:w,topColors:[...colors].sort((a,b)=>b[1]-a[1]).slice(0,8)}
      }
      rows.push(row)
     }finally{await context.close()}
    }
   }
  }
 }
 fs.writeFileSync(path.join(diagnosticOut,'measurements.json'),JSON.stringify({description:'Read-only source geometry. Only diagnostic-visible omits the implicit --hide-scrollbars flag. Same pinned fonts loaded before unchanged source mount.',rows},null,2)+'\n')
 process.stdout.write(JSON.stringify(rows.map(({device,theme,scenario,mode,state})=>({device,theme,scenario,mode,card:state.nodes['risk-dialog'].rect,content:state.nodes['risk-content'].rect,footer:state.nodes['risk-footer'].rect,additional:state.additional})),null,2)+'\n')
}finally{await Promise.all([...browsers.values()].map(b=>b.close()));await new Promise(resolve=>server.close(resolve))}
