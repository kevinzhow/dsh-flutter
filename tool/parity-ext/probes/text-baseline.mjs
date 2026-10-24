// Chromium side of tool/parity-ext/text-baseline-sweep.py: draws "HHHH" for every (family, weight, size, line-height)
// of <dir>/combos.json at every density, with the pinned parity fonts, one block per row, and writes
// <dir>/chromium-dpr<d>.png plus <dir>/rows.json. Run by the sweep script (it sets PARITY_WEB_DEPS).
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'

const dir = process.argv[2]
const fontsDir = process.argv[3]
const require = createRequire(path.join(process.env.PARITY_WEB_DEPS, 'node_modules', 'x.js'))
const { chromium } = require('playwright-core')
const cfg = JSON.parse(fs.readFileSync(path.join(dir, 'combos.json'), 'utf8'))
const faces = [
  ['Segoe UI', 400, 'NotoSans-Regular.ttf'], ['Segoe UI', 700, 'NotoSans-Bold.ttf'],
  ['SF Mono', 400, 'NotoSansMono-Regular.ttf'], ['SF Mono', 700, 'NotoSansMono-Bold.ttf'],
]
const css = faces.map(([family, weight, file]) => {
  const data = fs.readFileSync(path.join(fontsDir, 'files', file)).toString('base64')
  return `@font-face{font-family:'${family}';font-weight:${weight};src:url(data:font/ttf;base64,${data})}`
}).join('\n')
const PITCH = 40
const rows = []
for (const family of cfg.families) for (const weight of cfg.weights) for (const [size, line] of cfg.combos) rows.push({ family, weight, size, line })
fs.writeFileSync(path.join(dir, 'rows.json'), JSON.stringify({ pitch: PITCH, rows }))
// The same flags as tool/parity-web/capture.mjs.
const browser = await chromium.launch({ args: ['--disable-lcd-text', '--font-render-hinting=none'] })
for (const dpr of cfg.dprs) {
  const page = await browser.newPage({ viewport: { width: 80, height: PITCH * rows.length }, deviceScaleFactor: dpr })
  const blocks = rows.map((r, i) => `<div style="top:${i * PITCH + 4}px;font:${r.weight} ${r.size}px/${r.line}px '${r.family}'">HHHH</div>`)
  await page.setContent(`<style>${css} body{margin:0;background:#fff} div{position:absolute;left:16px;white-space:nowrap;color:#000}</style>${blocks.join('')}`)
  await page.evaluate(() => document.fonts.ready)
  fs.writeFileSync(path.join(dir, `chromium-dpr${dpr}.png`), await page.screenshot({ fullPage: true }))
  await page.close()
}
await browser.close()
