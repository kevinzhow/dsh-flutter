// Exercise the pinned upstream function, not a copied policy.
import {loadDsh} from './settings_loader.mjs'
const {load}=await loadDsh()
const {resolveSubmitMode}=await load('packages/client/ui-conversation/src/client/input/submission-policy.ts')
const results=[]
for (const preferred of ['queue','steer']) for (const running of [false,true])
  for (const gesture of ['enter','accelerated']) for (const available of [false,true])
    results.push({preferred,running,gesture,available,expected:resolveSubmitMode(preferred,running,gesture,available)})
process.stdout.write(JSON.stringify(results))
