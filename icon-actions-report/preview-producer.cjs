// Offline Artifact preview; reads the completed report and writes proof only.
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const out = path.resolve(process.argv[2]);
const {chromium} = require(path.join(root, 'dsh-flutter/.local/parity-web/node_modules/playwright-core'));
const document = fs.readFileSync(path.join(out, 'index.html'));
const sha = crypto.createHash('sha256').update(document).digest('hex');
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
    const origin = 'http://127.0.0.1:' + server.address().port;
    for (const width of [300, 1280]) {
      const page = await browser.newPage({viewport: {width, height: 960}, colorScheme: 'dark'});
      const errors = [], external = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.route('**/*', route => {
        if (route.request().url().startsWith(origin + '/') || route.request().url().startsWith('data:')) return route.continue();
        external.push(route.request().url()); return route.abort();
      });
      await page.goto(origin + '/', {waitUntil: 'networkidle'});
      const visible = () => page.locator('.pair:not([hidden])').count();
      if (await visible() !== 144 || await page.locator('.manager').count() !== 16 || await page.locator('img').count() !== 464) {
        throw Error('Report lost source regions or real manager pairs');
      }
      const images = await page.evaluate(async () => {
        const images = [...document.images];
        images.forEach(image => { image.loading = 'eager'; });
        await Promise.all(images.map(image => image.decode()));
        return images.every(image => image.complete && image.naturalWidth > 0);
      });
      if (!images) throw Error('A report image did not decode');
      await page.screenshot({path: path.join(out, `preview-${width}-overview.png`)});
      const controls = page.locator('select[data-token]');
      for (const [index, value] of ['iconAction', 'dark', '1', 'mouse', 'pending'].entries()) {
        await controls.nth(index).selectOption(value);
      }
      if (await visible() !== 5) throw Error('IconAction pending-state filter differs');
      await page.locator('.pair:not([hidden])').first().scrollIntoViewIfNeeded();
      await page.screenshot({path: path.join(out, `preview-${width}-pending.png`)});
      const geometry = await page.evaluate(() => ({width: innerWidth, scrollWidth: document.documentElement.scrollWidth,
        colorScheme: getComputedStyle(document.documentElement).colorScheme,
        controls: [...document.querySelectorAll('select')].map(c => ({width: c.getBoundingClientRect().width, height: c.getBoundingClientRect().height}))}));
      if (geometry.scrollWidth > width || geometry.colorScheme !== 'light' || geometry.controls.some(c => c.width <= 0 || c.height <= 0)) {
        throw Error('Report overflows, changes theme or hides a control: ' + JSON.stringify(geometry));
      }
      if (errors.length || external.length) throw Error(JSON.stringify({errors, external}));
      results.push({width, htmlSha256: sha, pairs: 144, managerPairs: 16, images: 464,
        allImagesDecoded: images, filteredPending: 5, geometry, errors, externalRequests: external});
      await page.close();
    }
    fs.writeFileSync(path.join(out, 'preview.json'), JSON.stringify(results, null, 2) + '\n');
    process.stdout.write(JSON.stringify(results) + '\n');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { process.stderr.write(error.stack + '\n'); process.exitCode = 1; });
