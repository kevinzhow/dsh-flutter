// Inspect initial focus inheritance in the real preset guide at native densities.
// Usage: node tool/design-system/probe_segmented_guide.mjs <react-plan.json>
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import {createRequire} from 'node:module'

const require = createRequire(process.env.PARITY_WEB_DEPS + '/package.json')
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
const entries = plan.entries.filter(e => /guide-(desktop|phone)-en-initial\.(light|dark)$/.test(e.key))
const rows=[]
try {
 for (const entry of entries) {
  const c=entry.case,density=c.viewport.density
  const browser=await chromium.launch({args:[...(plan.chromiumArgs??[]),...(density===1?[]:[`--force-device-scale-factor=${density}`])]})
  try {
   const context=await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height},deviceScaleFactor:density,colorScheme:c.theme,locale:c.locale})
   const page=await context.newPage()
   await page.addInitScript(ctx=>{window.__PARITY__=ctx},{case:c,variant:entry.variant})
   await page.goto(origin)
   await page.waitForSelector('body[data-parity-ready="true"]')
   await page.evaluate(()=>document.fonts.ready)
   await page.evaluate(()=>window.__parityReady)
   const trigger=page.locator('[data-parity-id="preset-guide-standard-details"]')
   const inspectTrigger=()=>trigger.evaluate(el=>({focused:el===document.activeElement,focusVisible:el.matches(':focus-visible'),automatic:el.hasAttribute('data-dsh-automatic-focus'),outline:getComputedStyle(el).outlineStyle}))
   const inspectTab=()=>page.locator('[role="dialog"] [role="tab"][aria-selected="true"]').evaluate(el=>({focused:el===document.activeElement,focusVisible:el.matches(':focus-visible'),underline:getComputedStyle(el).textDecorationLine}))
   await trigger.click()
   const pointerInitial=await inspectTab()
   await page.getByRole('button',{name:'Close',exact:true}).click()
   const pointerReturned=await inspectTrigger()
   await page.keyboard.press('Control')
   const afterControl=await inspectTrigger()
   await trigger.click()
   const pointerReopened=await inspectTab()
   await page.keyboard.press('Escape')
   const escapeReturned=await inspectTrigger()
   await trigger.click()
   const afterEscapePointerReopened=await inspectTab()
   rows.push({key:entry.key,density,pointerInitial,pointerReturned,afterControl,pointerReopened,escapeReturned,afterEscapePointerReopened})
  } finally {await browser.close()}
 }
 process.stdout.write(JSON.stringify(rows,null,2)+'\n')
} finally {await new Promise(resolve=>server.close(resolve))}
