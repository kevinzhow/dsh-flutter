// Capture the pinned browser's native checkbox without DSH's label opacity.
// Usage: node tool/design-system/probe_chromium_checkbox.mjs <output-directory>
import {createRequire} from 'node:module'
import {mkdir, readFile, writeFile} from 'node:fs/promises'
import {fileURLToPath} from 'node:url'
import path from 'node:path'

if (process.argv.length !== 3) throw new Error('An output directory is required')
const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../..')
const require = createRequire(path.join(root, 'tool/parity-web/capture.mjs'))
const {chromium} = require('playwright-core')
const theme = JSON.parse(await readFile(path.join(root, 'packages/dsh_theme/assets/themes/official.theme.json'), 'utf8'))
const out = path.resolve(process.argv[2])
await mkdir(out, {recursive: true})
const rows = []
for (const density of [1, 2.625]) {
  const args = ['--disable-lcd-text', '--font-render-hinting=none']
  if (density !== 1) args.push(`--force-device-scale-factor=${density}`)
  const browser = await chromium.launch({args})
  for (const mode of ['light', 'dark']) {
    for (const checked of [false, true]) {
      for (const disabled of [false, true]) {
        for (const state of ['normal', 'hover', 'pressed']) {
          const context = await browser.newContext({viewport: {width: 200, height: 100}, deviceScaleFactor: density, colorScheme: mode})
          const page = await context.newPage()
          const accent = theme.modes[mode].colors['--dsw-alias-brand-primary']
          const background = theme.modes[mode].colors['--dsw-alias-bg-base']
          await page.setContent(`<style>html{color-scheme:${mode}}body{background:${background};margin:0}input{position:absolute;left:32px;top:32px;width:16px;height:16px;margin:0;accent-color:${accent}}</style><input type="checkbox" ${checked ? 'checked' : ''} ${disabled ? 'disabled' : ''}>`)
          const input = page.locator('input')
          if (state !== 'normal') await page.mouse.move(40, 40)
          if (state === 'pressed') await page.mouse.down()
          const id = `${mode}-${checked ? 'on' : 'off'}-${disabled ? 'disabled' : 'enabled'}-${state}-${String(density).replace('.', '_')}`
          await input.screenshot({path: path.join(out, `${id}.png`), animations: 'disabled'})
          rows.push({id, density, mode, checked, disabled, state, accent, background, browser: browser.version(),
            styles: await input.evaluate(el => { const s = getComputedStyle(el); return {appearance:s.appearance,colorScheme:s.colorScheme,width:s.width,height:s.height,accentColor:s.accentColor} })})
          if (state === 'pressed') await page.mouse.up()
          await context.close()
        }
      }
    }
  }
  await browser.close()
}
await writeFile(path.join(out, 'probe.json'), JSON.stringify(rows, null, 2) + '\n')
console.log(`Captured ${rows.length} native checkbox states`)
