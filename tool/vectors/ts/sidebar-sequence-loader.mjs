// Narrow the upstream barrel to the exact production runtime symbol the
// persistence module imports; avoid importing unrelated React/CSS components.
import path from 'node:path'
import {pathToFileURL} from 'node:url'
export async function resolve(specifier,context,nextResolve) {
 if(specifier==='@deepseek-ai/dsh-client-ui-dockkit')return {url:pathToFileURL(path.join(process.env.DSH_SRC,'packages/client/ui-dockkit/src/engine/sequence.ts')).href,shortCircuit:true}
 return nextResolve(specifier,context)
}
