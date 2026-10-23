// Module resolution hook: bare specifiers that cannot be resolved from the dsh
// checkout (it has no node_modules here) are retried from the vector-node
// directory, which holds the few third-party packages dsh's client model needs.

import path from 'node:path'
import { pathToFileURL } from 'node:url'

let anchor

export function initialize(data) {
  anchor = pathToFileURL(path.join(data.nodeDir, 'noop.mjs')).href
}

export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context)
  } catch (error) {
    const bare = !specifier.startsWith('.') && !specifier.startsWith('/') && !specifier.startsWith('file:') && !specifier.startsWith('node:')
    if (!bare || error?.code !== 'ERR_MODULE_NOT_FOUND') throw error
    return nextResolve(specifier, { ...context, parentURL: anchor })
  }
}
