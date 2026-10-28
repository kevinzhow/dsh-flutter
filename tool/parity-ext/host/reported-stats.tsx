// Mount the actual exported pills and click their own source buttons. Only
// the projection data and the conversation backdrop are synthetic.
import {useLayoutEffect} from 'react'
import {ActivityPill, UsagePill} from '@dsh/ui-chat/src/client/chat/StatsPills.tsx'
import {en, zh} from '@dsh/ui-chat/src/client/locale.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'

const stats = {turns: 231, steps: 2901, llmMs: 37673000, toolMs: 9394000,
  ttftMs: 95000, ttftSteps: 10, decodeMs: 10000, decodeTokens: 1460}
const usage = {uncachedInputTokens: 9000000, cacheReadTokens: 150000000,
  cacheWriteTokens: 1000000, outputTokens: 1600000}

function Surface({props, ctx}: any) {
  const t = createTranslator(ctx.case.locale, {en, zh})
  useLayoutEffect(() => {
    const previous = document.documentElement.dataset.platform
    if (props.platform === 'darwin') document.documentElement.dataset.platform = 'darwin'
    else delete document.documentElement.dataset.platform
    const tag = () => {
      document.querySelector('[data-composer-stat] button')?.setAttribute('data-parity-id', 'stats-trigger')
      const panel = document.querySelector<HTMLElement>('[role="dialog"]')
      if (!panel) return
      panel.setAttribute('data-parity-id', 'stats-panel')
      const computed = getComputedStyle(panel)
      document.body.dataset.statsMaterial = JSON.stringify({
        fill: computed.backgroundColor, filter: computed.backdropFilter,
        shadow: computed.boxShadow, radius: computed.borderRadius,
        platform: document.documentElement.dataset.platform ?? 'other',
      })
    }
    tag()
    const observer = new MutationObserver(tag)
    observer.observe(document.body, {childList: true, subtree: true})
    return () => {
      observer.disconnect()
      if (previous === undefined) delete document.documentElement.dataset.platform
      else document.documentElement.dataset.platform = previous
    }
  }, [props.platform])
  const Pill = props.stat === 'usage' ? UsagePill : ActivityPill
  const injected = {
    useChat: (selector: any) => selector({legacy: {nodes: []}}),
    useProjection: (name: string) => name === 'sessionStats' ? stats : name === 'tokenUsage' ? usage : undefined,
    usePerformanceUsage: (selector: any) => selector('detailed'), t,
  }
  return <div style={{position: 'absolute', inset: 16, overflow: 'visible'}}>
    <div aria-hidden style={{position: 'absolute', inset: 0, color: 'var(--dsw-alias-label-primary)', fontSize: 14, lineHeight: '22px'}}>
      <div style={{position: 'absolute', left: 0, right: 0, top: 100, height: 44,
        background: 'var(--dsw-alias-interactive-bg-hover)'}} />
      <div style={{position: 'absolute', left: 0, right: 0, top: 188, height: 44,
        background: 'var(--dsw-specific-bubble-highlight)'}} />
      <div style={{position: 'absolute', top: 112}}>Synthetic conversation · {ctx.case.locale.startsWith('zh') ? '验证与提交' : 'Validation and delivery'}</div>
      <div style={{position: 'absolute', top: 210}}>Session projection data · 231 turns · 2901 steps</div>
    </div>
    <div style={{position: 'absolute', display: 'flex', alignItems: 'center', bottom: 0, ...(props.edge ? {right: 0} : {left: 0})}}>
      <Pill {...injected as any} />
    </div>
  </div>
}

export const kinds: Record<string, KindRenderer> = {
  'reported.stats': (props, ctx) => <Surface props={props} ctx={ctx} />,
}
