// Offline report preview only; no app, device, upload or external request.
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const out = path.resolve(process.argv[2] || path.join(root, 'scratch/header-shadows-artifact'));
const {chromium} = require(path.join(root, 'dsh-flutter/.local/parity-web/node_modules/playwright-core'));
const document = fs.readFileSync(path.join(out, 'index.html'));
const server = http.createServer((req, res) => {
  if (req.url === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'}); res.end(document);
});
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  const results = [];
  try {
    browser = await chromium.launch({headless: true, args: ['--no-sandbox']});
    for (const width of [300, 1280]) {
      const page = await browser.newPage({viewport: {width, height: 960}});
      const errors = [], requests = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('request', request => {
        if (!request.url().startsWith('[local-runtime-url]' + server.address().port + '/')) requests.push(request.url());
      });
      await page.goto('[local-runtime-url]' + server.address().port + '/', {waitUntil: 'networkidle'});
      const visible = () => page.locator('.case:not([hidden])').count();
      if (await visible() !== 124 || await page.locator('img').count() !== 248) throw Error('Report lost cases/images');
      if (await page.locator('[data-menu-source-proof="verified"]').count() !== 1) throw Error('Source controls/semantic boundary evidence missing');
      if (!(await page.locator('.checks').innerText()).includes('23 / 54')) throw Error('Android scene count is stale');
      await page.screenshot({path: path.join(out, `preview-${width}-overview.png`)});
      for (const [field, value] of Object.entries({family: 'header', theme: 'dark', layout: 'component', locale: 'none'})) {
        await page.locator(`select[data-filter="${field}"]`).selectOption(value);
      }
      if (await visible() !== 8) throw Error('Header filters differ');
      const first = page.locator('.case:not([hidden])').first();
      await first.scrollIntoViewIfNeeded();
      await page.waitForFunction(() => [...document.querySelector('.case:not([hidden])').querySelectorAll('img')]
        .every(image => image.complete && image.naturalWidth > 0));
      await page.screenshot({path: path.join(out, `preview-${width}-header.png`)});
      for (const [field, value] of Object.entries({family: 'model', theme: 'dark', layout: 'phone', locale: 'zh'})) {
        await page.locator(`select[data-filter="${field}"]`).selectOption(value);
      }
      if (await visible() !== 6) throw Error('Existing model filters differ');
      const geometry = await page.evaluate(() => ({width: innerWidth, scrollWidth: document.documentElement.scrollWidth,
        controls: [...document.querySelectorAll('select')].map(c => ({height: c.getBoundingClientRect().height, width: c.getBoundingClientRect().width}))}));
      if (geometry.scrollWidth > width || geometry.controls.some(c => c.height < 44 || c.width < 44)) throw Error('Overflow or undersized controls');
      if (errors.length || requests.length) throw Error(JSON.stringify({errors, requests}));
      results.push({width, initial: 124, images: 248, headerFiltered: 8, modelFiltered: 6, sourceControls: true,
        exactFinalRuntime: true, androidScenes: 23, androidChecks: 54, geometry, errors, externalRequests: requests});
      await page.close();
    }
    fs.writeFileSync(path.join(out, 'preview.json'), JSON.stringify(results, null, 2) + '\n');
    process.stdout.write(JSON.stringify(results) + '\n');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { process.stderr.write(error.stack + '\n'); process.exitCode = 1; });
