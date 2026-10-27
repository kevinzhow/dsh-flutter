// Inspect initial focus inheritance in the real preset guide at native densities.
// Usage: node tool/design-system/probe_segmented_guide.mjs <react-plan.json>
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
  const url = new URL(req.url, '[local-runtime-url]')
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
const origin = `[local-runtime-url]
const entries = plan.entries.filter(e => /guide-(desktop|phone)-en-initial\.(light|dark)$/.test(e.key))
const rows = []
try {
  for (const entry of entries) {
    const c = entry.case, density = c.viewport.density
    const browser = await chromium.launch({args:[...(plan.chromiumArgs ?? []), ...(density === 1 ? [] : [`--force-device-scale-factor=${density}`])]})
    try {
      const states = {}
      for (const mode of ['pointer', 'keyboard', 'keyboardThenSamePointer']) {
        // A fresh page makes each activation independent of the preceding
        // focus-visible state. The guide itself is opened by its real trigger.
        const context = await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height}, deviceScaleFactor:density, colorScheme:c.theme, locale:c.locale})
        try {
          const page = await context.newPage()
          await page.addInitScript(ctx => { window.__PARITY__ = ctx }, {case:c, variant:entry.variant})
          await page.goto(origin)
          await page.waitForSelector('body[data-parity-ready="true"]')
          await page.evaluate(() => document.fonts.ready)
          await page.evaluate(() => window.__parityReady)
          const trigger = page.locator('[data-parity-id="preset-guide-standard-details"]')
          await trigger.waitFor()
          if (mode !== 'pointer') {
            for (let i = 0; i < 40 && !(await trigger.evaluate(el => el === document.activeElement)); i++) await page.keyboard.press('Tab')
            if (!(await trigger.evaluate(el => el === document.activeElement))) throw new Error(`keyboard could not focus guide trigger ${entry.key}`)
          }
          const before = await trigger.evaluate(el => ({focused:el === document.activeElement, focusVisible:el.matches(':focus-visible')}))
          if (mode === 'keyboard') await page.keyboard.press('Enter')
          else await trigger.click()
          const selected = page.locator('[role="dialog"] [role="tab"][aria-selected="true"]')
          await selected.waitFor()
          const tab = await selected.evaluate(el => {
            const s = getComputedStyle(el), box = el.getBoundingClientRect()
            return {focused:el === document.activeElement, focusVisible:el.matches(':focus-visible'), role:el.getAttribute('role'),
              selected:el.getAttribute('aria-selected'), tabIndex:el.tabIndex, panelId:el.getAttribute('aria-controls'),
              underline:s.textDecorationLine, underlineOffset:s.textUnderlineOffset, underlineThickness:s.textDecorationThickness,
              width:box.width, height:box.height}
          })
          const visible = mode !== 'pointer'
          if (!tab.focused || tab.focusVisible !== visible || tab.underline !== (visible ? 'underline' : 'none')) throw new Error(`guide focus inheritance differs for ${entry.key} / ${mode}`)
          if (visible && (tab.underlineOffset !== '4px' || tab.underlineThickness !== '1px')) throw new Error(`guide underline differs for ${entry.key} / ${mode}`)
          states[mode] = {triggerBefore:before, tab}
        } finally { await context.close() }
      }
      rows.push({key:entry.key, density, browser:browser.version(), ...states})
    } finally { await browser.close() }
  }
  if (rows.length !== 4) throw new Error(`expected four guide probes, got ${rows.length}`)
  process.stdout.write(JSON.stringify(rows, null, 2) + '\n')
} finally {
  await new Promise(resolve => server.close(resolve))
}
