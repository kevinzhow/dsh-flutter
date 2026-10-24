// Replays a `dsh-settings-vector/1` fixture through dsh's REAL TypeScript settings
// client code and prints the expectations as JSON.
//
//   node run_settings_vector.mjs FIXTURE.json [--out PATH]
//
// The fixture's `kind` selects the family:
//   schema      SettingsSchemaService (real schemastery resolver)          settings_schema_runner.mjs
//   form        SettingsDescribeMirror + ConfigFormController + ConfigForms,
//               mounted by the real ui-settings `apply` over a real cordis Context
//                                                                           settings_form_runner.mjs
//   form-model  SettingsFormModel (ui-primitives settings-form)             settings_model_runner.mjs
//
// Environment (defaults are relative to this repository, see gen_settings_expected.py):
//   DSH_SRC              dsh checkout (read-only), default <repo>/.local/dsh-src
//   DSH_VECTOR_NODE_DIR  node_modules with tsx/zustand/immer, default <repo>/.local/vector-node
//
// Only the remote (`ctx.remote.settings.describe/mutate`, `$on`) and the scope of
// the form-model are glue written here; everything else is dsh code, unpatched.
// Exit status: 0 ok, 1 failure, 2 a prerequisite is missing.

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
if (fixturePath === undefined) die('usage: run_settings_vector.mjs FIXTURE.json [--out PATH]')

const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'))
if (fixture.format !== 'dsh-settings-vector/1') die(`unsupported fixture format ${String(fixture.format)}`)

const dsh = await loadDsh()
let result
switch (fixture.kind) {
  case 'schema': {
    const { runSchemaVector } = await import('./settings_schema_runner.mjs')
    result = await runSchemaVector(fixture, dsh)
    break
  }
  case 'form': {
    const { runFormVector } = await import('./settings_form_runner.mjs')
    result = await runFormVector(fixture, dsh)
    break
  }
  case 'form-model': {
    const { runModelVector } = await import('./settings_model_runner.mjs')
    result = await runModelVector(fixture, dsh)
    break
  }
  default:
    die(`unsupported fixture kind ${String(fixture.kind)}`)
}

const json = `${JSON.stringify(result)}\n`
if (outPath === undefined) process.stdout.write(json)
else fs.writeFileSync(outPath, json)
process.exit(0)
