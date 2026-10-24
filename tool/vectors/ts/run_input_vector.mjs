// Replays a `dsh-input-vector/1` fixture through dsh's REAL TypeScript input code and prints the
// expectations as JSON:
//
//   node run_input_vector.mjs FIXTURE.json [--out PATH]
//
// Every case has an `op` naming the dsh function it exercises:
//   detect    detectTrigger        (ui-input-trigger/core/detect.ts)
//   atToken   activeAtToken        (file-reference/grammar.ts)
//   mention   formatFileMention    (file-reference/grammar.ts)
//   rank      rankByName           (ui-primitives/rank-by-name.ts)
//   time      relativeTime         (ui-primitives/relative-time.ts)
//   menu      seedGroups + menuReduce + exactMatch (ui-input-trigger/core/menu.ts) over a scripted event list
//
// Environment: DSH_SRC, DSH_VECTOR_NODE_DIR (see gen_input_expected.py). Only the JSON encoders here are glue.

import fs from 'node:fs'
import { die, loadDsh } from './settings_loader.mjs'

const args = process.argv.slice(2)
let fixturePath
let outPath
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out') outPath = args[++i]
  else if (fixturePath === undefined) fixturePath = args[i]
  else die(`unexpected argument ${args[i]}`)
}
if (fixturePath === undefined) die('usage: run_input_vector.mjs FIXTURE.json [--out PATH]')

const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'))
if (fixture.format !== 'dsh-input-vector/1') die(`unsupported fixture format ${String(fixture.format)}`)

const dsh = await loadDsh()
const { detectTrigger } = await dsh.load('packages/client/ui-input-trigger/src/core/detect.ts')
const { menuReduce, seedGroups, exactMatch, MENU_CLOSED } = await dsh.load('packages/client/ui-input-trigger/src/core/menu.ts')
const { activeAtToken, formatFileMention } = await dsh.load('packages/context/file-reference/src/grammar.ts')
const { rankByName } = await dsh.load('packages/client/ui-primitives/src/rank-by-name.ts')
const { relativeTime } = await dsh.load('packages/client/ui-primitives/src/relative-time.ts')

const encodeHit = hit => hit === null ? null : {
  trigger: hit.trigger, query: hit.query, quoted: hit.quoted, position: hit.position,
  start: hit.span.start, end: hit.span.end,
}

const encodeState = state => ({
  open: state.open,
  hit: state.hit === null ? null : { trigger: state.hit.trigger, query: state.hit.query, start: state.hit.span.start, end: state.hit.span.end },
  generation: state.generation,
  groups: state.groups.map(g => ({
    source: g.source, showGroupTitle: g.showGroupTitle !== false, status: g.status, items: g.items.map(i => i.name),
  })),
  highlight: state.highlight === null ? null : { source: state.highlight.source, index: state.highlight.index },
})

const hitOf = h => ({
  trigger: h.trigger, query: h.query, quoted: h.quoted ?? false, position: h.position ?? 'leading',
  span: { start: h.start, end: h.end, draftRev: h.draftRev ?? 1 },
})

function runMenu(entry) {
  let state = MENU_CLOSED
  const out = []
  for (const ev of entry.events) {
    switch (ev.type) {
      case 'seed': state = seedGroups(state, entry.sources); break
      case 'hit': state = menuReduce(state, { type: 'hit', hit: ev.hit === null ? null : hitOf(ev.hit) }); break
      case 'settled': state = menuReduce(state, {
        type: 'source-settled', generation: ev.generation, source: ev.source, items: ev.items.map(name => ({ name })),
      }); break
      case 'failed': state = menuReduce(state, { type: 'source-failed', generation: ev.generation, source: ev.source }); break
      case 'move': state = menuReduce(state, { type: 'move', dir: ev.dir }); break
      case 'hover': state = menuReduce(state, { type: 'hover', source: ev.source, index: ev.index }); break
      case 'close': state = menuReduce(state, { type: 'close' }); break
      case 'exact': break
      default: throw new Error(`unknown menu event ${String(ev.type)}`)
    }
    const encoded = encodeState(state)
    if (ev.type === 'exact') encoded.exact = exactMatch(state.groups, ev.source, ev.name)?.name ?? null
    out.push(encoded)
  }
  return out
}

const expect = fixture.cases.map((entry, index) => {
  switch (entry.op) {
    case 'detect':
      return encodeHit(detectTrigger(entry.draft, entry.caret ?? entry.draft.length, { tier: entry.tier }))
    case 'atToken': {
      const at = activeAtToken(entry.line, entry.cursor)
      return at === undefined ? null : { prefix: at.prefix, query: at.query, quoted: at.quoted }
    }
    case 'mention':
      return formatFileMention({ path: entry.path, kind: entry.kind }, entry.preserveQuote) ?? null
    case 'rank':
      return rankByName(entry.items, entry.query).map(item => item.name)
    case 'time':
      return relativeTime(entry.at, entry.now)
    case 'menu':
      return runMenu(entry)
    default:
      throw new Error(`case ${index}: unknown op ${String(entry.op)}`)
  }
})

const json = `${JSON.stringify({ expect })}\n`
if (outPath === undefined) process.stdout.write(json)
else fs.writeFileSync(outPath, json)
