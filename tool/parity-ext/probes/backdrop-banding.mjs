// Probe for docs/parity.md ("Known engine differences"): what Chromium's `backdrop-filter: blur(40px) saturate(150%)`
// (dsh's `--dsw-menu-backdrop-filter`, used by the to-do panel and every menu surface) draws over a FLAT page.
// Prints the pixel values inside a translucent dark panel (dsh's `--dsw-specific-menu`, rgba(67 69 74 / 0.45) over
// bg-base rgb(21 21 23)) with and without the filter, at device scale factors 1 and 2, with an emulated density
// (Playwright's deviceScaleFactor, the old reference) and a native one (--force-device-scale-factor, a phone's, the
// reference of `tool/parity run`): the banding is an artifact of the emulated one.
//   PARITY_WEB_DEPS=<dir with node_modules> node tool/parity-ext/probes/backdrop-banding.mjs
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(path.join(process.env.PARITY_WEB_DEPS, 'node_modules', 'x.js'))
const { chromium } = require('playwright-core')
const flags = ['--disable-lcd-text', '--font-render-hinting=none']
for (const mode of ['emulated', 'native']) for (const dpr of [1, 2]) {
const browser = await chromium.launch({ args: mode === 'native' ? [...flags, `--force-device-scale-factor=${dpr}`] : flags })
for (const filter of ['none', 'blur(40px) saturate(150%)']) {
  const page = await browser.newPage({ viewport: { width: 390, height: 80 }, deviceScaleFactor: dpr })
  await page.setContent(`<style>html{color-scheme:dark}body{margin:0;background:rgb(21,21,23)}
    div{position:absolute;left:16px;top:16px;width:358px;height:48px;border-radius:16px;
    background:rgba(67,69,74,.45);backdrop-filter:${filter}}</style><div></div>`)
  const png = await page.screenshot()
  const counts = await page.evaluate(async (bytes) => {
    const bmp = await createImageBitmap(new Blob([new Uint8Array(bytes)]))
    const c = new OffscreenCanvas(bmp.width, bmp.height).getContext('2d')
    c.drawImage(bmp, 0, 0)
    const { data } = c.getImageData(Math.round(40 * bmp.width / 390), Math.round(24 * bmp.width / 390), Math.round(300 * bmp.width / 390), Math.round(32 * bmp.width / 390))
    const m = new Map()
    for (let i = 0; i < data.length; i += 4) { const k = `${data[i]},${data[i + 1]},${data[i + 2]}`; m.set(k, (m.get(k) ?? 0) + 1) }
    return [...m].sort((a, b) => b[1] - a[1])
  }, [...png])
  console.log(`${mode.padEnd(8)} dpr ${dpr}  backdrop-filter: ${filter.padEnd(26)} distinct fills: ${counts.length}  ${counts.map(([k, n]) => `${k} x${n}`).join('  ')}`)
  await page.close()
}
await browser.close()
}
