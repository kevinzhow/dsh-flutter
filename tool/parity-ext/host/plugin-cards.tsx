import type {KindRenderer} from '../../parity-web/host/types.ts'

// Fail closed: source-TS and reconstructed cards are not the accepted reference.
// capture-plugin-cards.mjs fills this plan's react outputs from the integrity-
// verified published factory. Existing Web renderers are unchanged.
export const kinds: Record<string, KindRenderer> = {
  'plugin-cards.manager': () => {
    throw new Error('Use tool/design-system/capture-plugin-cards.mjs for the actual published PluginManager reference; source-TS substitution is refused.')
  },
}
