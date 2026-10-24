// Schema vector: every case runs through dsh's REAL ui-settings SettingsSchemaService
// (rehydrate + validate over the real schemastery resolver, vendor/schemastery).
//
// A case is accepted when rehydrate does not throw and validate answers undefined;
// that is exactly the question ConfigFormController.decode asks of a section.
// `expect` is null for accepted, otherwise the failure text (the error message of
// a throwing rehydrate counts as a failure).

export async function runSchemaVector(fixture, { load }) {
  const { SettingsSchemaService } = await load('packages/client/ui-settings/src/client/schema.ts')
  const { Context } = await load('vendor/cordis/src/index.ts')
  const service = new SettingsSchemaService(new Context())
  const out = []
  for (const [index, entry] of fixture.cases.entries()) {
    // `schemaRef` names an entry of the fixture's `schemas`; `schema` is an inline envelope (any JSON value).
    const envelope = entry.schemaRef === undefined ? entry.schema : fixture.schemas[entry.schemaRef]
    if (entry.schemaRef !== undefined && envelope === undefined) throw new Error(`case ${index}: unknown schema ${entry.schemaRef}`)
    let failure
    try {
      failure = service.validate(service.rehydrate(structuredClone(envelope)), structuredClone(entry.value))
    } catch (error) {
      failure = error instanceof Error ? error.message : String(error)
    }
    out.push(failure === undefined ? null : failure)
  }
  return { expect: out }
}
