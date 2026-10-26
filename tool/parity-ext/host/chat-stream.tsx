// The stream controls of dsh's chat view (ui-chat), with the real styles and component:
//
//   chat.stream.control  props {control: to-bottom | hint | load-earlier | load-earlier-loading}
//                          to-bottom            `.toBottom` of ChatView.module.css (the floating chevron)
//                          hint                 `.hint`, the "Loading history…" line shown while a session opens
//                          load-earlier         `.older button`, the "Load earlier" control
//                          load-earlier-loading the same control disabled, reading "Loading…"
//   chat.stream.actions  props {clock: start | end}  MessageIconActions, the real component: the clock and the copy action
//                          of a message (user rows put the clock first, assistant tails last)
//
// ChatView itself needs the whole host (sessions, conversation store); these are the pieces it renders from its own
// stylesheet and the real actions component, mounted alone. Host services mocked: the locale seat `t` (the real chat
// dictionary) and the wall clock (so `HH:mm` / date forms do not depend on today).
import { useLayoutEffect, useRef } from 'react'
import { MessageIconActions } from '@dsh/ui-chat/src/client/chat/MessageIconActions.tsx'
import css from '@dsh/ui-chat/src/client/chat/ChatView.module.css'
import { en, zh } from '@dsh/ui-chat/src/client/locale.ts'
import { IconChevronDownOutlineRegular } from '@dsh/ui-primitives/src/icons/index.tsx'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

/** 2020-03-04 10:05 local time: an earlier year, so the clock shows the date form. */
const MESSAGE_TIME = new Date(2020, 2, 4, 10, 5, 0).getTime()

function ActionFixture({ props, locale }: { props: any; locale: string }) {
  const root = useRef<HTMLDivElement>(null)
  const t = createTranslator(locale, { en, zh })
  useLayoutEffect(() => {
    const buttons = root.current?.querySelectorAll('button')
    buttons?.[0]?.setAttribute('data-parity-id', 'message-copy')
    buttons?.[1]?.setAttribute('data-parity-id', 'message-branch')
  }, [props])
  return <div ref={root} data-parity-id="stream-el" style={{ display: 'inline-block' }}>
    <MessageIconActions text="Copy me" time={MESSAGE_TIME} clock={props.clock ?? 'start'}
      onBranch={props.branch ? () => {} : undefined} t={t as any} />
  </div>
}

export const kinds: Record<string, KindRenderer> = {
  'chat.stream.control': (props, ctx) => {
    const t = createTranslator(ctx.case.locale, { en, zh })
    switch (props.control) {
      case 'to-bottom':
        // The button sits in `.toBottomSlot` (absolutely placed, 34px square with a -34px margin); the case frames the
        // button itself.
        return (
          <button type="button" data-parity-id="stream-el" className={css.toBottom} style={{ marginTop: 0 }}
            aria-label={t('chat.toBottom')}>
            <IconChevronDownOutlineRegular />
          </button>
        )
      case 'hint':
        // The hint is a block filling the column; the captured element is its text line, shrink-wrapped.
        return <div data-parity-id="stream-el" className={css.hint} style={{ display: 'inline-block' }}>{t('chat.loadingHistory')}</div>
      case 'load-earlier':
        return (
          <div className={css.older}>
            <button type="button" data-parity-id="stream-el">{t('chat.loadOlder')}</button>
          </div>
        )
      default:
        return (
          <div className={css.older}>
            <button type="button" data-parity-id="stream-el" disabled>{t('loading')}</button>
          </div>
        )
    }
  },
  'chat.stream.actions': (props, ctx) => {
    return <ActionFixture props={props} locale={ctx.case.locale} />
  },
}
