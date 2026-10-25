// Pure Markdown classification imports the file-icon module. Its CSS is a
// presentation dependency; no component is rendered by the behavior oracle.
export async function load(url, context, nextLoad) {
  if (url.endsWith('.css')) return {format:'module',source:'export default {}',shortCircuit:true}
  return nextLoad(url,context)
}
