const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const root = '[workspace]';
const {chromium} = require(path.join(root, 'dsh-flutter/.local/parity-web/node_modules/playwright-core'));
const out = path.join(root, 'scratch/reported-families-artifact');
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
      const page = await browser.newPage({viewport: {width, height: 900}});
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto('[local-runtime-url]' + server.address().port, {waitUntil: 'networkidle'});
      const initial = await page.locator('.case:not([hidden])').count();
      if (initial !== 108) throw new Error('Initial case count differs');
      await page.screenshot({path: path.join(out, `preview-${width}-overview.png`)});
      for (const [field, value] of Object.entries({family: 'model', theme: 'dark', layout: 'phone', locale: 'zh'})) {
        await page.locator(`select[data-filter="${field}"]`).selectOption(value);
      }
      const filtered = await page.locator('.case:not([hidden])').count();
      if (filtered !== 6) throw new Error('Combined filters differ');
      const geometry = await page.evaluate(() => ({
        width: innerWidth, scrollWidth: document.documentElement.scrollWidth,
        controls: [...document.querySelectorAll('select')].map(control => control.getBoundingClientRect().height),
      }));
      if (geometry.scrollWidth > geometry.width || geometry.controls.some(height => height < 44)) {
        throw new Error('Report overflows or touch controls are too small');
      }
      await page.locator('.case:not([hidden])').first().scrollIntoViewIfNeeded();
      await page.waitForFunction(() => [...document.querySelector('.case:not([hidden])').querySelectorAll('img')]
        .every(image => image.complete && image.naturalWidth > 0));
      await page.screenshot({path: path.join(out, `preview-${width}-comparison.png`)});
      if (errors.length) throw new Error(errors.join('\n'));
      results.push({width, initial, filtered, images: await page.locator('img').count(), geometry, errors});
      await page.close();
    }
    fs.writeFileSync(path.join(out, 'preview.json'), JSON.stringify(results, null, 2) + '\n');
    process.stdout.write(JSON.stringify(results) + '\n');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { process.stderr.write(error.stack + '\n'); process.exitCode = 1; });
