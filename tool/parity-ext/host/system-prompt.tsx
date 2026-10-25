import { SystemPromptRow } from '@dsh/ui-chat/src/client/chat/SystemPromptRow.tsx'
import { en, zh } from '@dsh/ui-chat/src/client/locale.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

export const kinds: Record<string, KindRenderer> = {
  'chat.system-prompt': (props, ctx) => (
    <div data-parity-id="prompt-el" style={{ width: Number(props.width) }}
      ref={el => el?.querySelector('[data-disclosure-row]')?.setAttribute('data-parity-id', 'prompt-toggle')}>
      <SystemPromptRow text={String(props.text)} update={props.update === true}
        t={createTranslator(ctx.case.locale, { en, zh })} />
    </div>
  ),
}
