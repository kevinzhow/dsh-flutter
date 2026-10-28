// Mount the real upstream component. The wrapper only fixes the capture frame;
// all control CSS, glyphs, Tooltip and input-modality handling are upstream.
import {HeaderLeadingControls} from '@dsh/ui-sidebar/src/client/HeaderLeadingControls.tsx'
import type {KindRenderer} from '../../parity-web/host/types.ts'

const labels: Record<string, string> = {'toggle.open': 'Open sidebar', 'session.new.label': 'New session'}
export const kinds: Record<string, KindRenderer> = {
  'header-leading.actual': () => <div data-header-leading-frame style={{position: 'fixed', left: 0, top: 0, width: 96, height: 64, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--dsw-alias-bg-base)'}}>
    <HeaderLeadingControls
      toggleSidebar={() => {document.body.dataset.headerToggleCalls = String(Number(document.body.dataset.headerToggleCalls ?? 0) + 1)}}
      startSession={() => {document.body.dataset.headerSessionCalls = String(Number(document.body.dataset.headerSessionCalls ?? 0) + 1)}}
      useShortcuts={(selector: any) => selector([])}
      t={(key: string) => labels[key] ?? key}
    />
  </div>,
}
