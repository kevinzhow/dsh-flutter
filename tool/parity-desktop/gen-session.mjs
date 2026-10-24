// Writes one long synthetic session into an isolated session root through
// dsh's own JSONL persistence (no model call, nothing but generic text).
//   node gen-session.mjs <DSH_PKG_DIR> <sessions-root> <session-id> <turns>
import { pathToFileURL } from 'node:url'
import { createRequire } from 'node:module'
import { isAbsolute, join, resolve } from 'node:path'

const [pkg, root, sessionId, turnsArg] = process.argv.slice(2)
const turns = Number(turnsArg ?? 320)
if (!pkg || !root || !sessionId || !process.env.FIXTURE_CWD ||
    !isAbsolute(root) || !isAbsolute(process.env.FIXTURE_CWD) ||
    !Number.isSafeInteger(turns) || turns < 1) {
  console.error('FIXTURE_CWD=<absolute ws directory> node gen-session.mjs <DSH_PKG_DIR> <absolute sessions-root> <session-id> [positive turns]')
  process.exit(1)
}
// Resolve from the installed CLI so both local (hoisted) and global npm installs work.
const require = createRequire(join(resolve(pkg), 'package.json'))
const load = name => import(pathToFileURL(require.resolve(`@deepseek-ai/${name}`)).href)
const { Context } = await load('cordis')
const { SESSION_FORMAT_VERSION } = await load('dsh-session')
const Jsonl = await load('dsh-session-persistence-jsonl')

const ctx = new Context()
await ctx.plugin(Jsonl, { root, compression: 'zstd' })
const handle = await ctx.sessionPersistence.create({
  version: SESSION_FORMAT_VERSION,
  id: sessionId,
  createdAt: Date.UTC(2026, 9, 1, 9, 0, 0),
  cwd: process.env.FIXTURE_CWD,
  isSeeded: false,
})

let seq = 0
let time = Date.UTC(2026, 9, 1, 9, 0, 0)
let idn = 0
let firstUser = -1
const nid = p => `${p}-${++idn}`
const tick = (ms = 900) => (time += ms)
const ev = (type, data, surfaceOp, extra) => {
  const e = { type, seq: seq++, time: tick(37), data, ...(surfaceOp ? { surfaceOp } : {}), ...(extra ?? {}) }
  return e
}
const text = t => [{ type: 'text', text: t }]
const src = { kind: 'model', provider: 'fixture', model: 'fixture-model' }

const topics = [
  ['How does the retry policy work for failed requests?', 'src/net/retry.ts', 'retry'],
  ['Why is the cache invalidated twice on save?', 'src/cache/store.ts', 'cache'],
  ['Can you add pagination to the list endpoint?', 'src/api/list.ts', 'list'],
  ['Explain the build pipeline stages.', 'build/pipeline.md', 'pipeline'],
  ['The date parser rejects valid input, take a look.', 'src/util/date.ts', 'date'],
  ['Summarise what the scheduler does at startup.', 'src/sched/boot.ts', 'scheduler'],
  ['Rename the config loader and update the imports.', 'src/config/load.ts', 'config'],
  ['Where are the feature flags evaluated?', 'src/flags/eval.ts', 'flags'],
]
const answers = [
  (n, f) => `Here is what happens in **${n}**.\n\n1. The request is validated first.\n2. The result is cached for a short time.\n3. Failures are reported with a stable error code.\n\nThe implementation lives in [${f}](${f}#L${12 + (n.length % 40)}); the public entry point is documented at [the guide](https://example.com/guide/${n}).`,
  (n, f) => `I traced it through \`${f}\`. The relevant part:\n\n\`\`\`ts\nexport function ${n}(input: string): number {\n  const value = Number(input)\n  if (Number.isNaN(value)) throw new Error('invalid')\n  return value\n}\n\`\`\`\n\nThe check runs before any state changes, so a failure leaves nothing half applied.`,
  (n, f) => `Short answer: yes.\n\n- The default is conservative.\n- It can be overridden per call.\n- Tests cover both paths in \`${f}\`.\n\n> Note: the override is read once at startup.`,
  (n, f) => `Done. I updated \`${f}\` and the two call sites.\n\n| step | result |\n|---|---|\n| lint | clean |\n| tests | passing |\n\nLet me know if you want the same change in the other packages.`,
]
const reasonings = [
  'The question is about a single module, so I should read it before answering. I will check the entry point and then the tests.',
  'Two readings are possible; the code path in the handler settles it. I will confirm with the file contents.',
]

for (let t = 1; t <= turns; t++) {
  const [q, file, name] = topics[t % topics.length]
  const question = `${q} (#${t})`
  const rpc = `rpc-${t}`
  const uid = nid('u')
  const out = []
  out.push(ev('turn/start', { turn: t }))
  out.push(ev('step/start', { turn: t, step: 1 }))
  if (t === 1) out.push(ev('system/message', { turn: 1, step: 1, message: { role: 'system', content: text('You are a helpful assistant.'), source: { kind: 'system-prompt' }, id: nid('s') } }, 'append'))
  if (firstUser < 0) firstUser = seq
  out.push(ev('user/message', { content: text(question), source: { kind: 'user', rpcId: rpc }, role: 'user', id: uid }, 'append'))
  const callId = `call-${t}`
  const withTool = t % 3 !== 0
  const content1 = [
    ...(t % 4 === 1 ? [{ type: 'reasoning', text: reasonings[t % 2] }] : []),
    ...(withTool ? [{ type: 'tool-call', id: callId, name: 'read', arguments: JSON.stringify({ path: file }) }] : text(answers[t % answers.length](name, file))),
  ]
  out.push(ev('assistant/message', {
    turn: t, step: 1,
    message: { role: 'assistant', content: content1, source: src, id: nid('a') },
    usage: { inputTokens: 1200, outputTokens: 80, totalTokens: 1280 },
    stream: [],
  }, 'append'))
  if (withTool) {
    out.push(ev('tool/call', { turn: t, step: 1, callId, name: 'read', arguments: JSON.stringify({ path: file }) }))
    out.push(ev('tool/result', {
      turn: t, step: 1,
      message: { role: 'tool', source: { kind: 'tool', callId }, toolCallId: callId, content: text(`1\texport const ${name} = () => {}\n2\t// ${name}\n3\texport default ${name}`), isError: false, id: nid('r') },
      meta: { cwd: process.env.FIXTURE_CWD },
    }, 'append', { sourceEventSeqs: [seq - 1] }))
    out.push(ev('step/end', { turn: t, step: 1 }))
    out.push(ev('step/start', { turn: t, step: 2 }))
    out.push(ev('assistant/message', {
      turn: t, step: 2,
      message: { role: 'assistant', content: text(answers[t % answers.length](name, file)), source: src, id: nid('a') },
      usage: { inputTokens: 1500, outputTokens: 160, totalTokens: 1660 },
      stream: [],
    }, 'append'))
    out.push(ev('step/end', { turn: t, step: 2 }))
  } else {
    out.push(ev('step/end', { turn: t, step: 1 }))
  }
  out.push(ev('turn/end', { turn: t, reason: { kind: 'completed' } }))
  await handle.append(out)
}
await handle.append([ev('session/title', { title: 'Stream fixture (synthetic long session)', messageSeqs: [firstUser], source: { kind: 'fallback' } })])
await handle.close()
console.log(`wrote ${turns} turns, ${seq} events to ${root}`)
process.exit(0)
