// Builds the React render host (index.html + host/*.tsx + tool/parity-ext/host/*.tsx) into a static
// directory with Vite. The host imports dsh's real React components straight from the pinned dsh
// checkout; nothing from dsh is copied or edited.
//
//   node build-host.mjs --dsh <dsh checkout> --out <dist dir> [--deps <dir containing node_modules>]
//
// react, react-dom and clsx are aliased to the harness's own install so the dsh sources (which have
// no node_modules next to them) and the ext host files resolve one copy of each.
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

await build({
  root: here,
  base: './',
  configFile: false,
  logLevel: 'warn',
  define: { 'process.env.NODE_ENV': '"production"' },
  resolve: {
    alias: [
      { find: '@dsh', replacement: path.join(dsh, 'packages/client') },
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
