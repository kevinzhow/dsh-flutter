import {createRequire} from 'node:module';
import fs from 'node:fs';
const require=createRequire(process.cwd()+'/tool/parity-web/capture.mjs');
const {chromium}=require('playwright-core');
const proofs=[];
for (const mode of ['native','emulated']) {
 const browser=await chromium.launch({args:mode==='native'?['--force-device-scale-factor=2.625']:[]});
 try {
  for (const [width,height] of [[390,61],[391,62],[390,60]]) {
  const context=await browser.newContext({viewport:{width,height},deviceScaleFactor:2.625});
  const page=await context.newPage();await page.setContent('<style>body{margin:0;background:white}</style>');
  const png=await page.screenshot({path:'.local/viewport-chromium-'+mode+'.png',scale:'device'});
  proofs.push({mode,viewport:{width,height,density:2.625},browser:browser.version(),width:png.readUInt32BE(16),height:png.readUInt32BE(20)});
  await context.close();
  }
 } finally {await browser.close()}
}
fs.writeFileSync('.local/viewport-chromium-proof.json',JSON.stringify(proofs,null,2)+'\n');
console.log(proofs);
