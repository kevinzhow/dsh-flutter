// Actual source ModelSelect, including its trigger and portaled root menu.
import {useLayoutEffect, useMemo, useRef, useState} from 'react'
import {ModelSelect} from '@dsh/ui-model-selection/src/client/ModelSelect.tsx'
import {en, zh} from '@dsh/ui-model-selection/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'

const groups = [
  {id: 'deepseek-official', name: 'DeepSeek', models: [
    {id: 'flash', name: 'DeepSeek V4.1 Flash', reasoning: {efforts: [
      {id: 'low', name: 'Low'}, {id: 'high', name: 'High'}, {id: 'max', name: 'Max'},
    ], defaultEffort: 'high'}},
    {id: 'pro', name: 'DeepSeek V4.1 Pro'},
  ]},
  {id: 'local', name: 'Local provider', models: [
    {id: 'alpha', name: 'Alpha'}, {id: 'beta', name: 'Beta'},
    {id: 'gamma', name: 'Gamma'}, {id: 'delta', name: 'Delta'},
  ]},
]

function Model({props, ctx}: any) {
  const root = useRef<HTMLDivElement>(null)
  const t = useMemo(() => createTranslator(ctx.case.locale, {en, zh}), [ctx.case.locale])
  const [current, setCurrent] = useState<any>({provider: 'deepseek-official', model: 'flash', reasoningEffort: 'max'})
  const [result, setResult] = useState('none')
  const state = useMemo(() => ({current, routable: true, groups, failures: [],
    status: 'ready', pending: null, error: null}), [current])
  const directory = useMemo(() => ({getSnapshot: () => state, subscribe: () => () => {}}), [state])
  useLayoutEffect(() => {
    const html = document.documentElement
    const previous = html.getAttribute('data-platform')
    const previousTop = html.style.getPropertyValue('--dsh-frame-overlay-top')
    html.setAttribute('data-platform', props.platform)
    html.style.setProperty('--dsh-frame-overlay-top', props.platform === 'darwin' ? '68px' : '0px')
    return () => {
      if (previous === null) html.removeAttribute('data-platform')
      else html.setAttribute('data-platform', previous)
      if (previousTop) html.style.setProperty('--dsh-frame-overlay-top', previousTop)
      else html.style.removeProperty('--dsh-frame-overlay-top')
    }
  }, [props.platform])
  useLayoutEffect(() => {
    const mark = () => {
      root.current?.querySelector('button')?.setAttribute('data-parity-id', 'model-chip')
      const menu = [...document.querySelectorAll<HTMLElement>('[role="menu"], [role="group"]')]
        .find(node => node.getAttribute('aria-label') === t('menu.aria'))
      menu?.setAttribute('data-parity-id', 'model-sheet')
      const cells = menu?.querySelectorAll('[role="menuitem"]')
      cells?.[0]?.setAttribute('data-parity-id', 'model-root-model')
      cells?.[1]?.setAttribute('data-parity-id', 'model-root-effort')
      menu?.querySelector('input')?.setAttribute('data-parity-id', 'model-search')
      for (const row of menu?.querySelectorAll('[role="menuitemradio"]') ?? []) {
        const owner = row.querySelector('[data-provider-id]')
        const id = owner ? `model-option-${owner.getAttribute('data-provider-id')}/${owner.getAttribute('data-model-id')}`
          : `effort-option-effort:${row.textContent?.toLowerCase().trim()}`
        row.setAttribute('data-parity-id', id)
      }
    }
    mark()
    const observer = new MutationObserver(mark)
    observer.observe(document.body, {childList: true, subtree: true})
    return () => observer.disconnect()
  }, [t])
  return <div style={{position: 'absolute', inset: 0}} data-parity-id="reported-model-viewport">
    <div data-parity-id="reported-model-result" style={{position: 'absolute', left: 24, top: 24, fontSize: 13}}>
      Selection: {result}
    </div>
    <div ref={root} style={{position: 'absolute', right: 24, bottom: 24}}>
      <ModelSelect {...({locked: false, available: true, directory, load: () => {},
        select: async (next: any) => {setCurrent(next); setResult(`${next.provider}/${next.model}/${next.reasoningEffort ?? 'default'}`); return {ok: true}},
        t, renderSlot: (_name: string, _owner: unknown, options: any) => options.fallback} as any)} />
    </div>
  </div>
}

export const kinds: Record<string, KindRenderer> = {
  'reported-model.menu': (props, ctx) => <Model props={props} ctx={ctx} />,
}
