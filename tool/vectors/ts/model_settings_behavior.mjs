import fs from 'node:fs'
import {register} from 'node:module'
import {loadDsh} from './settings_loader.mjs'
register(new URL('./ignore-css-loader.mjs',import.meta.url),import.meta.url)
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh({extraNodeDirs:[process.env.PARITY_WEB_DEPS,process.env.PARITY_VT_DEPS].filter(Boolean)})
const keys=await load('packages/client/ui-settings-models/src/client/apiKey.ts')
const store=await load('packages/client/ui-settings-models/src/client/store.ts')
const models=await load('packages/client/ui-settings-models/src/client/DeepSeekModelsEditor.tsx')
const reasoning=await load('packages/client/ui-settings-models/src/client/ModelReasoningEfforts.tsx')
const editor=await load('packages/client/ui-settings-models/src/client/ProviderEditor.tsx')
process.stdout.write(JSON.stringify({
 keys:input.keys.map(v=>keys.apiKeyFailure(v)??null),
 refs:input.refs.map(store.deriveKeyRef),
 capacities:input.capacities.map(v=>{const n=models.parseCapacity(v);return n===undefined?null:Number.isNaN(n)?'NaN':n}),
 formatted:input.formatted.map(models.formatCapacity),
 models:input.models.map(v=>models.validateDeepSeekModels(v)??null),
 reasoning:input.models.map(v=>reasoning.validateReasoningEfforts(v)??null),
 ops:input.ops.map(v=>editor.pathOps(v.base,v.before,v.after)),
 joins:input.joins.map(v=>store.joinProviderDirectory(v.live,v.directory)),
}))
