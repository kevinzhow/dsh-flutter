// The pinned TS functions are the oracle; only input enumeration is glue.
import fs from 'node:fs'
import {register} from 'node:module'
import {loadDsh} from './settings_loader.mjs'
const fixture=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh({extraNodeDirs:[process.env.PARITY_WEB_DEPS]})
register(new URL('./ignore-css-loader.mjs',import.meta.url),import.meta.url)
const {parsePlanAddress,planAddress}=await load('packages/client/ui-plan/src/client/plan.ts')
const {planReviewOf}=await load('packages/client/ui-user-questions/src/client/contract/slots.ts')
const {extractMarkdownPlainText}=await load('packages/client/ui-primitives/src/markdown/plain-text.ts')
const out={addresses:[],reviews:[],markdown:[]}
for (const address of fixture.addresses) {
  const parsed=parsePlanAddress(address)
  out.addresses.push({address,parsed:parsed??null,encoded:parsed===undefined?null:planAddress(parsed)})
}
for (const questions of fixture.reviews) out.reviews.push({questions,expected:planReviewOf(questions)??null})
for (const text of fixture.markdown) out.markdown.push({text,expected:Object.fromEntries(
  ['all','first-line','first-paragraph'].map(mode=>[mode,extractMarkdownPlainText(text,{mode})]))})
process.stdout.write(JSON.stringify(out))
