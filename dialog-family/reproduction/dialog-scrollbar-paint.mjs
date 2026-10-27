// Read-only rendering probe of the real preset guide. The two launch modes
// isolate Playwright's implicit scrollbar-hiding flag without changing the app.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(process.env.PARITY_WEB_DEPS+'/package.json');
const {chromium}=require('playwright-core');
const {PNG}=require('pngjs');
const plan=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const out=path.resolve(process.argv[3]);
fs.mkdirSync(out,{recursive:true});
const fontsDir=path.dirname(plan.fontsManifest);
const fonts=JSON.parse(fs.readFileSync(plan.fontsManifest,'utf8'));
const faces=fonts.families.flatMap(f=>f.faces.flatMap(face=>f.names.map(name=>({name,...face}))));
const fontCss=faces.map(f=>`@font-face{font-family:'${f.name}';font-weight:${f.weight};font-style:${f.style};src:url('/fonts/${path.basename(f.file)}');font-display:block}`).join('\n');
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.ttf':'font/ttf','.otf':'font/otf'};
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/parity-fonts.css'){res.writeHead(200,{'content-type':'text/css'});res.end(fontCss);return;}
 const face=url.pathname.startsWith('/fonts/')?faces.find(f=>path.basename(f.file)===path.basename(url.pathname)):null;
 const file=face?path.join(fontsDir,face.file):path.resolve(plan.hostDist,url.pathname==='/'?'index.html':url.pathname.slice(1));
 if((!face&&!file.startsWith(path.resolve(plan.hostDist)+path.sep))||!fs.existsSync(file)){res.writeHead(404);res.end();return;}
 res.writeHead(200,{'content-type':mime[path.extname(file)]??'application/octet-stream'});fs.createReadStream(file).pipe(res);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin=`http://127.0.0.1:${server.address().port}`;
const rows=[];
async function settle(page){await page.evaluate(async()=>{await document.fonts.ready;await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);});}
try {
 for(const device of ['desktop','phone']){
  const entry=plan.entries.find(e=>e.key===`components.dialog-family.${device==='phone'?'reader':'panel-scrolled'}-${device}-en-usage.dark`);
  const c=entry.case,density=c.viewport.density;
  for(const mode of ['parity-default','diagnostic-visible']){
   const browser=await chromium.launch({args:[...(plan.chromiumArgs??[]),...(density===1?[]:[`--force-device-scale-factor=${density}`])],...(mode==='diagnostic-visible'?{ignoreDefaultArgs:['--hide-scrollbars']}:{})});
   try {
    const session=await browser.newBrowserCDPSession();
    const command=await session.send('Browser.getBrowserCommandLine');
    const context=await browser.newContext({viewport:{width:c.viewport.width,height:c.viewport.height},deviceScaleFactor:density,colorScheme:c.theme,locale:c.locale,reducedMotion:'reduce'});
    const page=await context.newPage();
    await page.addInitScript(ctx=>{window.__PARITY__=ctx;},{case:c,variant:entry.variant});
    await page.goto(origin);
    await page.waitForSelector('body[data-parity-ready="true"]');
    await page.evaluate(()=>window.__parityReady);
    await page.locator(`[data-parity-id="${entry.variant.interactions[0].target}"]`).click();
    await settle(page);
    const panel=page.locator('[data-parity-id="preset-guide-panel-usage"]');
    const measurements=[];
    async function snapshot(state){
     const dom=await panel.evaluate(el=>{
      const r=el.getBoundingClientRect(),s=getComputedStyle(el),bar=getComputedStyle(el,'::-webkit-scrollbar'),thumb=getComputedStyle(el,'::-webkit-scrollbar-thumb');
      return {rect:{x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom},offsetWidth:el.offsetWidth,clientWidth:el.clientWidth,clientHeight:el.clientHeight,scrollHeight:el.scrollHeight,scrollTop:el.scrollTop,dpr:devicePixelRatio,overflowY:s.overflowY,gutter:s.scrollbarGutter,scrollbarWidth:s.scrollbarWidth,webkitWidth:bar.width,thumbColor:thumb.backgroundColor,thumbOpacity:thumb.opacity,thumbDisplay:thumb.display,paddingRight:s.paddingRight};
     });
     const full=PNG.sync.read(await page.screenshot({animations:'disabled',caret:'hide',scale:'device'}));
     // Stable scrollbar gutter includes floor(5*dpr) device columns. The
     // outward rounding of the panel rect adds a possible edge column.
     const x1=Math.round(dom.rect.right*dom.dpr),width=Math.floor(parseFloat(dom.webkitWidth)*dom.dpr),y0=Math.ceil(dom.rect.y*dom.dpr),y1=Math.floor(dom.rect.bottom*dom.dpr);
     const strip=new PNG({width,height:y1-y0});
     const colors=new Map();
     for(let y=0;y<strip.height;y++)for(let x=0;x<width;x++){
      const src=((y+y0)*full.width+(x+x1-width))*4,dst=(y*width+x)*4;
      for(let ch=0;ch<4;ch++)strip.data[dst+ch]=full.data[src+ch];
      const rgb=[...strip.data.subarray(dst,dst+4)].join(',');colors.set(rgb,(colors.get(rgb)??0)+1);
     }
     const name=`${device}-${mode}-${state}`;
     fs.writeFileSync(path.join(out,name+'.gutter.png'),PNG.sync.write(strip));
     fs.writeFileSync(path.join(out,name+'.png'),PNG.sync.write(full));
     const colorCounts=[...colors].sort((a,b)=>b[1]-a[1]);
     const thumbRgb=dom.thumbColor.match(/[\d.]+/g).slice(0,3).map(Number).join(',')+',255';
     measurements.push({state,dom,gutterPixelRect:{x:x1-width,y:y0,width,height:y1-y0},uniqueColors:colors.size,topColors:colorCounts.slice(0,8),exactCssThumbPixels:colors.get(thumbRgb)??0,images:{full:name+'.png',gutter:name+'.gutter.png'}});
    }
    await page.mouse.move(1,1);await settle(page);await snapshot('idle');
    let rect=await panel.boundingBox();
    await page.mouse.move(rect.x+rect.width/2,rect.y+rect.height/2);await settle(page);await snapshot('hover-panel');
    await page.mouse.move(rect.x+rect.width-2,rect.y+20);await settle(page);await snapshot('hover-gutter');
    await page.mouse.move(rect.x+rect.width/2,rect.y+rect.height/2);await page.mouse.wheel(0,180);await settle(page);await snapshot('wheel');
    await page.mouse.move(1,1);await page.waitForTimeout(1500);await settle(page);await snapshot('after-wheel-idle');
    if(!measurements.some(m=>m.dom.scrollTop>0))throw new Error(`real wheel did not scroll ${device}/${mode}`);
    rows.push({caseKey:entry.key,mode,browser:browser.version(),scrollbarArgs:command.arguments.filter(arg=>/scroll|headless|overlay/.test(arg)),measurements});
    await context.close();
   }finally{await browser.close();}
  }
 }
 fs.writeFileSync(path.join(out,'measurements.json'),JSON.stringify({plan:process.argv[2],rows},null,2)+'\n');
 process.stdout.write(JSON.stringify(rows.map(({caseKey,mode,scrollbarArgs,measurements})=>({caseKey,mode,scrollbarArgs,states:measurements.map(({state,dom,uniqueColors,topColors,exactCssThumbPixels})=>({state,scrollTop:dom.scrollTop,extent:dom.scrollHeight-dom.clientHeight,uniqueColors,topColors,exactCssThumbPixels}))})),null,2)+'\n');
}finally{await new Promise(resolve=>server.close(resolve));}
