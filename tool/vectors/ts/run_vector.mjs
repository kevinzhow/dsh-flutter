// Replays a `dsh-session-vector/1` fixture through dsh's REAL TypeScript client
// model and prints `{window, chat}`: the `expected` window snapshots and the chat
// snapshots of dsh's real conversation engine over each window (chat_glue.mjs).
//
//   node run_vector.mjs FIXTURE.json [--out PATH] [--meta]
//
// Environment (defaults are relative to this repository, see gen_expected.py):
//   DSH_SRC              dsh checkout (read-only), default <repo>/.local/dsh-src
//   DSH_VECTOR_NODE_DIR  directory holding node_modules with tsx/zustand/immer,
//                        default <repo>/.local/vector-node
//
// REAL dsh code (loaded from DSH_SRC; nothing is copied or patched):
//   session-controller/src/client/sessions/session.ts          Session (open, doOpen,
//       acceptEventChange, installWindow, publishAssistantEntry, prependWindow,
//       appendLive, loadOlder, openState/hasMore bookkeeping)
//   session-controller/src/client/transport.ts                  SessionEventStream
//       (follow() wrapper: snapshot/revision checks, readPage)
//   gateway/src/client/journal-stream.ts                        RemoteJournalStream
//       (cursor algebra, gap repair, generation replacement, prepend)
//   gateway/src/client/remote-stream.ts                         RemoteStream
//       (reconnecting logical stream, restart, retry pacing)
//   gateway/src/client/stream-client.ts                         RemoteStreamCarrierError
//   session-controller/src/client/sessions/assistant-stream.ts  ClientAssistantStream
//   session-controller/src/client/contract/events.ts            MutableSessionEventSource
//   llm/src/assistant-stream.ts                                 expandAssistantStream
//   plus their transitive imports (history-records, session-wire-event,
//   projection-store, notifier, typert-protocol RemoteError, ...).
//
// GLUE written here (the only non-dsh code):
//   - the fake `SessionRemotes`: `session.follow` yields the fixture's frames per
//     connection generation from an in-memory queue, `session.page` answers from
//     the recorded `page` steps, `$stream` builds the real `RemoteStream` over a
//     fake connection handle whose `generation` snapshot is the current
//     generation number; `commands`/`subagents` are never called;
//   - the step driver, the settle (flush) loop and the snapshot encoder;
//   - module resolution: dsh's own tsconfig `paths` (via tsx) map
//     `@deepseek-ai/*` imports to source, a small hook resolves the two
//     third-party packages (zustand, immer) from DSH_VECTOR_NODE_DIR.
//
// Page answers are matched on (address, throughSeq, beforeSeq) only: dsh's
// Session hardcodes its own history window options, so maxMessages/turnWindow
// of the recorded request are ignored, as is the follow request.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { register as registerHooks } from 'node:module'

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, '..', '..', '..')
const dshSrc = path.resolve(process.env.DSH_SRC ?? path.join(repoRoot, '.local', 'dsh-src'))
const nodeDir = path.resolve(process.env.DSH_VECTOR_NODE_DIR ?? path.join(repoRoot, '.local', 'vector-node'))

function die(message, code = 1) {
  process.stderr.write(`run_vector: ${message}\n`)
  process.exit(code)
}

const args = process.argv.slice(2)
let fixturePath
let outPath
let wantMeta = false
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out') outPath = args[++i]
  else if (args[i] === '--meta') wantMeta = true
  else if (fixturePath === undefined) fixturePath = args[i]
  else die(`unexpected argument ${args[i]}`)
}
if (fixturePath === undefined) die('usage: run_vector.mjs FIXTURE.json [--out PATH] [--meta]')

const sessionControllerClient = path.join(dshSrc, 'packages/api/session-controller/src/client')
if (!fs.existsSync(path.join(sessionControllerClient, 'sessions/session.ts'))) die(`dsh source not found at ${dshSrc} (set DSH_SRC)`, 2)
const tsxApi = path.join(nodeDir, 'node_modules/tsx/dist/esm/api/index.mjs')
if (!fs.existsSync(tsxApi)) die(`tsx not installed under ${nodeDir} (set DSH_VECTOR_NODE_DIR)`, 2)

// ---- module loading: dsh tsconfig paths via tsx, third-party packages from nodeDir ----

const { register: registerTsx } = await import(pathToFileURL(tsxApi).href)
registerTsx({ tsconfig: path.join(dshSrc, 'tsconfig.base.json') })
registerHooks(pathToFileURL(path.join(here, 'resolve-externals.mjs')).href, {
  parentURL: import.meta.url,
  data: { nodeDir },
})

const load = specifier => import(pathToFileURL(path.join(dshSrc, specifier)).href)
const { Session } = await load('packages/api/session-controller/src/client/sessions/session.ts')
const { RemoteStream } = await load('packages/api/gateway/src/client/remote-stream.ts')
const { RemoteStreamCarrierError } = await load('packages/api/gateway/src/client/stream-client.ts')
const { createChatGlue } = await import(pathToFileURL(path.join(here, 'chat_glue.mjs')).href)
const chatGlue = await createChatGlue(load)

// ---- fixture ----

const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'))
if (fixture.format !== 'dsh-session-vector/1') die(`unsupported fixture format ${String(fixture.format)}`)
const steps = fixture.steps
const SESSION_ID = 'session-1'

const problems = []
const notes = []
const note = (index, text) => { notes.push(`step ${index}: ${text}`) }

// Stable stringify for deep-equality keys.
function canon(value) {
  if (Array.isArray(value)) return `[${value.map(canon).join(',')}]`
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().filter(k => value[k] !== undefined).map(k => `${JSON.stringify(k)}:${canon(value[k])}`).join(',')}}`
  }
  return JSON.stringify(value)
}

// ---- fake remote ----

let currentStep = -1
let currentGeneration = 1
let followCalls = 0
const recordedGenerations = new Set(steps.flatMap(step => (step.generation === undefined ? [] : [step.generation])))

/** Frames and ends the fixture delivers on one connection generation. */
class Channel {
  queue = []
  waiter = undefined
  push(item) {
    this.queue.push(item)
    this.waiter?.()
  }
  async next(signal) {
    while (this.queue.length === 0) {
      if (signal.aborted) return { aborted: true }
      await new Promise(resolve => {
        const wake = () => { signal.removeEventListener('abort', wake); this.waiter = undefined; resolve() }
        this.waiter = wake
        signal.addEventListener('abort', wake, { once: true })
      })
    }
    return { item: this.queue.shift() }
  }
}
const channels = new Map()
const channelOf = generation => {
  let channel = channels.get(generation)
  if (channel === undefined) { channel = new Channel(); channels.set(generation, channel) }
  return channel
}

const recordedPages = []
steps.forEach((step, index) => {
  if (step.op !== 'page') return
  const request = step.request
  recordedPages.push({
    index,
    key: canon([request.address, request.throughSeq, request.beforeSeq ?? null]),
    response: step.response,
    used: false,
  })
})

async function * follow(_request, signal) {
  const generation = ++followCalls
  if (process.env.DSH_VECTOR_TRACE) note(currentStep, `follow opened (#${generation})`)
  const channel = channelOf(generation)
  while (true) {
    const next = await channel.next(signal)
    if (next.aborted) return
    const item = next.item
    if (item.end) {
      if (item.error === null || item.error === undefined) return
      const message = typeof item.error === 'string' ? item.error : item.error.message ?? JSON.stringify(item.error)
      throw new RemoteStreamCarrierError(message)
    }
    yield structuredClone(item.frame)
  }
}

async function page(request) {
  const key = canon([request.address, request.throughSeq, request.beforeSeq ?? null])
  const matches = recordedPages.filter(candidate => candidate.key === key)
  const chosen = matches.find(candidate => !candidate.used) ?? matches.at(-1)
  if (chosen === undefined) {
    const message = `no recorded page answer for ${key}`
    problems.push(`step ${currentStep}: ${message}`)
    throw new Error(message)
  }
  chosen.used = true
  return { ok: true, value: structuredClone(chosen.response) }
}

const connection = {
  generation: {
    getSnapshot: () => currentGeneration,
    subscribe: () => () => {},
  },
}

const remote = {
  $stream: options => new RemoteStream(connection, options),
  session: { follow, page },
  commands: { execute: async () => { throw new Error('commands.execute is not part of the vector') } },
  subagents: {
    prompt: async () => { throw new Error('subagents.prompt is not part of the vector') },
    interruptByParent: async () => { throw new Error('subagents.interruptByParent is not part of the vector') },
  },
}

// ---- diagnostics ----

const realConsoleError = console.error
console.error = (...values) => {
  notes.push(`step ${currentStep}: console.error: ${values.map(value => (value instanceof Error ? value.message : String(value))).join(' ')}`)
  realConsoleError(...values)
}
process.on('unhandledRejection', reason => {
  notes.push(`step ${currentStep}: unhandled rejection: ${reason instanceof Error ? reason.message : String(reason)}`)
})

// ---- replay ----

const settle = async () => {
  for (let round = 0; round < 12; round++) await new Promise(resolve => setImmediate(resolve))
  await new Promise(resolve => setTimeout(resolve, 2))
  for (let round = 0; round < 12; round++) await new Promise(resolve => setImmediate(resolve))
}

function encodeEntry(entry) {
  if (entry.type === 'event') return ['event', entry.event.seq, entry.event.type]
  if (entry.type === 'transient' && entry.event.type === 'assistant/live-chunk') {
    const chunk = entry.event.data.chunk
    return ['live', entry.event.seq, chunk.type, typeof chunk.text === 'string' ? chunk.text : '']
  }
  throw new Error(`unrecognised window entry ${JSON.stringify(entry)}`)
}

const SNAPSHOT_OPS = new Set(['opened', 'frame', 'ended'])
let session
let openPromise
let chatBinding
const expected = []
const expectedChat = []

for (let index = 0; index < steps.length; index++) {
  const step = steps[index]
  currentStep = index
  let snapshot = false
  switch (step.op) {
    case 'action':
      if (step.name === 'open') {
        if (session !== undefined) die(`step ${index}: second open action`)
        session = new Session(SESSION_ID, remote)
        chatBinding = chatGlue.bind(session.eventSource)
        openPromise = session.open().catch(error => { note(index, `open() rejected: ${error instanceof Error ? error.message : String(error)}`) })
      } else if (step.name === 'loadOlder') {
        if (session === undefined) die(`step ${index}: loadOlder before open`)
        await session.loadOlder()
        snapshot = true
      } else if (step.name !== 'prompt') {
        die(`step ${index}: unknown action ${String(step.name)}`)
      }
      break
    case 'opened':
      currentGeneration = step.generation
      channelOf(step.generation)
      snapshot = true
      break
    case 'frame':
      currentGeneration = Math.max(currentGeneration, step.generation)
      channelOf(step.generation).push({ frame: step.frame })
      snapshot = true
      break
    case 'ended':
      channelOf(step.generation).push({ end: true, error: step.error ?? null })
      snapshot = true
      break
    case 'page':
      break
    default:
      die(`step ${index}: unknown op ${String(step.op)}`)
  }
  await settle()
  if (!snapshot || !(SNAPSHOT_OPS.has(step.op) || step.name === 'loadOlder')) continue
  if (session === undefined) die(`step ${index}: ${step.op} before open`)
  const sessionSnapshot = session.getSnapshot()
  const window = session.eventSource.getSnapshot()
  if (sessionSnapshot.hasMore !== window.hasMore) {
    note(index, `session snapshot hasMore=${sessionSnapshot.hasMore} differs from event window hasMore=${window.hasMore}`)
  }
  if (sessionSnapshot.openState === 'error') {
    note(index, `openState error: ${sessionSnapshot.openError?.message ?? String(sessionSnapshot.openError)}`)
  }
  expected.push({
    step: index,
    openState: sessionSnapshot.openState,
    hasMore: window.hasMore,
    entries: window.entries.map(encodeEntry),
  })
  expectedChat.push({ step: index, ...chatBinding.project({ systemPrompts: fixture.projectSystemPrompts === true }) })
}

chatBinding?.unsubscribe()
await session?.dispose()
void openPromise

for (let generation = 1; generation <= followCalls; generation++) {
  // The model reopened follow (rebaseline, retry) on a generation the trace never recorded.
  if (!recordedGenerations.has(generation)) problems.push(`the model opened follow #${generation} but the trace records no generation ${generation}`)
}
for (const unused of recordedPages.filter(candidate => !candidate.used)) {
  notes.push(`recorded page at step ${unused.index} was never requested by the model`)
}

const json = `${JSON.stringify({ window: expected, chat: expectedChat })}\n`
if (outPath === undefined) process.stdout.write(json)
else fs.writeFileSync(outPath, json)
if (wantMeta || notes.length > 0) {
  for (const line of notes) process.stderr.write(`note: ${line}\n`)
}
if (problems.length > 0) {
  for (const line of problems) process.stderr.write(`problem: ${line}\n`)
  process.exit(1)
}
process.exit(0)
