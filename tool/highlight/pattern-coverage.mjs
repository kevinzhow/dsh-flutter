#!/usr/bin/env node
// For every converted grammar, counts the distinct regex sources (match /
// begin / end / while) that shiki's JavaScript regex engine (oniguruma-to-es
// as dsh configures it) accepts and rejects. The Dart side reports the same
// numbers through HighlightEngine.patternStats; the two should agree.
//
//   node tool/highlight/pattern-coverage.mjs --shiki <node_modules dir>
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name)
  return i >= 0 ? process.argv[i + 1] : fallback
}
const here = path.dirname(new URL(import.meta.url).pathname)
const nm = arg('shiki')
if (!nm) {
  console.error('usage: pattern-coverage.mjs --shiki <node_modules dir>')
  process.exit(2)
}
const dir = arg('grammars', path.resolve(here, '../../packages/dsh_highlight/assets/grammars'))
const { defaultJavaScriptRegexConstructor } = await import(
  pathToFileURL(path.join(nm, '@shikijs/engine-javascript/dist/index.mjs')).href)

function sources(node, out) {
  if (Array.isArray(node)) node.forEach(n => sources(n, out))
  else if (node && typeof node === 'object') {
    for (const k of ['match', 'begin', 'end', 'while']) {
      if (typeof node[k] === 'string' && node[k]) out.add(node[k])
    }
    Object.values(node).forEach(v => sources(v, out))
  }
}
let unique = 0, rejected = 0
for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.json') && f !== 'index.json').sort()) {
  const g = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'))
  const set = new Set()
  sources([g.patterns, g.repository, g.injections], set)
  let bad = 0
  for (const s of set) {
    try { defaultJavaScriptRegexConstructor(s, { lazyCompileLength: Infinity }) } catch { bad++ }
  }
  unique += set.size
  rejected += bad
  console.log(`${f.replace('.json', '').padEnd(12)} unique=${set.size} shiki-rejected=${bad}`)
}
console.log(`TOTAL unique=${unique} shiki-rejected=${rejected}`)
