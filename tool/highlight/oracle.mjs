#!/usr/bin/env node
// Tokenizes the committed sample files with real shiki and dsh's configuration
// (JavaScript regex engine, forgiving, css-variables theme with
// fontStyle: true, TOKENIZE_MAX_LINE_LENGTH 1000, no per-line time limit, boot grammars typescript /
// shellscript / json, the language under test loaded on top) and writes the
// result the Dart test compares against.
//
//   node tool/highlight/oracle.mjs --shiki <node_modules dir> [--lang python,...]
//
// samples: packages/dsh_highlight/test/fixtures/samples/<grammar id>/<file>
// output : packages/dsh_highlight/test/fixtures/oracle/<grammar id>.json
//   { "grammar": id, "shiki": version, "files": [ { "name", "lines": [ [ {text, token, fontStyle} ] ] } ] }
// token is one of the nine classes or null (foreground); fontStyle is shiki's
// bit set (1 italic, 2 bold, 4 underline).
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL, fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name)
  return i >= 0 ? process.argv[i + 1] : fallback
}
const here = path.dirname(new URL(import.meta.url).pathname)
const nm = arg('shiki')
if (!nm) {
  console.error('usage: oracle.mjs --shiki <node_modules dir> [--lang a,b]')
  process.exit(2)
}
const fixtures = path.resolve(here, '../../packages/dsh_highlight/test/fixtures')
const samplesDir = arg('samples', path.join(fixtures, 'samples'))
const outDir = arg('out', path.join(fixtures, 'oracle'))
const only = arg('lang') ? arg('lang').split(',') : null
const rejectedOut = arg('rejected-out')
const isChild = process.argv.includes('--child')

// Each language runs in its own node process: V8 refuses to compile some very
// large regexes ("Regular expression too large") once enough code has been
// generated in the process, and shiki's forgiving engine then silently drops
// those patterns. A fresh process per language is deterministic and is what a
// fresh dsh page session sees.
if (!isChild) {
  const all = fs.readdirSync(samplesDir).filter(d => fs.statSync(path.join(samplesDir, d)).isDirectory())
  const rejectedAll = {}
  for (const lang of all) {
    if (only && !only.includes(lang)) continue
    const tmpRejected = path.join(outDir, `.${lang}.rejected.json`)
    fs.mkdirSync(outDir, { recursive: true })
    const r = spawnSync(process.execPath, [fileURLToPath(import.meta.url), '--shiki', nm, '--samples', samplesDir,
      '--out', outDir, '--lang', lang, '--child', '--rejected-out', tmpRejected], { stdio: 'inherit' })
    if (r.status !== 0) process.exit(r.status ?? 1)
    Object.assign(rejectedAll, JSON.parse(fs.readFileSync(tmpRejected, 'utf8')))
    fs.rmSync(tmpRejected)
  }
  if (rejectedOut) fs.writeFileSync(rejectedOut, JSON.stringify(rejectedAll, null, 1))
  process.exit(0)
}

const imp = rel => import(pathToFileURL(path.join(nm, rel)).href)
const { createHighlighterCoreSync, createCssVariablesTheme } = await imp('shiki/dist/core.mjs')
const { createJavaScriptRegexEngine, defaultJavaScriptRegexConstructor } =
  await imp('shiki/dist/engine-javascript.mjs')
const shikiVersion = JSON.parse(fs.readFileSync(path.join(nm, 'shiki/package.json'), 'utf8')).version
const langModule = id => imp(`@shikijs/langs/dist/${id}.mjs`)

const theme = createCssVariablesTheme({ name: 'css-variables', variablePrefix: '--shiki-', fontStyle: true })
const TOKENS = {
  constant: 'constant', string: 'string', comment: 'comment', keyword: 'keyword', parameter: 'parameter',
  function: 'function', 'string-expression': 'stringExpression', punctuation: 'punctuation', link: 'link',
}
function tokenOf(color) {
  const m = /^var\(--shiki-token-([a-z-]+)\)$/.exec(color ?? '')
  return m ? (TOKENS[m[1]] ?? null) : null // foreground, '' and undefined variables -> null
}

const boot = ['typescript', 'shellscript', 'json']
const bootMods = await Promise.all(boot.map(id => langModule(id)))
const rejected = {}

const languages = fs.readdirSync(samplesDir).filter(d => fs.statSync(path.join(samplesDir, d)).isDirectory())
fs.mkdirSync(outDir, { recursive: true })
for (const lang of languages) {
  if (only && !only.includes(lang)) continue
  const failures = new Set()
  const engine = createJavaScriptRegexEngine({
    forgiving: true,
    regexConstructor: pattern => {
      try {
        return defaultJavaScriptRegexConstructor(pattern, { lazyCompileLength: Number.POSITIVE_INFINITY })
      } catch (e) {
        failures.add(pattern)
        throw e
      }
    },
  })
  const hl = createHighlighterCoreSync({ themes: [theme], langs: bootMods.map(m => m.default), engine })
  if (!boot.includes(lang)) hl.loadLanguageSync((await langModule(lang)).default)
  const dir = path.join(samplesDir, lang)
  const files = []
  for (const name of fs.readdirSync(dir).sort()) {
    const code = fs.readFileSync(path.join(dir, name), 'utf8')
    const { tokens } = // tokenizeTimeLimit 0: shiki's default 500 ms per line includes the
    // first-use regex compilation, so a loaded machine could cut a line short and
    // make the oracle non-deterministic (observed with sql's big keyword rule).
    hl.codeToTokens(code, { lang, theme: 'css-variables', tokenizeMaxLineLength: 1000, tokenizeTimeLimit: 0 })
    const last = tokens[tokens.length - 1]
    const lines = tokens.length > 1 && last.length === 0 ? tokens.slice(0, -1) : tokens
    files.push({
      name,
      lines: lines.map(line => line.map(t => ({ text: t.content, token: tokenOf(t.color), fontStyle: t.fontStyle ?? 0 }))),
    })
  }
  rejected[lang] = [...failures]
  fs.writeFileSync(path.join(outDir, lang + '.json'), JSON.stringify({ grammar: lang, shiki: shikiVersion, files }) + '\n')
  console.log(`${lang}: ${files.length} files, ${files.reduce((n, f) => n + f.lines.length, 0)} lines, ${failures.size} patterns rejected by shiki`)
}
if (rejectedOut) fs.writeFileSync(rejectedOut, JSON.stringify(rejected, null, 1))
