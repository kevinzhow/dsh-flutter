#!/usr/bin/env node
// Converts shiki's TextMate grammar registrations (@shikijs/langs) into the
// asset files packages/dsh_highlight/assets/grammars/<name>.json.
//
//   node tool/highlight/convert.mjs --langs <@shikijs/langs/dist dir> [--out <dir>] [--list <languages.json>]
//
// Every module in @shikijs/langs exports an array of registrations (the
// language's embedded dependencies first, the language itself last). Each
// registration becomes ONE file named after its `name`, so a dependency shared
// by several languages (css, javascript, c, ...) is stored once; the engine
// follows `embeddedLangs` by name. Only the keys the engine reads are kept and
// the output is minified JSON. Also writes an index.json listing what was
// converted, which languages were requested, and the byte size of each file.
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name)
  return i >= 0 ? process.argv[i + 1] : fallback
}

const here = path.dirname(new URL(import.meta.url).pathname)
const langsDir = arg('langs')
if (!langsDir) {
  console.error('usage: convert.mjs --langs <@shikijs/langs/dist> [--out dir] [--list file]')
  process.exit(2)
}
const outDir = arg('out', path.resolve(here, '../../packages/dsh_highlight/assets/grammars'))
const listFile = arg('list', path.join(here, 'languages.json'))
const config = JSON.parse(fs.readFileSync(listFile, 'utf8'))
const requested = config.languages
// Grammars whose upstream licence is not on the allowed list (MIT / Apache / BSD / OFL):
// never converted, and dropped from other grammars' embeddedLangs. Includes of
// their scope names then resolve to nothing, as for a grammar that is not loaded.
const withheld = new Set(Object.keys(config.withheld ?? {}))

// Keys of a registration the engine reads. Everything else (displayName,
// aliases, fileTypes, firstLineMatch, folding markers, ...) is metadata.
const KEEP = ['name', 'scopeName', 'patterns', 'repository', 'injections', 'injectionSelector', 'injectTo',
  'embeddedLangs', 'embeddedLangsLazy']

// Drop authors' free-text `comment` strings inside rules (never a repository
// entry named "comment", which is an object).
function strip(node) {
  if (Array.isArray(node)) return node.map(strip)
  if (node && typeof node === 'object') {
    const out = {}
    for (const [k, v] of Object.entries(node)) {
      if (k === 'comment' && typeof v === 'string') continue
      if (k === '$vscodeTextmateLocation') continue
      out[k] = strip(v)
    }
    return out
  }
  return node
}

const registrations = new Map()
for (const id of requested) {
  const mod = await import(pathToFileURL(path.join(langsDir, id + '.mjs')).href)
  for (const reg of mod.default) {
    if (withheld.has(reg.name)) continue
    if (!registrations.has(reg.name)) registrations.set(reg.name, reg)
  }
  if (!registrations.has(id)) throw new Error('module ' + id + ' does not register ' + id)
}

fs.mkdirSync(outDir, { recursive: true })
for (const f of fs.readdirSync(outDir)) {
  if (f.endsWith('.json')) fs.rmSync(path.join(outDir, f))
}
const index = { requested, grammars: {} }
let total = 0
for (const [name, reg] of [...registrations].sort(([a], [b]) => a.localeCompare(b))) {
  const slim = {}
  for (const k of KEEP) if (reg[k] !== undefined) slim[k] = strip(reg[k])
  for (const k of ['embeddedLangs', 'embeddedLangsLazy']) {
    if (slim[k]) slim[k] = slim[k].filter(n => !withheld.has(n))
  }
  const text = JSON.stringify(slim)
  fs.writeFileSync(path.join(outDir, name + '.json'), text)
  const bytes = Buffer.byteLength(text)
  total += bytes
  index.grammars[name] = { scopeName: reg.scopeName, bytes, embeddedLangs: slim.embeddedLangs ?? [] }
}
index.totalBytes = total
fs.writeFileSync(path.join(outDir, 'index.json'), JSON.stringify(index, null, 1) + '\n')
console.log(`converted ${registrations.size} grammars, ${total} bytes -> ${outDir}`)
