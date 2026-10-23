// React provider: renders dsh's real React components (the built host) in Chromium and writes the
// provider output contract (see tool/parity_lib/manifest.py):
//
//   <out>/react/<captureKey>.png
//   <out>/react/<captureKey>.metadata.json
//
//   node capture.mjs --plan <plan.json>
//
// plan.json (written by tool/parity_lib/runner.py):
//   { hostDist, resultsDir, fontsManifest, chromiumArgs: [...], dshCommit,
//     entries: [{ key, case, variant }] }
//
// Determinism: fixed viewport and device scale factor per case, grayscale text (chromiumArgs), the
// pinned Latin face served as 'Segoe UI' (tool/parity-fonts), Playwright `animations: "disabled"` and
// `caret: "hide"`, a fresh browser context per capture and no network: the host is a static bundle.
import { chromium } from 'playwright-core'
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import { createRequire } from 'node:module'

const plan = JSON.parse(fs.readFileSync(process.argv[process.argv.indexOf('--plan') + 1], 'utf8'))
const fontsDir = path.dirname(plan.fontsManifest)
const fonts = JSON.parse(fs.readFileSync(plan.fontsManifest, 'utf8'))
const require = createRequire(import.meta.url)
const playwrightVersion = require('playwright-core/package.json').version

// ---- fonts: verified, then served as @font-face --------------------------------------------------
const faces = []
for (const family of fonts.families) {
  for (const face of family.faces) {
    for (const name of family.names) {
    const file = path.join(fontsDir, face.file)
    const digest = createHash('sha256').update(fs.readFileSync(file)).digest('hex')
    if (digest !== face.sha256) throw new Error(`parity font ${face.file}: sha256 ${digest} != manifest ${face.sha256}`)
    faces.push({ family: name, weight: face.weight, style: face.style, file, url: `/fonts/${path.basename(file)}`, sha256: digest })
    }
  }
}
const fontCss = faces
  .map((f) => `@font-face{font-family:'${f.family}';font-weight:${f.weight};font-style:${f.style};src:url('${f.url}') format('truetype');font-display:block}`)
  .join('\n')

// ---- static server for the host ------------------------------------------------------------------
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.ttf': 'font/ttf', '.json': 'application/json' }
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x')
  let file
  if (url.pathname === '/parity-fonts.css') {
    res.writeHead(200, { 'content-type': 'text/css' })
    return res.end(fontCss)
  }
  if (url.pathname.startsWith('/fonts/')) file = faces.find((f) => f.url === url.pathname)?.file
  else {
    const rel = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname).replace(/^\/+/, '')
    const candidate = path.resolve(plan.hostDist, rel)
    if (candidate.startsWith(path.resolve(plan.hostDist) + path.sep)) file = candidate
  }
  if (!file || !fs.existsSync(file)) {
    res.writeHead(404)
    return res.end('not found')
  }
  res.writeHead(200, { 'content-type': MIME[path.extname(file)] ?? 'application/octet-stream' })
  fs.createReadStream(file).pipe(res)
})
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
const origin = `http://127.0.0.1:${server.address().port}`

// ---- capture -------------------------------------------------------------------------------------
const outDir = path.join(plan.resultsDir, 'react')
fs.mkdirSync(outDir, { recursive: true })
const browser = await chromium.launch({ args: plan.chromiumArgs ?? [] })
const failures = []

async function applyInteractions(page, steps) {
  for (const step of steps ?? []) {
    const target = step.target ? page.locator(`[data-parity-id="${step.target}"]`) : null
    switch (step.type) {
      case 'hover': await target.hover(); break
      case 'press': await target.hover(); await page.mouse.down(); break
      case 'click': await target.click(); break
      case 'tab': for (let i = 0; i < (step.count ?? 1); i++) await page.keyboard.press('Tab'); break
      case 'type': await target.pressSequentially(step.text); break
      case 'wait': await page.waitForTimeout(step.ms); break
      default: throw new Error(`unknown interaction ${step.type}`)
    }
  }
}

/** Typography / token probes of the rendered DOM (metadata only; the report shows them next to the images). */
async function probes(page, selector) {
  return page.evaluate((sel) => {
    const root = document.querySelector(sel)
    const hex = (c) => c
    const typography = []
    const styleTokens = []
    for (const el of [root, ...root.querySelectorAll('*')]) {
      const cs = getComputedStyle(el)
      const own = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('').trim()
      if (own && typography.length < 24) {
        typography.push({
          selector: el.dataset.parityId ? `[data-parity-id="${el.dataset.parityId}"]` : el.tagName.toLowerCase(),
          text: own.slice(0, 60), fontFamily: cs.fontFamily, fontSize: parseFloat(cs.fontSize), fontWeight: Number(cs.fontWeight),
          lineHeight: cs.lineHeight === 'normal' ? null : parseFloat(cs.lineHeight), letterSpacing: cs.letterSpacing === 'normal' ? 0 : parseFloat(cs.letterSpacing),
          color: hex(cs.color),
        })
      }
      const box = el.getBoundingClientRect()
      const hasBorder = parseFloat(cs.borderTopWidth) > 0
      if (el !== root && styleTokens.length < 16 && (cs.backgroundColor !== 'rgba(0, 0, 0, 0)' || hasBorder || cs.boxShadow !== 'none')) {
        styleTokens.push({
          selector: el.dataset.parityId ? `[data-parity-id="${el.dataset.parityId}"]` : el.tagName.toLowerCase(),
          size: `${box.width.toFixed(1)}x${box.height.toFixed(1)}`,
          backgroundColor: cs.backgroundColor, ...(hasBorder ? { borderColor: cs.borderTopColor, borderWidth: parseFloat(cs.borderTopWidth) } : {}),
          borderRadius: cs.borderTopLeftRadius, ...(cs.boxShadow !== 'none' ? { shadow: cs.boxShadow } : {}), opacity: cs.opacity,
        })
      }
    }
    return { typography, styleTokens }
  }, selector)
}

/** Faces Chromium really drew the text with (CDP CSS.getPlatformFontsForNode), glyph counts per family. */
async function platformFonts(page, selector) {
  const cdp = await page.context().newCDPSession(page)
  await cdp.send('DOM.enable')
  await cdp.send('CSS.enable')
  const { root } = await cdp.send('DOM.getDocument', { depth: -1 })
  const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: `${selector}, ${selector} *` })
  const usage = {}
  for (const nodeId of nodeIds.slice(0, 400)) {
    try {
      const { fonts: used } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId })
      for (const f of used) {
        const key = `${f.familyName}${f.isCustomFont ? '' : ' (system)'}`
        usage[key] = (usage[key] ?? 0) + f.glyphCount
      }
    } catch { /* nodes without layout */ }
  }
  await cdp.detach()
  return usage
}

for (const entry of plan.entries) {
  const { key, case: c, variant } = entry
  const { width, height, density } = c.viewport
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: density, locale: c.locale, colorScheme: c.theme, reducedMotion: 'reduce' })
  const page = await context.newPage()
  const errors = []
  page.on('pageerror', (e) => errors.push(String(e)))
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()) })
  try {
    await page.addInitScript((ctx) => { window.__PARITY__ = ctx }, { case: c, variant })
    await page.goto(`${origin}/`)
    await page.waitForSelector('body[data-parity-ready="true"]')
    const failure = await page.evaluate(() => document.body.dataset.parityError)
    if (failure) throw new Error(failure)
    await page.evaluate(() => document.fonts.ready)
    await applyInteractions(page, variant.interactions)
    const selector = c.capture?.selector ?? '[data-parity-target]'
    const target = page.locator(selector)
    await target.waitFor({ state: 'visible' })
    const png = path.join(outDir, `${key}.png`)
    const crop = c.capture?.crop ?? 'element'
    const box = await target.boundingBox()
    const shotOptions = { path: png, animations: 'disabled', caret: 'hide', scale: 'device' }
    if (crop === 'viewport') await page.screenshot(shotOptions)
    else await target.screenshot(shotOptions)
    if (errors.length) throw new Error(`page errors: ${errors.join(' | ')}`)
    const faceStatus = await page.evaluate(() => [...document.fonts].map((f) => ({ family: f.family.replace(/"/g, ''), weight: f.weight, status: f.status })))
    const metadata = {
      provider: 'react',
      providerType: 'playwright-chromium',
      source: 'dsh-react',
      caseId: c.id,
      variantId: variant.id,
      captureKey: key,
      theme: c.theme,
      locale: c.locale,
      image: `visual-testing-results/react/${key}.png`,
      viewport: c.viewport,
      selector,
      crop: { mode: crop, rect: box && { x: box.x, y: box.y, width: box.width, height: box.height } },
      react: {
        browser: `chromium ${browser.version()}`,
        playwright: playwrightVersion,
        chromiumArgs: plan.chromiumArgs ?? [],
        animationPolicy: 'playwright animations: disabled; prefers-reduced-motion: reduce',
        dshCommit: plan.dshCommit ?? null,
        renderer: 'static vite bundle of the real dsh components, no network',
      },
      fonts: {
        manifest: path.relative(process.cwd(), plan.fontsManifest),
        faces: faces.map(({ family, weight, style, sha256 }) => ({ family, weight, style, sha256 })),
        documentFonts: faceStatus,
        platformFonts: await platformFonts(page, selector),
      },
      ...(await probes(page, selector)),
      capturedAt: new Date().toISOString(),
    }
    fs.writeFileSync(path.join(outDir, `${key}.metadata.json`), JSON.stringify(metadata, null, 2) + '\n')
    console.log(`react ${key}`)
  } catch (error) {
    failures.push({ key, error: String(error) })
    console.error(`react ${key} FAILED: ${error}`)
  } finally {
    await context.close()
  }
}
await browser.close()
server.close()
if (failures.length) {
  fs.writeFileSync(path.join(plan.resultsDir, 'react-failures.json'), JSON.stringify(failures, null, 2) + '\n')
  process.exit(1)
}
