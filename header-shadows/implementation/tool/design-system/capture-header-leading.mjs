// Focused reference proof. First build the existing parity web host, then run:
// node tool/design-system/capture-header-leading.mjs <react-host> <output>
// Source checkout/hash verification is generate.py --src's responsibility.
import {readFile, mkdir, writeFile} from 'node:fs/promises'
import {createServer} from 'node:http'
import {resolve, extname, join} from 'node:path'
import {pathToFileURL} from 'node:url'
import assert from 'node:assert/strict'

const [distArg, outArg] = process.argv.slice(2)
if (!distArg || !outArg) throw new Error('react-host and output directories are required')
const dist = resolve(distArg), out = resolve(outArg)
const {chromium} = await import(pathToFileURL(join(process.env.PARITY_WEB_DEPS, 'node_modules/playwright-core/index.mjs')))
await mkdir(out, {recursive: true})
const server = createServer(async (request, response) => {
  try {
    const name = new URL(request.url, '[local-runtime-url]').pathname
    const file = resolve(dist, '.' + (name === '/' ? '/index.html' : name))
    if (!file.startsWith(dist + '/')) throw new Error('outside host')
    response.setHeader('Content-Type', {'.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css'}[extname(file)] ?? 'application/octet-stream')
    response.end(await readFile(file))
  } catch { response.writeHead(404); response.end() }
})
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const url = `[local-runtime-url]
const receipts = []
const chromiumVersions = []
try {
  for (const density of [1, 2]) {
    const browser = await chromium.launch({args: ['--disable-lcd-text', '--font-render-hinting=none', `--force-device-scale-factor=${density}`]})
    chromiumVersions.push({density, version: browser.version()})
    try {
      for (const theme of ['light', 'dark']) {
        const context = await browser.newContext({viewport: {width: 400, height: 240}, deviceScaleFactor: density, colorScheme: theme, reducedMotion: 'reduce'})
        const page = await context.newPage()
        await page.addInitScript(({theme, density}) => {
          window.__PARITY__ = {case: {id: 'header-leading', kind: 'header-leading.actual', locale: 'en', theme, viewport: {width: 400, height: 240, density}}, variant: {id: 'default', props: {}}}
        }, {theme, density})
        await page.goto(url)
        const frame = page.locator('[data-header-leading-frame]')
        const toggle = page.getByRole('button', {name: 'Open sidebar', exact: true})
        await toggle.waitFor()
        const box = await toggle.boundingBox()
        assert.deepEqual({width: box.width, height: box.height}, {width: 28, height: 28})
        const read = () => toggle.evaluate(el => {
          const css = getComputedStyle(el), icon = el.querySelector('svg').getBoundingClientRect()
          return {color: css.color, background: css.backgroundColor, outlineColor: css.outlineColor, outlineWidth: css.outlineWidth, outlineStyle: css.outlineStyle, outlineOffset: css.outlineOffset, focused: document.activeElement === el, focusVisible: el.matches(':focus-visible'), modality: document.documentElement.dataset.inputModality, iconWidth: icon.width, iconHeight: icon.height}
        })
        const capture = async state => {
          const actual = await read()
          const file = `source-${theme}-dpr${density}-${state}.png`
          await frame.screenshot({path: join(out, file), animations: 'disabled'})
          receipts.push({theme, density, state, file, actual})
          return actual
        }
        const idle = await capture('idle')
        await toggle.hover()
        const hover = await capture('hover')
        assert.equal(hover.color, idle.color)
        assert.notEqual(hover.background, idle.background)
        await page.mouse.down()
        const pressed = await capture('pressed')
        assert.equal(pressed.background, hover.background)
        await page.mouse.up()
        await page.mouse.move(200, 200)
        // Native pointer focus suppresses the ring; Enter alone retains that.
        await page.keyboard.press('Enter')
        let pointer = await read()
        assert.equal(pointer.modality, 'pointer')
        assert.equal(pointer.outlineColor, 'rgba(0, 0, 0, 0)')
        await page.keyboard.press('Home')
        const focus = await capture('focus')
        assert.equal(focus.modality, 'keyboard')
        assert.equal(focus.outlineWidth, '2px')
        assert.equal(focus.outlineStyle, 'auto')
        assert.equal(focus.outlineOffset, '0px')
        assert.equal(focus.background, idle.background)
        assert.equal(focus.iconWidth, 16)
        assert.equal(focus.iconHeight, 16)
        await page.keyboard.press('Tab')
        await page.keyboard.press('Enter')
        await page.keyboard.press('Space')
        const calls = await page.evaluate(() => ({toggle: Number(document.body.dataset.headerToggleCalls), session: Number(document.body.dataset.headerSessionCalls)}))
        assert.deepEqual(calls, {toggle: 2, session: 2})
        receipts.push({theme, density, check: 'native-callbacks-and-pointer-versus-navigation-focus', passed: true, calls})
        await context.close()
      }
    } finally { await browser.close() }
  }
  await writeFile(join(out, 'source-receipt.json'), JSON.stringify({passed: true, source: 'actual locked HeaderLeadingControls.tsx, Tooltip.tsx and input-modality.ts', referenceMode: 'native device scale factor', chromiumVersions, receipts}, null, 2) + '\n')
} finally { await new Promise(resolve => server.close(resolve)) }
