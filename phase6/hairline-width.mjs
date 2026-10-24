// Probe for docs/parity.md ("What Blink does in the captures"): how wide does Chromium draw a border of `0.5px` (and
// `1px`) at device scale factors 1, 2 and 3?  Two ways of getting the density are compared:
//   emulated  Playwright's `deviceScaleFactor` (what the React captures use)
//   native    `--force-device-scale-factor=N` at launch (the browser's own zoom-for-DSF, a phone's setup), context at 1
// Prints the border's thickness in device pixels, measured on the left edge of a box in a screenshot, and the thickness
// of the box's total width (border-box width in device px), so box sizing is visible too.
//   PARITY_WEB_DEPS=<dir with node_modules> node tool/parity-ext/probes/hairline-width.mjs
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(path.join(process.env.PARITY_WEB_DEPS, 'node_modules', 'x.js'))
const { chromium } = require('playwright-core')
const DENSITIES = (process.argv[2] ?? "1,2,3").split(",").map(Number)
const args = ['--disable-lcd-text', '--font-render-hinting=none']
const html = (bw) => `<style>html{background:#fff}body{margin:0}
  .a{position:absolute;left:20px;top:20px;width:40px;height:40px;box-sizing:border-box;border:${bw} solid #000}
  .b{position:absolute;left:100px;top:20px;width:40px;height:40px;box-sizing:content-box;border:${bw} solid #000}</style>
  <div class="a"></div><div class="b"></div>`

async function measure(page, bw) {
  await page.setContent(html(bw))
  const dpr = await page.evaluate(() => window.devicePixelRatio)
  const layout = await page.evaluate(() => {
    const cs = getComputedStyle(document.querySelector('.a'))
    const r = document.querySelector('.b').getBoundingClientRect()
    return { computedBorder: cs.borderLeftWidth, contentBoxWidth: r.width }
  })
  const png = await page.screenshot()
  const run = await page.evaluate(async ([bytes, dpr]) => {
    const bmp = await createImageBitmap(new Blob([new Uint8Array(bytes)]))
    const c = new OffscreenCanvas(bmp.width, bmp.height).getContext('2d')
    c.drawImage(bmp, 0, 0)
    const y = Math.round(40 * dpr)
    const row = c.getImageData(0, y, bmp.width, 1).data
    const dark = []
    for (let x = 0; x < bmp.width; x++) if (row[x * 4] < 128) dark.push(x)
    // thickness of the first dark run (the .a box's left edge) and the extent of the .b box
    let n = 1
    while (n < dark.length && dark[n] === dark[n - 1] + 1) n++
    const bStart = dark.find((x) => x >= 90 * dpr)
    const bEnd = dark[dark.length - 1]
    const levels = [...new Set(dark.slice(0, n + 1).map((x) => row[x * 4]))]
    return { thicknessPx: n, bWidthPx: bEnd - bStart + 1, levels }
  }, [[...png], dpr])
  return { dpr, ...layout, ...run }
}

const browser = await chromium.launch({ args })
for (const d of DENSITIES) {
  for (const bw of ['0.5px', '1px']) {
    const page = await browser.newPage({ viewport: { width: 200, height: 80 }, deviceScaleFactor: d })
    const r = await measure(page, bw)
    console.log(`emulated dpr ${d}  border ${bw.padEnd(5)} -> ${r.thicknessPx} device px = ${r.thicknessPx / d} CSS px` +
      `  (computed ${r.computedBorder}, content-box box ${r.bWidthPx} device px for 40 + 2*border, levels ${r.levels})`)
    await page.close()
  }
}
await browser.close()
for (const d of DENSITIES) {
  const b = await chromium.launch({ args: [...args, `--force-device-scale-factor=${d}`] })
  for (const bw of ['0.5px', '1px']) {
    const page = await b.newPage({ viewport: { width: 200, height: 80 }, deviceScaleFactor: d })
    const r = await measure(page, bw)
    console.log(`native   dpr ${d}  border ${bw.padEnd(5)} -> ${r.thicknessPx} device px = ${r.thicknessPx / d} CSS px` +
      `  (computed ${r.computedBorder}, content-box box ${r.bWidthPx} device px for 40 + 2*border, levels ${r.levels})`)
    await page.close()
  }
  await b.close()
}
