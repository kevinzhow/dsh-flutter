// Read-only actual-source control for the native compact Pro-root guard.
// Source scripts/pr16-env.sh, then pass --repo, --host-dist and a fresh --out.
// The host is the existing parity host importing the actual pinned ModelSelect.
import {readFile, writeFile, mkdir, readdir, access} from 'node:fs/promises'
import {createServer} from 'node:http'
import {resolve, extname, join, relative, dirname} from 'node:path'
import {pathToFileURL, fileURLToPath} from 'node:url'
import {createRequire} from 'node:module'
import {createHash} from 'node:crypto'
import {execFileSync} from 'node:child_process'
import assert from 'node:assert/strict'

const argv = Object.fromEntries(process.argv.slice(2).reduce((rows, arg, i, all) => {
  if (arg.startsWith('--')) rows.push([arg.slice(2), all[i + 1]])
  return rows
}, []))
for (const key of ['repo', 'host-dist', 'out']) if (!argv[key]) throw Error(`Missing --${key}`)
const repo = resolve(argv.repo), dist = resolve(argv['host-dist']), out = resolve(argv.out)
try { await access(out); throw Error('Refusing to overwrite source proof output') }
catch (error) { if (error.code !== 'ENOENT') throw error }
await mkdir(out, {recursive: true})
const sha = data => createHash('sha256').update(data).digest('hex')
const json = async file => JSON.parse(await readFile(file, 'utf8'))
const lock = await json(join(repo, 'tool/design-system/sources.lock.json'))
const src = resolve(process.env.DSH_SRC)
assert.equal(execFileSync('git', ['-C', src, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), lock.referenceCommit)
const sourceFiles = {}
for (const file of [
  'packages/client/ui-model-selection/src/client/ModelSelect.tsx',
  'packages/client/ui-model-selection/src/client/ModelSelect.module.css',
  'packages/client/ui-primitives/src/MenuSurface.tsx',
  'packages/client/ui-primitives/src/MenuSurface.module.css',
]) {
  const hash = sha(await readFile(join(src, file)))
  const expected = lock.packages.map(p => p.referenceSourceSha256?.[file]).find(Boolean)
  if (expected) assert.equal(hash, expected)
  sourceFiles[file] = {sha256: hash, matchedExplicitSourceLock: Boolean(expected)}
}
const bundleFiles = {}
async function hashHost(folder) {
  for (const entry of await readdir(folder, {withFileTypes: true})) {
    const path = join(folder, entry.name)
    if (entry.isDirectory()) await hashHost(path)
    else bundleFiles[relative(dist, path)] = sha(await readFile(path))
  }
}
await hashHost(dist)
const auditFile = join(repo, 'tool/design-system/recipes.generated.json')
const audit = await json(auditFile), recipe = audit.metrics.DshModelMenuRecipe
const themeFile = join(repo, 'packages/dsh_theme/assets/themes/official.theme.json')
const pack = await json(themeFile)
const fontFile = join(repo, 'tool/parity-fonts/manifest.json'), fonts = await json(fontFile)
const fontPaths = new Map(), fontFaces = []
let fontCss = ''
for (const family of fonts.families) for (const face of family.faces) {
  const id = String(fontPaths.size) + extname(face.file)
  const path = join(dirname(fontFile), face.file)
  fontPaths.set(id, path)
  fontFaces.push({file: face.file, sha256: sha(await readFile(path))})
  for (const name of family.names) fontCss += `@font-face{font-family:'${name}';font-weight:${face.weight};font-style:normal;src:url('/__proof_fonts/${id}');font-display:block}`
}
const {chromium} = await import(pathToFileURL(join(process.env.PARITY_WEB_DEPS, 'node_modules/playwright-core/index.mjs')))
const sharp = createRequire(pathToFileURL(join(process.env.PARITY_VT_DEPS, 'package.json')))('sharp')
const server = createServer(async (request, response) => {
  try {
    const name = new URL(request.url, '[local-runtime-url]').pathname
    if (name === '/parity-fonts.css') {
      response.setHeader('Content-Type', 'text/css'); response.end(fontCss); return
    }
    if (name.startsWith('/__proof_fonts/')) {
      const path = fontPaths.get(name.slice('/__proof_fonts/'.length))
      if (!path) throw Error('Unknown font')
      response.setHeader('Content-Type', 'font/ttf'); response.end(await readFile(path)); return
    }
    const file = resolve(dist, '.' + (name === '/' ? '/index.html' : name))
    if (!file.startsWith(dist + '/')) throw Error('Outside host')
    response.setHeader('Content-Type', {'.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css'}[extname(file)] ?? 'application/octet-stream')
    response.end(await readFile(file))
  } catch { response.writeHead(404); response.end() }
})
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const browser = await chromium.launch({args: ['--disable-lcd-text', '--font-render-hinting=none']})
const receipt = {
  referenceCommit: lock.referenceCommit, chromiumVersion: browser.version(),
  recipeSha256: sha(await readFile(auditFile)), themeSha256: sha(await readFile(themeFile)),
  sourceFiles, hostBundleFiles: bundleFiles, fontFaces,
  scriptSha256: sha(await readFile(fileURLToPath(import.meta.url))), cases: [], passed: false,
}
async function differences(a, b, rect) {
  const region = {left: rect[0], top: rect[1], width: rect[2] - rect[0], height: rect[3] - rect[1]}
  const x = await sharp(a).extract(region).ensureAlpha().raw().toBuffer()
  const y = await sharp(b).extract(region).ensureAlpha().raw().toBuffer()
  let changedPixels = 0, maxChannelDifference = 0
  for (let i = 0; i < x.length; i += 4) {
    let changed = false
    for (let channel = 0; channel < 4; channel++) {
      const value = Math.abs(x[i + channel] - y[i + channel])
      changed ||= value !== 0; maxChannelDifference = Math.max(maxChannelDifference, value)
    }
    changedPixels += Number(changed)
  }
  return {changedPixels, maxChannelDifference}
}
try {
  for (const [id, width, height, theme, horizontal] of [
    ['desktop-light', 1280, 720, 'light', [1028, 1248]],
    ['phone-dark', 390, 844, 'dark', [138, 358]],
  ]) {
    const context = await browser.newContext({viewport: {width, height}, colorScheme: theme, reducedMotion: 'reduce', deviceScaleFactor: 1})
    const page = await context.newPage()
    await page.addInitScript(({width, height, theme}) => {
      window.__PARITY__ = {case: {id: 'source-clearance-proof', kind: 'reported-model.menu', locale: 'en', theme, viewport: {width, height, density: 1}}, variant: {id: 'default', props: {platform: 'other'}}}
    }, {width, height, theme})
    await page.goto(`[local-runtime-url]
    const trigger = page.locator('[data-parity-id="model-chip"]')
    await trigger.waitFor(); await page.evaluate(() => document.fonts.ready.then(() => true))
    async function capture(name) {
      await page.mouse.move(width - 4, 4)
      const buffer = await page.screenshot({animations: 'disabled'})
      await writeFile(join(out, `${id}-${name}.png`), buffer)
      return buffer
    }
    const closed = await capture('closed')
    await trigger.click()
    const menu = page.locator('[data-parity-id="model-sheet"]')
    await menu.waitFor()
    const twoBounds = await menu.boundingBox(), two = await capture('two-row-root')
    await page.locator('[data-parity-id="model-root-model"]').click()
    await page.locator('input').fill('Pro')
    await page.getByRole('menuitemradio', {name: 'DeepSeek V4.1 Pro', exact: true}).click()
    await menu.waitFor({state: 'detached'})
    const selected = await capture('pro-selected')
    await trigger.click(); await menu.waitFor()
    const oneBounds = await menu.boundingBox(), one = await capture('pro-root')
    const triggerBounds = await trigger.boundingBox()
    const css = await menu.evaluate(el => ({
      boxShadow: getComputedStyle(el).boxShadow, padding: getComputedStyle(el).padding,
      rows: [...el.querySelectorAll('[role="menuitem"]')].map(row => ({height: row.getBoundingClientRect().height, text: row.textContent})),
    }))
    const shadow = pack.modes[theme].shadows[audit.metrics.DshMenuSurfaceRecipe.shadowToken]
    const layers = shadow.split(',').map(layer => {
      const values = layer.trim().split(/\s+/).slice(0, 4).map(value => Number(value.replace(/px$/, '')))
      assert(values.every(Number.isFinite)); return values
    })
    const upwardReach = Math.max(0, ...layers.map(([, y, blur, spread]) => 3 * blur / 2 + spread - y))
    assert.equal(css.rows.length, 1); assert.equal(css.rows[0].height, recipe.cellHeight)
    assert.equal(oneBounds.height, recipe.cellHeight + 2 * recipe.padding)
    assert.equal(twoBounds.height, 2 * recipe.cellHeight + 2 * recipe.padding)
    assert.equal(oneBounds.y + oneBounds.height, triggerBounds.y - recipe.anchorGap)
    assert(upwardReach < recipe.cellHeight)
    const rect = [horizontal[0], oneBounds.y - recipe.cellHeight, horizontal[1], oneBounds.y - upwardReach]
    assert(rect.every(Number.isInteger))
    const correct = await differences(selected, one, rect), wrongTwoRow = await differences(closed, two, rect)
    assert.equal(correct.changedPixels, 0)
    assert(wrongTwoRow.changedPixels > 0)
    receipt.cases.push({id, viewport: {width, height, density: 1}, theme, twoBounds, oneBounds, triggerBounds, css, authoredShadow: shadow, upwardReach, sourceDerivedRect: rect, correctOneRow: correct, actualTwoRowControl: wrongTwoRow})
    await context.close()
  }
  receipt.passed = true
} catch (error) { receipt.error = String(error); throw error }
finally {
  await writeFile(join(out, 'geometry.json'), JSON.stringify(receipt, null, 2) + '\n')
  await browser.close(); await new Promise(resolve => server.close(resolve))
}
console.log(JSON.stringify({passed: receipt.passed, chromiumVersion: receipt.chromiumVersion, cases: receipt.cases}, null, 2))
