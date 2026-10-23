// Oracle for the Dart diff card: runs dsh's own `structuredPatch` (the `diff` package, with the card's options and
// fallback, copied from ui-primitives DiffBlock.tsx `localHunks`/`buildRows`/`diffTotals`) over generated edit cases and
// prints {cases:[{old,new,rows:[[kind,text]],added,removed}]} as JSON. Cases are deterministic (seeded generator).
// Usage: node diff_cases.mjs   with NODE_PATH pointing at an install that has `diff` (the parity web deps).
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const { structuredPatch } = require('diff')

const MAX = 256
function contentLines(text) {
  if (text === '') return []
  const body = text.endsWith('\n') ? text.slice(0, -1) : text
  return body.split('\n')
}
function localHunks(oldText, newText) {
  const oldLines = contentLines(oldText ?? '')
  const newLines = contentLines(newText)
  const normalize = lines => lines.map(line => `${line}\n`).join('')
  return structuredPatch('', '', normalize(oldLines), normalize(newLines), undefined, undefined, { context: 3, maxEditLength: MAX })?.hunks
    ?? [{ lines: [...oldLines.map(line => `-${line}`), ...newLines.map(line => `+${line}`)] }]
}
function rows(oldText, newText) {
  const out = []
  localHunks(oldText, newText).forEach((hunk, index) => {
    if (index > 0) out.push(['gap', '⋯'])
    for (const line of hunk.lines) out.push([line.startsWith('-') ? 'del' : line.startsWith('+') ? 'add' : 'context', line.slice(1)])
  })
  return out
}
let seed = 20261024
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff }
const pick = n => Math.floor(rnd() * n)
const words = ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta', 'iota', 'kappa']
function base(n) { return Array.from({ length: n }, (_, i) => `${words[pick(words.length)]} ${i % 7}`) }
const cases = []
function add(a, b) { cases.push([a, b]) }
add(null, 'one\ntwo\nthree\n')
add('', 'x\n')
add('same\nlines\n', 'same\nlines\n')
add('a\nb\nc\n', 'a\nB\nc\n')
add('a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n', 'a\nb\nc\nd\ne\nF\ng\nh\ni\nj\n')
add('a\nb\nc\n', 'a\nb\nc')
add('line\n\nline\n', 'line\n\n\nline\n')
add('x\n', '')
for (let i = 0; i < 40; i++) {
  const lines = base(4 + pick(30))
  const next = [...lines]
  for (let k = 0; k < 1 + pick(4); k++) {
    const at = pick(next.length + 1)
    const op = pick(3)
    if (op === 0) next.splice(at, 0, `new ${pick(100)}`)
    else if (op === 1 && next.length > 1) next.splice(at % next.length, 1)
    else next[at % next.length] = `changed ${pick(100)}`
  }
  add(lines.join('\n') + (pick(4) === 0 ? '' : '\n'), next.join('\n') + (pick(4) === 0 ? '' : '\n'))
}
add(Array.from({ length: 300 }, (_, i) => `old ${i}`).join('\n'), Array.from({ length: 300 }, (_, i) => `new ${i}`).join('\n'))
const out = cases.map(([a, b]) => {
  const r = rows(a, b)
  return { old: a, new: b, rows: r, added: r.filter(x => x[0] === 'add').length, removed: r.filter(x => x[0] === 'del').length }
})
process.stdout.write(JSON.stringify({ schema: 'dsh-diff-cases/1', source: 'diff (jsdiff) structuredPatch, dsh DiffBlock options', cases: out }, null, 1) + '\n')
