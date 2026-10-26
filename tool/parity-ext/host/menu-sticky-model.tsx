// The real model selector, with a synthetic directory and no Host connection.
import { useEffect, useMemo, useRef } from 'react'
import { ModelSelect } from '@dsh/ui-model-selection/src/client/ModelSelect.tsx'
import { en, zh } from '@dsh/ui-model-selection/src/client/locales.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

function Model({ props, locale }: { props: any; locale: string }) {
  const root = useRef<HTMLDivElement>(null)
  const t = useMemo(() => createTranslator(locale, { en, zh }), [locale])
  const state = useMemo(() => ({
    current: null, routable: null, groups: props.groups, failures: [],
    status: 'ready', pending: null, error: null,
  }), [props])
  const directory = useMemo(() => ({ getSnapshot: () => state, subscribe: () => () => {} }), [state])
  useEffect(() => {
    const mark = () => {
      const list = document.querySelector('[data-menu-group]')?.parentElement
      if (list) list.setAttribute('data-parity-id', 'model-list')
    }
    const observer = new MutationObserver(mark)
    observer.observe(document.body, { childList: true, subtree: true })
    root.current?.querySelector('button')?.click()
    mark()
    return () => observer.disconnect()
  }, [])
  return <div ref={root} style={{ position: 'absolute', left: 24, bottom: 20 }}>
    <ModelSelect {...({ locked: false, available: true, directory, load: () => {},
      select: async () => ({ ok: true }), t,
      renderSlot: (_name: string, _owner: unknown, options: any) => options.fallback } as any)} />
  </div>
}

export const kinds: Record<string, KindRenderer> = {
  'menu-sticky.model': (props, ctx) => <Model props={props} locale={ctx.case.locale} />,
}
