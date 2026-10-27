// Inspect initial focus inheritance in the real preset guide at native densities.
// Usage: node tool/design-system/probe_segmented_guide.mjs <react-plan.json>
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import {createRequire} from 'node:module'

const require = createRequire(new URL('../tool/parity-web/capture.mjs', import.meta.url))
const {chromium} = require('playwright-core')
const plan = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const fontsDir = path.dirname(plan.fontsManifest)
const fonts = JSON.parse(fs.readFileSync(plan.fontsManifest, 'utf8'))
const faces = fonts.families.flatMap(f => f.faces.flatMap(face => f.names.map(name => ({name, ...face}))))
const fontCss = faces.map(f => `@font-face{font-family:'${f.name}';font-weight:${f.weight};font-style:${f.style};src:url('/fonts/${path.basename(f.file)}');font-display:block}`).join('\n')
const mime = {'.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.ttf':'font/ttf', '.otf':'font/otf'}
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost')
  if (url.pathname === '/parity-fonts.css') {
    res.writeHead(200, {'content-type':'text/css'}); res.end(fontCss); return
  }
  const face = url.pathname.startsWith('/fonts/') ? faces.find(f => path.basename(f.file) === path.basename(url.pathname)) : null
  const file = face ? path.join(fontsDir, face.file) : path.resolve(plan.hostDist, url.pathname === '/' ? 'index.html' : url.pathname.slice(1))
  if ((!face && !file.startsWith(path.resolve(plan.hostDist) + path.sep)) || !fs.existsSync(file)) {
    res.writeHead(404); res.end(); return
  }
  res.writeHead(200, {'content-type':mime[path.extname(file)] ?? 'application/octet-stream'})
  fs.createReadStream(file).pipe(res)
})
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const origin = `http://127.0.0.1:${server.address().port}`
const entries = plan.entries.filter(e => /dialog-family\.(reader|panel-retained)-(desktop|phone)-(en|zh)-(explanation|usage)\.(light|dark)$/.test(e.key))
const browsers = new Map(), rows = []
async function settle(page) { await page.evaluate(async()=>{await document.fonts.ready;await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame)}) }
async function measure(page, selected) {
 return page.evaluate(selected=>{
  const dialog=document.querySelector('[data-parity-id="preset-guide-dialog"]'),tabs=document.querySelector('[data-parity-id="preset-guide-tabs"]')
  const box=el=>{const r=el.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}}
  const panels={}
  for(const el of dialog.querySelectorAll('[role="tabpanel"]')){
   const s=getComputedStyle(el),bar=getComputedStyle(el,'::-webkit-scrollbar'),thumb=getComputedStyle(el,'::-webkit-scrollbar-thumb')
   const child=el.firstElementChild
   panels[el.dataset.guidePage]={hidden:el.hidden,rect:box(el),offsetWidth:el.offsetWidth,clientWidth:el.clientWidth,
    scrollWidth:el.scrollWidth,offsetHeight:el.offsetHeight,clientHeight:el.clientHeight,scrollHeight:el.scrollHeight,scrollTop:el.scrollTop,
    css:{boxSizing:s.boxSizing,width:s.width,height:s.height,paddingTop:s.paddingTop,paddingRight:s.paddingRight,paddingBottom:s.paddingBottom,paddingLeft:s.paddingLeft,
     overflowX:s.overflowX,overflowY:s.overflowY,scrollbarGutter:s.scrollbarGutter,scrollbarWidth:s.scrollbarWidth,scrollbarColor:s.scrollbarColor,
     webkitScrollbarWidth:bar.width,webkitScrollbarHeight:bar.height,webkitThumbColor:thumb.backgroundColor,webkitThumbRadius:thumb.borderRadius,
     scrollbarWidthVariable:s.getPropertyValue('--dsh-scrollbar-width').trim()},
    firstChild:child?{tag:child.tagName,rect:box(child)}:null}
  }
  return {density:devicePixelRatio,viewport:{width:innerWidth,height:innerHeight},selected,dialog:box(dialog),tabs:box(tabs),panels}
 },selected)
}
try {
 for(const entry of entries){
  const c=entry.case,density=c.viewport.density
  if(!browsers.has(density))browsers.set(density,await chromium.launch({args:[...(plan.chromiumArgs??[]),...(density===1?[]:[`--force-device-scale-factor=${density}`])]}))
  const browser=browsers.get(density),context=await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height},deviceScaleFactor:density,colorScheme:c.theme,locale:c.locale,reducedMotion:'reduce'})
  try{
   const page=await context.newPage()
   await page.addInitScript(ctx=>{window.__PARITY__=ctx},{case:c,variant:entry.variant})
   await page.goto(origin)
   await page.waitForSelector('body[data-parity-ready="true"]')
   await page.evaluate(()=>window.__parityReady)
   const steps=entry.variant.interactions
   await page.locator(`[data-parity-id="${steps[0].target}"]`).click()
   await settle(page)
   const selected=entry.key.includes('-explanation.')?'explanation':'usage'
   const initial=await measure(page,selected)
   let retention
   if(entry.key.includes('panel-retained-')){
    const first=page.locator(`[data-parity-id="${steps[1].target}"]`)
    const original=await first.elementHandle()
    await first.evaluate((el,offset)=>{el.scrollTop=offset},steps[1].offset)
    await settle(page)
    const before=await measure(page,selected)
    await page.locator(`[data-parity-id="${steps[2].target}"]`).click()
    await page.locator(`[data-parity-id="${steps[3].target}"]`).evaluate((el,offset)=>{el.scrollTop=offset},steps[3].offset)
    await settle(page)
    const other=await measure(page,selected==='explanation'?'usage':'explanation')
    await page.locator(`[data-parity-id="${steps[4].target}"]`).click()
    await settle(page)
    const after=await measure(page,selected)
    const sameNode=await original.evaluate(el=>el===document.querySelector(`[data-parity-id="preset-guide-panel-${el.dataset.guidePage}"]`))
    const beforeTop=before.panels[selected].scrollTop,afterTop=after.panels[selected].scrollTop
    if(!(beforeTop>0&&beforeTop===afterTop&&sameNode))throw new Error(`source scroll retention failed for ${entry.key}`)
    retention={requestedOffset:steps[1].offset,before,other,after,samePanelNode:sameNode,positiveScrollOffsetPreserved:true}
   }
   rows.push({key:entry.key,browser:browser.version(),initial,...(retention?{retention}:{})})
  }finally{await context.close()}
 }
 if(rows.length!==32)throw new Error(`expected32measurements,got${rows.length}`)
 process.stdout.write(JSON.stringify(rows,null,2)+'\n')
}finally{
 await Promise.all([...browsers.values()].map(b=>b.close()))
 await new Promise(resolve=>server.close(resolve))
}
