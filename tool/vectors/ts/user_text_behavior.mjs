// Real pinned production matcher and document evaluator. Synthetic strings are
// assembled from fragments so fixtures never contain a usable credential.
import fs from 'node:fs'
import {loadDsh} from './settings_loader.mjs'
const fixture=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh()
const {UserTextDocument}=await load('packages/client/ui-conversation/src/client/conversation/user-text-document.ts')
const {createSecretRule}=await load('packages/client/ui-secret-mask/src/client/secret-rule.ts')
const {fileReferenceRule,folderReferenceRule}=await load('packages/client/ui-reference/src/client/user-text-rules.ts')
const {sessionReferenceRule}=await load('packages/client/ui-conversation/src/client/user-text/session-reference-rule.ts')
const {trimWhitespaceRule,collapseWhitespaceRule}=await load('packages/client/ui-conversation/src/client/user-text/whitespace-rules.ts')
const expand=parts=>parts.map(p=>typeof p==='string'?p:p.repeat.repeat(p.count)).join('')
const rules=()=>[createSecretRule(),sessionReferenceRule,fileReferenceRule,folderReferenceRule,trimWhitespaceRule,collapseWhitespaceRule].sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id))
const documents=fixture.documents.map(c=>new UserTextDocument().evaluate({text:expand(c.parts),facts:c.facts??{}},rules()))
const queries=fixture.queries.map(c=>{
 const rule=createSecretRule(),text=expand(c.parts)
 return c.from.map(from=>rule.match(text,from)??null)
})
process.stdout.write(JSON.stringify({documents,queries}))
