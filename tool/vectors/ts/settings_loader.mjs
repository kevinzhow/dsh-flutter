// Module loading shared by the settings vector runners (see run_settings_vector.mjs):
// dsh's own tsconfig `paths` via tsx map `@deepseek-ai/*` imports to dsh source, and
// resolve-externals.mjs finds the few third-party packages (zustand, immer) in the
// vector-node install. Same approach as run_vector.mjs.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { register as registerHooks } from 'node:module'

const here = path.dirname(fileURLToPath(import.meta.url))
export const repoRoot = path.resolve(here, '..', '..', '..')

/** Print a diagnostic and exit; status 2 means a prerequisite is missing (the driver reports "tool unavailable"). */
export function die(message, code = 1) {
  process.stderr.write(`run_settings_vector: ${message}\n`)
  process.exit(code)
}

/**
 * Register tsx and the externals hook, and return a loader for dsh source files.
 * @returns `{ load(relativeSpecifier) }`, importing a file of the dsh checkout.
 */
export async function loadDsh({ extraNodeDirs = [] } = {}) {
  const dshSrc = path.resolve(process.env.DSH_SRC ?? path.join(repoRoot, '.local', 'dsh-src'))
  const nodeDir = path.resolve(process.env.DSH_VECTOR_NODE_DIR ?? path.join(repoRoot, '.local', 'vector-node'))
  if (!fs.existsSync(path.join(dshSrc, 'packages/client/ui-settings/src/client/schema.ts'))) {
    die(`dsh source not found at ${dshSrc} (set DSH_SRC)`, 2)
  }
  const tsxApi = path.join(nodeDir, 'node_modules/tsx/dist/esm/api/index.mjs')
  if (!fs.existsSync(tsxApi)) die(`tsx not installed under ${nodeDir} (set DSH_VECTOR_NODE_DIR)`, 2)
  const { register: registerTsx } = await import(pathToFileURL(tsxApi).href)
  registerTsx({ tsconfig: path.join(dshSrc, 'tsconfig.base.json') })
  registerHooks(pathToFileURL(path.join(here, 'resolve-externals.mjs')).href, {
    parentURL: import.meta.url,
    data: { nodeDir, extraNodeDirs },
  })
  return { load: specifier => import(pathToFileURL(path.join(dshSrc, specifier)).href) }
}

/** Wait until the model's promise chains and timers are quiet (the settle loop of run_vector.mjs). */
export async function settle() {
  for (let round = 0; round < 12; round++) await new Promise(resolve => setImmediate(resolve))
  await new Promise(resolve => setTimeout(resolve, 2))
  for (let round = 0; round < 12; round++) await new Promise(resolve => setImmediate(resolve))
}
