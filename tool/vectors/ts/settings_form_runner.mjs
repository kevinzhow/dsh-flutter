// Form vector: a scripted trace through dsh's REAL settings client services,
// mounted the way production mounts them: the real ui-settings `apply` over a
// real cordis Context (SettingsSchemaService, SettingsDescribeMirror, the
// `settings/document-updated` and `connection/reset` invalidations, the eager
// first read, ConfigForms with its ConfigFormController per namespace).
//
// Glue (the only non-dsh code): `ctx.remote` is dsh's own TestRemote test double
// (`$on` plus an `emit` driver) whose `settings.describe/mutate` park every call
// until the script answers it. An answer is a RemoteResult
// ({ok:true,value} | {ok:false,error:{code,message}}) or {throw:message}, a
// transport failure (the call rejects). An answer that arrives before its call
// waits in a queue.
//
// Steps (`op`): start (a fresh world; separates traces), answer, emit, reset,
// watch, set, unset, mutate, ensure, acceptView, whileServed, stopWhileServed,
// dispose. After every step the runner waits for quiescence and records:
//   mirror   status, error, and when a view is held its writable/hasDocument/revisions
//   forms    snapshot of each watched form (status, value, base, user, revision, writable)
//   calls    the settings.describe / settings.mutate calls made during the step
//   effects  whileServed registrations and disposals during the step
//   writes   outcome of every write so far: pending | true | false | rejected: <message>

import { settle } from './settings_loader.mjs'

const plain = value => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

export async function runFormVector(fixture, { load }) {
  const { Context } = await load('vendor/cordis/src/index.ts')
  const { TestRemote } = await load('packages/test-support/client-runtime/src/remote.ts')
  const { apply, inject } = await load('packages/client/ui-settings/src/client/index.ts')

  const expected = []
  let world

  const newWorld = () => {
    const ctx = new Context()
    const queued = { describe: [], mutate: [] }
    const waiting = { describe: [], mutate: [] }
    const state = { calls: [], effects: [], writes: {}, forms: new Map(), served: new Map() }
    const deliver = (call, result) => {
      if (result.throw !== undefined) call.reject(new Error(result.throw))
      else call.resolve(structuredClone(result))
    }
    const park = (method, entry) => {
      state.calls.push(entry)
      return new Promise((resolve, reject) => {
        const call = { resolve, reject }
        if (queued[method].length > 0) deliver(call, queued[method].shift())
        else waiting[method].push(call)
      })
    }
    const settings = {
      describe: () => park('describe', { call: 'describe' }),
      mutate: (ns, ops, expectedRevision) => park('mutate', {
        call: 'mutate', ns, ops: plain(ops), expectedRevision: expectedRevision ?? null,
      }),
    }
    const answer = (method, result) => {
      const call = waiting[method].shift()
      if (call === undefined) queued[method].push(result)
      else deliver(call, result)
    }
    const remote = new TestRemote(ctx, { settings })
    remote.$host = { home: undefined, isLoopback: false }
    return { ctx, remote, state, answer, fiber: undefined }
  }

  const track = (id, promise) => {
    world.state.writes[id] = 'pending'
    promise.then(
      accepted => { world.state.writes[id] = String(accepted) },
      error => { world.state.writes[id] = `rejected: ${error instanceof Error ? error.message : String(error)}` },
    )
  }

  const formOf = (ns) => {
    const form = world.state.forms.get(ns)
    if (form === undefined) throw new Error(`namespace ${ns} is not watched`)
    return form
  }

  // Captured at start: disposing the plugin unregisters the `configForms` service, the objects live on.
  const face = () => world.face

  const encode = () => {
    const mirror = face().getSnapshot()
    const view = mirror.view
    const out = {
      mirror: {
        status: mirror.status,
        error: mirror.error,
        view: view === undefined ? undefined : {
          writable: view.writable,
          hasDocument: view.hasDocument,
          revisions: Object.fromEntries(view.namespaces.map(row => [row.ns, row.revision])),
        },
      },
      forms: Object.fromEntries([...world.state.forms].map(([ns, form]) => {
        const snapshot = form.getSnapshot()
        return [ns, {
          status: snapshot.status,
          value: snapshot.value,
          base: snapshot.base,
          user: snapshot.user,
          revision: snapshot.revision,
          writable: snapshot.writable,
        }]
      })),
      calls: world.state.calls,
      effects: world.state.effects,
      writes: { ...world.state.writes },
    }
    world.state.calls = []
    world.state.effects = []
    return plain(out)
  }

  for (const [index, step] of fixture.steps.entries()) {
    if (step.op === 'start') {
      world = newWorld()
      world.fiber = world.ctx.plugin({ inject: [...inject], apply })
      await world.fiber.await()
      world.face = world.ctx.configForms.describe()
      world.forms = world.ctx.configForms
    } else if (world === undefined) {
      throw new Error(`step ${index}: ${step.op} before start`)
    } else {
      switch (step.op) {
        case 'answer': world.answer(step.method, step.result); break
        case 'emit': world.remote.emit(step.event, step.args ?? []); break
        case 'reset': world.ctx.emit('connection/reset'); break
        case 'watch': world.state.forms.set(step.ns, world.forms.get(step.ns)); break
        case 'set': track(step.id, formOf(step.ns).set(step.field, step.value)); break
        case 'unset': track(step.id, formOf(step.ns).unset(step.field)); break
        case 'mutate': track(step.id, formOf(step.ns).mutate(step.ops, step.expectedRevision ?? undefined)); break
        case 'ensure': void face().ensure(); break
        case 'acceptView': face().acceptView(structuredClone(step.view)); break
        case 'whileServed': {
          const off = world.forms.whileServed(step.namespaces, (served) => {
            world.state.effects.push({ effect: 'register', id: step.id, served: [...served].sort() })
            return () => { world.state.effects.push({ effect: 'off', id: step.id }) }
          })
          world.state.served.set(step.id, off)
          break
        }
        case 'stopWhileServed': world.state.served.get(step.id)(); break
        case 'dispose': void world.fiber.dispose(); break
        default: throw new Error(`step ${index}: unknown op ${String(step.op)}`)
      }
    }
    await settle()
    expected.push(encode())
  }
  return { expected }
}
