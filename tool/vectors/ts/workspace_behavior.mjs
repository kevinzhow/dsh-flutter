// Execute the pinned functions, including private pure helpers whose module
// also mounts UI. Type erasure adds no behavior; dependencies stay upstream.
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import {stripTypeScriptTypes} from 'node:module'
import {loadDsh} from './settings_loader.mjs'
const fixture=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh()
const {pinCurrentBlank}=await load('packages/client/ui-workspace/src/client/tree.ts')
function pure(file,name,deps={}) {
 const source=fs.readFileSync(path.join(process.env.DSH_SRC,file),'utf8')
 const start=source.indexOf(`function ${name}(`)
 const end=source.indexOf('\n}',start)+2
 if(start<0||end<start)throw Error(`Pinned helper ${name} unavailable`)
 return vm.runInNewContext('('+stripTypeScriptTypes(source.slice(start,end),{mode:'strip'})+')',deps)
}
const title=pure('packages/api/session-controller/src/client/sessions/service.ts','increasedForkTitle')
const drag=pure('packages/client/ui-workspace/src/client/rows/WorkspaceBrowser.tsx','sessionDragOrder',{pinCurrentBlank})
const ancestry=pure('packages/client/ui-conversation/src/client/skeleton/ConversationSession.tsx','deriveAncestry')
process.stdout.write(JSON.stringify({
 titles:fixture.titles.map(input=>({input,expected:title(input)})),
 drag:fixture.drag.map(c=>({...c,expected:drag(c.order,c.rows,c.drag,c.over)??null})),
 ancestry:fixture.ancestry.map(c=>({...c,expected:ancestry(c.list,c.id)})),
}))
