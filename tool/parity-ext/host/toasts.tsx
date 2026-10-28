import type {KindRenderer} from '../../parity-web/host/types.ts'

// Normal provider routing invokes the real published ESM module. Direct generic
// rendering must never substitute a reconstructed Toast or source TS body.
export const kinds: Record<string, KindRenderer> = {
  'toast.source': () => {throw new Error('Use the automatically routed published Toast provider')},
}
