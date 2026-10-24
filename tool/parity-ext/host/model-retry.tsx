import { RetryNodeView } from '@dsh/ui-chat/src/client/chat/MessageItem.tsx'
import { en, zh } from '@dsh/ui-chat/src/client/locale.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

// Freeze only the client wall clock, as in the question-wait fixture. The
// retry component itself anchors the delay on mount; host event time differs.
const NOW = 1_700_000_000_000
export const kinds: Record<string, KindRenderer> = {
  'chat.model-retry': (props, ctx) => {
    Date.now = () => NOW
    const current = {
      kind: 'model-retry', retryState: props.state, seq: 3, time: 0,
      retryId: 'fixture', turn: 1, step: 1, retry: 1, mode: 'normal',
      delayMs: 2500, maxRetries: 3,
      failure: { code: 'RATE_LIMIT', message: 'Try later' },
    }
    return (
      <div style={{ width: Number(props.width) }} ref={(el) => {
        const details = el?.querySelector('details')
        details?.setAttribute('data-parity-id', 'retry-el')
        if (props.open) details?.setAttribute('open', '')
      }}>
        <RetryNodeView {...({ node: { data: { current, attempts: [current] } },
          t: createTranslator(ctx.case.locale, { en, zh }) } as any)} />
      </div>
    )
  },
}
