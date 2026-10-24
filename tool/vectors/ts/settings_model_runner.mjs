// Form-model vector: dsh's REAL SettingsFormModel (ui-primitives settings-form,
// with settingsNumberField / settingsTextField and createSnapshotStore) over a
// scripted SettingsFormScope.
//
// Glue (the only non-dsh code): the scope. Its snapshot is whatever the last
// `start` / `scope` step set (replaced wholesale, subscribers notified at once);
// `mutate(ops, expectedRevision)` and each secret control's `write(text)` park
// until an `answer` step settles them: `result` true or false resolves the
// promise with it, {throw: message} rejects. An answer may carry `scope`, a
// snapshot applied just before it settles (what the real form does when a
// write lands: the mirror takes the answer, then the write resolves).
//
// Steps (`op`): start {specs:[{field,kind:number|text}], secrets:[field],
// snapshot}, scope {snapshot}, edit {field,text}, reset {field}, save, discard,
// answer {method:'mutate'|'secret:<field>', result, scope?}, dispose.
// After every step the runner waits for quiescence and records:
//   shell   SettingsFormShell
//   fields  SettingsFieldState of every spec field and secret control
//   bound   the snapshot of the store `bind` published (what a card renders)
//   calls   the mutate / secret calls made during the step
//   error   the message of an action that threw

import { settle } from './settings_loader.mjs'

const plain = value => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))

export async function runModelVector(fixture, { load }) {
  const model = await load('packages/client/ui-primitives/src/settings-form/form-model.ts')
  const expected = []
  let world

  const newWorld = (step) => {
    const state = {
      snapshot: structuredClone(step.snapshot),
      listeners: new Set(),
      calls: [],
      queued: new Map(),
      waiting: new Map(),
    }
    const deliver = (call, result) => {
      if (result !== null && typeof result === 'object') call.reject(new Error(result.throw))
      else call.resolve(result)
    }
    const park = (key, entry) => {
      state.calls.push(entry)
      return new Promise((resolve, reject) => {
        const call = { resolve, reject }
        const queued = state.queued.get(key) ?? []
        if (queued.length > 0) deliver(call, queued.shift())
        else state.waiting.set(key, [...(state.waiting.get(key) ?? []), call])
      })
    }
    const scope = {
      getSnapshot: () => state.snapshot,
      subscribe: (listener) => {
        state.listeners.add(listener)
        return () => { state.listeners.delete(listener) }
      },
      mutate: (ops, expectedRevision) => park('mutate', {
        call: 'mutate', ops: plain(ops), expectedRevision: expectedRevision ?? null,
      }),
    }
    const specs = step.specs.map(spec => (spec.kind === 'number'
      ? model.settingsNumberField(spec.field)
      : model.settingsTextField(spec.field)))
    const secrets = (step.secrets ?? []).map(field => ({
      field,
      write: text => park(`secret:${field}`, { call: 'secret', field, text }),
    }))
    const form = new model.SettingsFormModel(scope, specs, secrets)
    const project = () => ({ shell: form.shell(), fields: fieldStates() })
    const fieldNames = [...step.specs.map(spec => spec.field), ...(step.secrets ?? [])]
    const fieldStates = () => Object.fromEntries(fieldNames.map(field => [field, form.field(field)]))
    const store = form.bind(project)
    const notify = () => { for (const listener of [...state.listeners]) listener() }
    return { state, form, store, project, actions: form.actions(), notify, deliver, fieldNames }
  }

  for (const [index, step] of fixture.steps.entries()) {
    let error
    if (step.op === 'start') {
      world = newWorld(step)
    } else if (world === undefined) {
      throw new Error(`step ${index}: ${step.op} before start`)
    } else {
      try {
        switch (step.op) {
          case 'scope':
            world.state.snapshot = structuredClone(step.snapshot)
            world.notify()
            break
          case 'edit': world.actions.edit(step.field, step.text); break
          case 'reset': world.actions.resetField(step.field); break
          case 'save': world.actions.save(); break
          case 'discard': world.actions.discard(); break
          case 'dispose': world.form.dispose(); break
          case 'answer': {
            const waiting = world.state.waiting.get(step.method) ?? []
            if (step.scope !== undefined) {
              world.state.snapshot = structuredClone(step.scope)
              world.notify()
            }
            const call = waiting.shift()
            if (call === undefined) {
              world.state.queued.set(step.method, [...(world.state.queued.get(step.method) ?? []), step.result])
            } else {
              world.deliver(call, step.result)
            }
            break
          }
          default: throw new Error(`step ${index}: unknown op ${String(step.op)}`)
        }
      } catch (caught) {
        if (String(caught?.message).startsWith(`step ${index}:`)) throw caught
        error = caught instanceof Error ? caught.message : String(caught)
      }
    }
    await settle()
    const out = {
      shell: world.form.shell(),
      fields: Object.fromEntries(world.fieldNames.map(field => [field, world.form.field(field)])),
      bound: world.store.getSnapshot(),
      calls: world.state.calls,
      error,
    }
    world.state.calls = []
    expected.push(plain(out))
  }
  return { expected }
}
