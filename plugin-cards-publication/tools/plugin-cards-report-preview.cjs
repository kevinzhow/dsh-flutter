// Preview the complete local report without contacting any external origin.
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const folder = path.resolve(process.argv[2]);
const {chromium} = require(path.join(root, 'dsh-flutter/.local/parity-web/node_modules/playwright-core'));
const receipt = JSON.parse(fs.readFileSync(path.join(folder, 'build-receipt.json')));
const digest = data => crypto.createHash('sha256').update(data).digest('hex');
const files = new Map(receipt.files.map(row => [row.path, row]));
if (files.size !== 225 || receipt.compositeAssets !== 224) throw Error('Complete report required');
for (const [name, row] of files) {
  const data = fs.readFileSync(path.join(folder, name));
  if (data.length !== row.bytes || digest(data) !== row.sha256) throw Error('Changed report file: ' + name);
}
const requested = new Set();
const server = http.createServer((req, res) => {
  const name = new URL(req.url, 'http://127.0.0.1').pathname.slice(1) || 'index.html';
  if (name === 'favicon.ico') {res.writeHead(204); return res.end();}
  if (!files.has(name)) {res.writeHead(404); return res.end();}
  const data = fs.readFileSync(path.join(folder, name));
  if (digest(data) !== files.get(name).sha256) {res.writeHead(409); return res.end();}
  requested.add(name);
  res.writeHead(200, {'Content-Type': name.endsWith('.png') ? 'image/png' : 'text/html; charset=utf-8'});
  res.end(data);
});
(async () => {
  let browser;
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = 'http://127.0.0.1:' + server.address().port;
    browser = await chromium.launch({headless: true, args: ['--no-sandbox']});
    const rows = [];
    for (const width of [300, 1280]) {
      const page = await browser.newPage({viewport: {width, height: 960}, colorScheme: 'dark'});
      const errors = [], external = [], failed = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('requestfailed', request => failed.push(request.url()));
      await page.route('**/*', route => {
        if (route.request().url().startsWith(origin + '/')) return route.continue();
        external.push(route.request().url()); return route.abort();
      });
      await page.goto(origin + '/', {waitUntil: 'networkidle'});
      const visible = () => page.locator('.pair:not([hidden])').count();
      if (await visible() !== 224 || await page.locator('img').count() !== 224) throw Error('Missing pairs/images');
      // Decode in small batches so this check does not require every full-DPR
      // frame to remain simultaneously decoded in the browser's image cache.
      const decoded = await page.evaluate(async () => {
        const sources = [...document.images].map(image => image.getAttribute('src'));
        const result = [];
        for (let offset = 0; offset < sources.length; offset += 4) {
          for (const src of sources.slice(offset, offset + 4)) {
            const image = new Image(); image.src = src; await image.decode();
            if (!image.naturalWidth || !image.naturalHeight) throw Error('Undecoded image ' + src);
            result.push({src, size: [image.naturalWidth, image.naturalHeight]});
            image.src = '';
          }
        }
        return result;
      });
      const dimensions = new Map(Object.values(receipt.composites).map(row => [row.path, row.size]));
      if (decoded.length !== 224 || decoded.some(row => JSON.stringify(row.size) !== JSON.stringify(dimensions.get(row.src)))) {
        throw Error('Browser decoded a different asset size');
      }
      await page.screenshot({path: path.join(folder, `preview-${width}-overview.png`)});
      const filters = [
        ['scenario', 'long-tags', 16], ['theme', 'dark', 8], ['layout', 'phone', 4],
        ['locale', 'en', 2], ['dpr', '1', 1], ['state', 'idle', 1],
      ];
      const checks = [];
      for (const [name, value, expected] of filters) {
        await page.locator(`select[data-filter="${name}"]`).selectOption(value);
        const actual = await visible();
        if (actual !== expected) throw Error('Filter count differs: ' + name + '/' + actual);
        checks.push({name, value, actual});
      }
      const pair = page.locator('.pair:not([hidden])');
      await pair.scrollIntoViewIfNeeded();
      await pair.locator('img').evaluate(image => image.decode());
      await page.screenshot({path: path.join(folder, `preview-${width}-long-tags.png`)});
      await pair.locator('summary').click();
      await pair.locator('details').scrollIntoViewIfNeeded();
      await page.screenshot({path: path.join(folder, `preview-${width}-geometry.png`)});
      const geometry = await page.evaluate(() => ({
        width: innerWidth, scrollWidth: document.documentElement.scrollWidth,
        colorScheme: getComputedStyle(document.documentElement).colorScheme,
        controls: [...document.querySelectorAll('select,input,button')].map(control => {
          const rect = control.getBoundingClientRect(); return {width: rect.width, height: rect.height};
        }),
        imageScrollers: [...document.querySelectorAll('.pair:not([hidden]) .image-scroll')].map(node => ({
          clientWidth: node.clientWidth, scrollWidth: node.scrollWidth,
        })),
      }));
      if (geometry.scrollWidth > width || geometry.colorScheme !== 'light' ||
          geometry.controls.some(control => control.width <= 0 || control.height < 44) ||
          geometry.imageScrollers.some(node => node.clientWidth <= 0 || node.scrollWidth < node.clientWidth)) {
        throw Error('Report layout differs: ' + JSON.stringify(geometry));
      }
      await page.locator('#query').fill('a deliberately absent search phrase 872f99');
      if (await visible() !== 0) throw Error('Empty search result differs');
      await page.locator('#reset').click();
      if (await visible() !== 224) throw Error('Reset lost pairs');
      if (errors.length || external.length || failed.length) throw Error(JSON.stringify({errors, external, failed}));
      rows.push({width, htmlSha256: files.get('index.html').sha256, pairs: 224, decodedAssets: decoded,
        filters: checks, resetCount: 224, geometry, errors, externalRequests: external, failedRequests: failed});
      await page.close();
    }
    if (requested.size !== 225 || [...files.keys()].some(name => !requested.has(name))) throw Error('Not every report file was served');
    for (const [name, row] of files) if (digest(fs.readFileSync(path.join(folder, name))) !== row.sha256) throw Error('Changed report');
    fs.writeFileSync(path.join(folder, 'preview.json'), JSON.stringify({
      schema: 'whalee-plugin-cards-report-preview/1', scriptSha256: digest(fs.readFileSync(__filename)),
      all225FilesServedWithVerifiedBytes: true, widths: rows,
    }, null, 2) + '\n');
    process.stdout.write(JSON.stringify({widths: rows.map(row => row.width), decodedPerWidth: 224, files: 225, passed: true}) + '\n');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => {process.stderr.write(error.stack + '\n'); process.exitCode = 1;});
