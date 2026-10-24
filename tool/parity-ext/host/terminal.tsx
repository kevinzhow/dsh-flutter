// dsh's real sidebar terminal body (ui-sidebar-terminal TerminalBody: the xterm.js screen, the status strip, the error line and
// the missing-terminal panel), mounted over a scripted terminal model.
//
//   terminal.body   props {state, screen?, width, height}
//                     state    the TerminalViewState the model publishes (phase, info, writable, error, issue)
//                     screen   text written to the emulator as the Host's opening snapshot
//
// Host services mocked (the terminal controller and the sidebar own them in dsh): `useTabInfo`, the keyed state hook
// `useTerminal`, the theme snapshot `useTheme` and the model `view(tab)` (every command a no-op), plus the locale seat `t`
// (a translator over dsh's `sidebarTerminal` dictionaries). The user's terminal font list is `SF Mono`, which the harness
// registers (Noto Sans Mono) on both providers.
import { useMemo } from 'react'
import { TerminalBody } from '@dsh/ui-sidebar-terminal/src/client/terminal.tsx'
import { en, zh } from '@dsh/ui-sidebar-terminal/src/client/locales.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

const noop = () => {}

function Body({ props, locale }: { props: Record<string, any>; locale: string }) {
  const t = useMemo(() => createTranslator(locale, { en, zh }), [locale])
  const state = useMemo(() => {
    const info = props.state.info
    return {
      writable: false, ...props.state,
      render: props.screen === undefined || info === undefined ? undefined
        : { revision: 1, frame: { type: 'snapshot', sequence: 0, screen: props.screen, info, writable: props.state.writable } },
    }
  }, [props])
  const model = useMemo(() => ({
    mount: () => noop, connect: noop, refresh: async () => {}, write: noop, resize: noop, acknowledge: noop, rename: async () => {},
  }), [])
  const theme = useMemo(() => ({ fontFamilies: { terminal: 'SF Mono' }, fontSizes: { terminal: 13 } }), [])
  return (
    <div data-parity-id="terminal" style={{ width: props.width, height: props.height, display: 'flex', flexDirection: 'column' }}>
      <TerminalBody
        {...({
          useTabInfo: () => ({ tab: { id: 'terminal-1', visible: true, actions: { openTab: noop } } }),
          useTerminal: (_id: string, select?: (value: any) => any) => (select ? select(state) : state),
          useTheme: (select: (value: any) => any) => select(theme),
          view: () => model,
          t,
        } as any)}
      />
    </div>
  )
}

export const kinds: Record<string, KindRenderer> = {
  'terminal.body': (props, ctx) => <Body props={props} locale={ctx.case.locale} />,
}
