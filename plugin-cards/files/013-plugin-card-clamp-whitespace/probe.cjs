// Actual published Manager diagnostic; unchanged factory/styles, own output.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto');
const root='[workspace]';
const repo=path.join(root,'scratch/whalee-plugin-cards'),current=path.join(repo,'build/parity-plugin-cards-final1');
const source=path.join(current,'published-plugin-cards-rs3dr9vc/source'),dist=path.join(source,'dist'),out=__dirname;
const {chromium}=require(path.join(root,'dsh-flutter/.local/parity-web/node_modules/playwright-core'));
const base=JSON.parse(fs.readFileSync(path.join(current,'flutter-plan.json'))).entries.find(e=>e.key==='components.plugin-card.default-idle-phone-dpr1-en.light');
const fonts=JSON.parse(fs.readFileSync(path.join(repo,'tool/parity-fonts/manifest.json'))),files=new Map(),inputHashes={};let css='';
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
for(const family of fonts.families)for(const face of family.faces){const id=String(files.size)+path.extname(face.file),p=path.join(repo,'tool/parity-fonts',face.file),bytes=fs.readFileSync(p);if(sha(bytes)!==face.sha256)throw Error('font hash mismatch');files.set(id,p);inputHashes[face.file]=sha(bytes);for(const name of family.names)css+=`@font-face{font-family:'${name}';font-weight:${face.weight};font-style:${face.style};src:url('/proof-fonts/${id}');font-display:block}`;}
for(const p of ['host/plugin-manager.js','provenance.json','source-trace.json'])inputHashes[p]=sha(fs.readFileSync(path.join(source,p)));
if(inputHashes['host/plugin-manager.js']!=='aef3cde87abbf361ddd33965891403d0580ebcf59ccfe388a6ad69dd56229707')throw Error('published Manager identity changed');
const server=http.createServer((req,res)=>{try{const n=new URL(req.url,'[local-runtime-url]').pathname;if(n==='/proof-fonts.css'){res.setHeader('Content-Type','text/css');return res.end(css)}if(n.startsWith('/proof-fonts/'))return res.end(fs.readFileSync(files.get(n.slice(13))));if(n==='/favicon.ico'){res.writeHead(204);return res.end()}const p=path.resolve(dist,'.'+(n==='/'?'/index.html':n));if(!p.startsWith(dist+'/'))throw Error('escape');res.setHeader('Content-Type',{'.html':'text/html','.js':'text/javascript','.css':'text/css'}[path.extname(p)]||'application/octet-stream');res.end(fs.readFileSync(p));}catch{res.writeHead(404);res.end()}});
(async()=>{let browser;const rows=[],errors=[],external=[];try{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='[local-runtime-url]'+server.address().port;
 browser=await chromium.launch({args:['--disable-lcd-text','--font-render-hinting=none','--force-device-scale-factor=1']});
 for(const [id,text] of [['spaces','   '],['tab','\t'],['newlines','\n\r\n'],['mixed',' \t\r\n\f '],['empty',''],['nbsp','\u00a0'],['visible-control',' \tA\n ']]){
  const page=await browser.newPage({viewport:{width:390,height:900},deviceScaleFactor:1});page.on('pageerror',e=>errors.push(String(e)));await page.route('**/*',route=>{if(route.request().url().startsWith(origin+'/'))return route.continue();external.push(route.request().url());return route.abort()});
  const entry=structuredClone(base);entry.variant.props.scenario.package.meta.description={en:text,zh:text};await page.addInitScript(e=>window.__pluginCardEntry=e,entry);await page.goto(origin,{waitUntil:'networkidle'});await page.evaluate(()=>document.fonts.ready);
  const actual=await page.evaluate(()=>{const css=window.__CardCss,card=document.querySelector('[data-plugin-package]'),desc=card.querySelector('.'+css.cardDesc),title=card.querySelector('.'+css.cardOpen),rect=node=>{if(!node)return null;const r=node.getBoundingClientRect();return[r.x,r.y,r.width,r.height]};return{card:rect(card),title:rect(title),description:rect(desc),rawDescription:desc?.textContent??null,whiteSpace:desc?getComputedStyle(desc).whiteSpace:null,descriptionScrollHeight:desc?.scrollHeight??null}});
  rows.push({id,text,actual});await page.close();
 }
 if(errors.length||external.length)throw Error(JSON.stringify({errors,external}));const version=browser.version();await browser.close();const disconnected=!browser.isConnected();browser=null;
 fs.writeFileSync(path.join(out,'source.json'),JSON.stringify({schema:'plugin-card-clamp-whitespace-source/1',publishedSourceAndStylesUnchanged:true,inputHashes,chromium:version,rows,errors,externalRequests:external,browserDisconnected:disconnected},null,2)+'\n');console.log(JSON.stringify(rows));
}finally{if(browser)await browser.close();await new Promise(r=>server.close(r))}})().catch(e=>{console.error(e);process.exitCode=1});
