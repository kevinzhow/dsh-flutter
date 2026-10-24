// Captures the real dsh web client (an isolated `dsh web` host) in the states of tool/parity-desktop/cases.json.
//   node web_capture.mjs <out-dir> <cases.json> [case-id ...]
// Environment (all required): PARITY_WEB_DEPS (the parity suite's npm dependencies, for playwright-core),
// PARITY_DESKTOP_HOST_LOG (the host's log holding its launch link), PARITY_DESKTOP_CHROME (a Chromium executable).
// Chromium runs at density 1 with grayscale text; the parity fonts (tool/parity-fonts) are served under the text stack's
// leading names, exactly as the component suite does, so both sides draw the same Noto files.
import { readFileSync, mkdirSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..')
const [out, casesFile, ...only] = process.argv.slice(2)
const need = (k) => process.env[k] ?? (() => { throw new Error(`${k} is not set`) })()
const { chromium } = (await import(pathToFileURL(join(need('PARITY_WEB_DEPS'), 'node_modules', 'playwright-core', 'index.js')).href)).default
const log = readFileSync(need('PARITY_DESKTOP_HOST_LOG'), 'utf8')
const url = /http:\/\/127\.0\.0\.1:\d+\/\?token=[^\s]+/.exec(log)?.[0]
if (url === undefined) throw new Error('no launch link in the host log')
const fonts = join(root, 'tool', 'parity-fonts')
const manifest = JSON.parse(readFileSync(join(fonts, 'manifest.json'), 'utf8'))
let css = ''
for (const fam of manifest.families) for (const name of fam.names) for (const face of fam.faces) {
  const fmt = face.file.endsWith('.otf') ? 'opentype' : 'truetype'
  css += `@font-face{font-family:'${name}';font-weight:${face.weight};font-style:normal;src:url('/__pf/${basename(face.file)}') format('${fmt}');font-display:block}`
}
const cases = JSON.parse(readFileSync(casesFile, 'utf8')).cases.filter(c => only.length === 0 || only.includes(c.id))
mkdirSync(out, { recursive: true })
const browser = await chromium.launch({ executablePath: need('PARITY_DESKTOP_CHROME'), args: ['--disable-lcd-text', '--font-render-hinting=none'] })
for (const c of cases) {
  const ctx = await browser.newContext({
    viewport: { width: c.width, height: c.height }, colorScheme: c.theme, locale: c.locale === 'zh' ? 'zh-CN' : 'en-US',
    reducedMotion: 'reduce',
  })
  const page = await ctx.newPage()
  await page.route('**/__pf/*', route => route.fulfill({
    body: readFileSync(join(fonts, 'files', basename(new URL(route.request().url()).pathname))), contentType: 'font/ttf',
  }))
  await page.addInitScript((sheet) => {
    const add = () => { const st = document.createElement('style'); st.textContent = sheet; document.documentElement.appendChild(st) }
    if (document.documentElement) add(); else document.addEventListener('DOMContentLoaded', add)
  }, css)
  await page.goto(url)
  await page.waitForTimeout(3500)
  await page.evaluate(() => document.fonts.ready)
  await page.locator('button', { hasText: /Continue|继续/ }).first().click({ timeout: 2000 }).catch(() => {})
  await page.keyboard.press('Escape'); await page.waitForTimeout(300); await page.keyboard.press('Escape')
  for (const step of c.web) {
    if (step.click) await page.locator(step.click).first().click()
    else if (step.text) await page.getByText(step.text, { exact: true }).first().click()
    else if (step.wait) await page.waitForTimeout(step.wait)
    else if (step.key) await page.keyboard.press(step.key)
  }
  await page.mouse.move(c.width * 0.5, c.height - 2)
  await page.waitForTimeout(900)
  await page.screenshot({ path: join(out, `${c.id}.png`), animations: 'disabled', caret: 'hide' })
  await ctx.close()
  console.log('web', c.id)
}
await browser.close()
