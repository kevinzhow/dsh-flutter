// Inspect the real plugin manager tabs at the pinned native browser densities.
// Usage: node tool/design-system/probe_segmented_tabs.mjs <react-plan.json>
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
const entries = plan.entries.filter(e => /manager-(desktop|phone)-en-initial\.(light|dark)$/.test(e.key))
const rows = []
try {
  for (const entry of entries) {
    const c = entry.case, density = c.viewport.density
    const browser = await chromium.launch({args:[...(plan.chromiumArgs ?? []), ...(density === 1 ? [] : [`--force-device-scale-factor=${density}`])]})
    try {
      const context = await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height}, deviceScaleFactor:density, colorScheme:c.theme, locale:c.locale})
      const page = await context.newPage()
      await page.addInitScript(ctx => { window.__PARITY__ = ctx }, {case:c, variant:entry.variant})
      await page.goto(origin)
      await page.waitForSelector('body[data-parity-ready="true"]')
      await page.evaluate(() => document.fonts.ready)
      await page.evaluate(() => window.__parityReady)
      const first = page.locator('[data-parity-id="plugin-manager-tab-installed"]')
      const other = page.locator('[data-parity-id="plugin-manager-tab-discover"]')
      const inspect = () => page.locator('[role="tablist"]').evaluate(el => ({
        role:el.getAttribute('role'), label:el.getAttribute('aria-label'),
        tabs:[...el.querySelectorAll('[role="tab"]')].map(tab => {
          const s = getComputedStyle(tab)
          return {label:tab.textContent, selected:tab.getAttribute('aria-selected'), tabIndex:tab.tabIndex,
            focused:document.activeElement === tab, focusVisible:tab.matches(':focus-visible'),
            underline:s.textDecorationLine, underlineOffset:s.textUnderlineOffset, underlineThickness:s.textDecorationThickness,
            height:tab.getBoundingClientRect().height, padding:s.padding, color:s.color, transition:s.transition}
        })
      }))
      const normal = await inspect()
      for (let i = 0; i < 40 && !(await first.evaluate(el=>el===document.activeElement)); i++) await page.keyboard.press('Tab')
      const keyboard = await inspect()
      if (!keyboard.tabs[0].focused || keyboard.tabs[0].underline !== 'underline' || keyboard.tabs[0].underlineOffset !== '4px') throw new Error('source focus underline was not reached')
      await first.click()
      const pointer = await inspect()
      await page.keyboard.press('Space')
      const spaceAfterPointer = await inspect()
      await other.click()
      const pointerOther = await inspect()
      await page.keyboard.press('Space')
      const spaceOnOther = await inspect()
      await page.keyboard.press('Home')
      await page.keyboard.press('ArrowRight')
      const right = await inspect()
      await page.keyboard.press('Home')
      const home = await inspect()
      await page.keyboard.press('End')
      const end = await inspect()
      if (!pointer.tabs[0].focusVisible || pointerOther.tabs[1].focusVisible ||
          !spaceOnOther.tabs[1].focusVisible || !right.tabs[1].focused ||
          right.tabs[1].selected !== 'true' || home.tabs[0].selected !== 'true' ||
          end.tabs[1].selected !== 'true') throw new Error('source tab focus or selection behavior changed')
      rows.push({key:entry.key, density, browser:browser.version(), normal, keyboard, pointer, spaceAfterPointer, pointerOther, spaceOnOther, right, home, end})
    } finally { await browser.close() }
  }
  if (rows.length !== 4) throw new Error(`expected four source probes, got ${rows.length}`)
  process.stdout.write(JSON.stringify(rows, null, 2) + '\n')
} finally {
  await new Promise(resolve => server.close(resolve))
}
