// Builds the React render host (index.html + host/*.tsx + tool/parity-ext/host/*.tsx) into a static
// directory with Vite. The host imports dsh's real React components straight from the pinned dsh
// checkout; nothing from dsh is copied or edited.
//
//   node build-host.mjs --dsh <dsh checkout> --out <dist dir> [--deps <dir containing node_modules>]
//
// react, react-dom and clsx are aliased to the harness's own install so the dsh sources (which have
// no node_modules next to them) and the ext host files resolve one copy of each. The same goes for the
// other npm packages the mounted dsh sources import (see `harnessPackages`), and dsh's own workspace
// packages (`@deepseek-ai/dsh-*`, normally resolved through pnpm links to a built `lib/`) resolve to their
// TypeScript sources in the checkout.
import { build } from 'vite'
import path from 'node:path'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1]])
  return acc
}, []))
const dsh = path.resolve(args.dsh ?? process.env.DSH_SRC ?? '')
const out = path.resolve(args.out ?? '')
const deps = path.resolve(args.deps ?? path.join(here, 'node_modules', '..'))
if (!args.out || !fs.existsSync(path.join(dsh, 'packages/client/ui-primitives/src'))) {
  console.error('usage: build-host.mjs --dsh <dsh checkout> --out <dir> [--deps <dir>]')
  process.exit(2)
}
const modules = path.join(deps, 'node_modules')
const pkg = (name, sub = '') => path.join(modules, name, sub)
const client = path.join(dsh, 'packages/client')

// dsh workspace packages the mounted surfaces import by name, mapped to the source entry the checkout holds.
// The primitives barrel is the one exception: it maps to a narrower barrel over the same real modules
// (host/mocks/primitives.ts says why).
const workspace = {
  '@deepseek-ai/dsh-client-ui-primitives': path.join(here, 'host/mocks/primitives.ts'),
  '@deepseek-ai/dsh-client-store': path.join(here, 'host/mocks/client-store.ts'),
  '@deepseek-ai/dsh-util-workspace-path': path.join(dsh, 'packages/util/workspace-path/src/index.ts'),
  '@deepseek-ai/dsh-util-code-language': path.join(dsh, 'packages/util/code-language/src/index.ts'),
  '@deepseek-ai/dsh-util-values': path.join(dsh, 'packages/util/values/src/index.ts'),
  '@deepseek-ai/dsh-spill-policy/notice': path.join(dsh, 'packages/spill/spill-policy/src/notice.ts'),
}

// npm packages the dsh sources import that live in the harness install (package.json), not next to dsh:
// any bare import of a dsh file whose package is installed under `modules` resolves there.
const packageOf = (source) => source.split('/', source.startsWith('@') ? 2 : 1).join('/')
const harnessPackages = { test: (source) => !source.startsWith('.') && !source.startsWith('/') && fs.existsSync(path.join(modules, packageOf(source))) }
const dshReal = fs.realpathSync(dsh) + path.sep
const harnessResolver = {
  name: 'parity-harness-packages',
  enforce: 'pre',
  async resolveId(source, importer, options) {
    if (!importer || importer.startsWith('\0') || !harnessPackages.test(source)) return null
    const file = importer.split('?')[0]
    if (!fs.existsSync(file) || !fs.realpathSync(file).startsWith(dshReal)) return null
    return this.resolve(source, path.join(modules, '.parity-importer.js'), { ...options, skipSelf: true })
  },
}

await build({
  root: here,
  base: './',
  configFile: false,
  logLevel: 'warn',
  define: { 'process.env.NODE_ENV': '"production"' },
  plugins: [harnessResolver],
  resolve: {
    alias: [
      { find: '@dsh', replacement: client },
      ...Object.entries(workspace).map(([name, file]) => ({ find: new RegExp(`^${name}$`), replacement: file })),
      { find: /^react\/jsx-runtime$/, replacement: pkg('react', 'jsx-runtime.js') },
      { find: /^react-dom\/client$/, replacement: pkg('react-dom', 'client.js') },
      { find: /^react-dom$/, replacement: pkg('react-dom', 'index.js') },
      { find: /^react$/, replacement: pkg('react', 'index.js') },
      { find: /^clsx$/, replacement: pkg('clsx', 'dist/clsx.mjs') },
    ],
  },
  oxc: { jsx: { runtime: 'automatic' } },
  server: { fs: { strict: false } },
  build: {
    outDir: out,
    emptyOutDir: true,
    minify: false,
    sourcemap: false,
    cssCodeSplit: false,
    target: 'es2022',
    rollupOptions: { input: path.join(here, 'index.html') },
  },
})
console.log(`host built: ${out}`)
