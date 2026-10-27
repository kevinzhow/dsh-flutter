// Inspect the real DiscoverSection Pill in the already-built parity host.
// Usage: node tool/design-system/probe_pill_browser.mjs <react-plan.json>
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import {createRequire} from 'node:module'

const require = createRequire(new URL('../parity-web/capture.mjs', import.meta.url))
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
const entries = plan.entries.filter(e => /market-(desktop|phone)-en-inactive\.(light|dark)$/.test(e.key))
const rows = []
try {
  for (const entry of entries) {
    const c = entry.case, density = c.viewport.density
    const browser = await chromium.launch({args:[...(plan.chromiumArgs ?? []), ...(density === 1 ? [] : [`--force-device-scale-factor=${density}`])]})
    const context = await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height}, deviceScaleFactor:density, colorScheme:c.theme, locale:c.locale})
    const page = await context.newPage()
    await page.addInitScript(ctx => { window.__PARITY__ = ctx }, {case:c, variant:entry.variant})
    await page.goto(origin)
    await page.waitForSelector('body[data-parity-ready="true"]')
    await page.evaluate(() => document.fonts.ready)
    await page.evaluate(() => window.__parityReady)
    const target = page.locator('[data-parity-id="market-category-tools"]')
    const inspect = () => target.evaluate(el => {
      const s = getComputedStyle(el), box = el.getBoundingClientRect()
      return {focused:document.activeElement === el, focusVisible:el.matches(':focus-visible'), width:box.width, height:box.height,
        outlineStyle:s.outlineStyle, outlineWidth:s.outlineWidth, outlineColor:s.outlineColor, outlineOffset:s.outlineOffset,
        background:s.backgroundColor, borderRadius:s.borderRadius, shadow:s.boxShadow, color:s.color, cursor:s.cursor}
    })
    const normal = await inspect()
    for (let i = 0; i < 40 && !(await inspect()).focused; i++) await page.keyboard.press('Tab')
    const keyboard = await inspect()
    if (!keyboard.focused) throw new Error(`keyboard could not focus ${entry.key}`)
    await target.click()
    const pointer = await inspect()
    await target.evaluate(el => { el.disabled = true })
    await target.hover({force:true})
    const disabledHover = await inspect()
    rows.push({key:entry.key, density, normal, keyboard, pointer, disabledHover})
    await browser.close()
  }
  if (!rows.length) throw new Error('plan has no inactive market pill captures')
  process.stdout.write(JSON.stringify(rows, null, 2) + '\n')
} finally {
  await new Promise(resolve => server.close(resolve))
}
