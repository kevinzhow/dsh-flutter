// dsh's real question composer (ui-user-questions QuestionComposer), mounted with the host services it needs, cropped to
// the part this client ports for timed waits: the wait status and the Take time button of the card header.
//
//   question.wait   props {state: counting | paused | held | continued, seconds}
//                     counting   a running countdown (`wait.countdown`) and the Take time button
//                     paused     the countdown frozen by focus in the answer surface (`wait.paused`)
//                     held       the person took time (`wait.held`)
//                     continued  the agent went on; the question stays answerable (`wait.continued`)
//
// Mocked host services: the draft store (`useStore`, `actions`), the keyed card hook (`useQuestionCard`, over the real
// PendingQuestion carrier), `renderSlot` and the locale seat `t`. The carrier's clock is frozen (`Date.now`), so the
// countdown reads the same on every capture. The header's icon buttons (minimize, close) are hidden: the cropped element
// `.headerActions` then holds exactly the wait status and button.
import { useMemo, useSyncExternalStore } from 'react'
import { QuestionComposer } from '@dsh/ui-user-questions/src/client/QuestionComposer.tsx'
import { createWaterfallRequest, PendingQuestion } from '@dsh/ui-user-questions/src/client/contract/slots.ts'
import { en, zh } from '@dsh/ui-user-questions/src/client/locales.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

const NOW = 1_700_000_000_000
const QUESTIONS = [{
  id: 'q1', question: 'Which database?', header: 'Storage',
  options: [{ label: 'SQLite' }, { label: 'Postgres' }],
}]

function Wait({ state, seconds, locale }: { state: string; seconds: number; locale: string }) {
  const t = useMemo(() => createTranslator(locale, { en, zh }), [locale])
  const pending = useMemo(() => {
    Date.now = () => NOW // the card's own clock; every tick publishes the same remaining time
    const card = new PendingQuestion('session-1' as any, QUESTIONS as any, 'call-1' as any)
    if (state === 'continued') {
      card.attachRpc({ answer: async () => true })
      card.setState('continued')
    } else {
      card.attachWaterfall(createWaterfallRequest(NOW + seconds * 1000, undefined, () => {}).channel)
      if (state === 'paused') card.holdFocus(NOW)
      if (state === 'held') card.takeTime()
    }
    return card
  }, [state, seconds])
  const useQuestionCard = (_key: string, select: (snapshot: any) => any) =>
    select(useSyncExternalStore(pending.subscribe, pending.snapshot))
  return (
    <div
      ref={(el) => el?.querySelector('[class*="headerActions"]')?.setAttribute('data-parity-id', 'wait-actions')}
      style={{ width: 600 }}
    >
      <style>{'[data-parity-id="wait-actions"] button[aria-label] { display: none }'}</style>
      <QuestionComposer
        {...({
          matched: pending,
          t,
          useStore: (select: (state: any) => any) => select({ progressByRequest: {} }),
          useQuestionCard,
          actions: { replace: () => {}, clear: () => {}, prune: () => {} },
          renderSlot: () => null,
        } as any)}
      />
    </div>
  )
}

export const kinds: Record<string, KindRenderer> = {
  'question.wait': (props, ctx) => (
    <Wait state={props.state} seconds={props.seconds ?? 20} locale={ctx.case.locale} />
  ),
}
