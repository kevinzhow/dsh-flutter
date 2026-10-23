import type { KindRenderer } from './types.ts'

// Every host file exports `kinds: Record<string, KindRenderer>`. Files are discovered by glob:
// adding a file registers its kinds, no shared file is edited. Core kinds live in host/cases/,
// extension kinds in tool/parity-ext/host/.
const modules = import.meta.glob<{ kinds: Record<string, KindRenderer> }>(
  ['./cases/*.tsx', '../../parity-ext/host/*.tsx'],
  { eager: true },
)

export const registry: Record<string, KindRenderer> = {}
for (const [file, mod] of Object.entries(modules)) {
  for (const [kind, render] of Object.entries(mod.kinds ?? {})) {
    if (registry[kind]) throw new Error(`parity host: kind ${kind} registered twice (${file})`)
    registry[kind] = render
  }
}
