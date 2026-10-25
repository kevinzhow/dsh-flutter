import { CompactionItem } from '@dsh/ui-chat/src/client/chat/CompactionItem.tsx'
import { CompactionCommandCard } from '@dsh/ui-chat/src/client/chat/CompactionCommandCard.tsx'
import { GenericCommandCard } from '@dsh/ui-chat/src/client/chat/GenericCommandCard.tsx'
import { en, zh } from '@dsh/ui-chat/src/client/locale.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

const SUMMARY = '## Summary\n\nRemember **this** synthetic fact.'
const render = (compaction: boolean): KindRenderer => (props, ctx) => {
  const t = createTranslator(ctx.case.locale, { en, zh })
  const node = {
    kind: 'command', seq: 1, time: 10001, commandId: 'fixture',
    name: props.orphan ? null : props.manual ? 'compact' : 'status', args: null,
    outcome: props.state === 'running' ? null : { kind: props.state ?? 'success', ...(props.text === undefined ? {} : { text: props.text }) },
  } as any
  const marker = {
    kind: 'compaction', seq: 3, time: 10003, summary: props.summary ? SUMMARY : null,
    summaryEventSeq: props.summary ? 2 : null,
    shadowedItemCount: props.counts ? 2 : null, shadowedTokenCount: props.counts ? 125 : null,
  } as any
  return (
    <div data-parity-id="lifecycle-el" style={{ width: Number(props.width) }} ref={el => {
      el?.querySelector('button, [data-disclosure-row]')?.setAttribute('data-parity-id', 'lifecycle-toggle')
    }}>
      {compaction
        ? <CompactionItem node={marker} title={props.manual ? t('message.compaction.commandTitle') : undefined}
            fallbackSummary={props.manual ? 'Manual settlement' : undefined} t={t} />
        : props.manual ? <CompactionCommandCard node={node} t={t} /> : <GenericCommandCard node={node} t={t} />}
    </div>
  )
}
export const kinds: Record<string, KindRenderer> = { 'chat.command': render(false), 'chat.compaction': render(true) }
