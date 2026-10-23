// dsh's real tool rows and todo panel, mounted with the host mocks they need (tool/parity-web/host/mocks/).
//
//   tool.card        the real toolview row registered for each item's tool name:
//                      bash, pwsh  -> BashRow (ui-tool toolviews/bash-sample.tsx)
//                      edit, write -> FileMutationRow (file-mutation-row.tsx; the DiffBlock goes through ToolRow)
//                      read        -> ReadRow, grep/glob/web_search -> SearchRow, web_fetch -> WebRow,
//                      any other name -> GenericToolCard (the row dsh uses when no toolview claims the name)
//   plan.todo-panel  the real TodoPanel (ui-conversation skeleton/TodoPanel.tsx)
//   plan.card        the real PlanCards (ui-plan PlanCard.tsx): one card per submitted plan of a turn
//   plan.preview     the real PlanPreview (ui-plan PlanPreview.tsx): the plan's Markdown document
//
// Host services mocked (the conversation host owns them in dsh): the session store (`useSessions`), the
// per-row disclosure hook (`useDisclosure`), file opening / image loading / trajectory inspection (no-ops;
// `inspect` is omitted so no Inspect pill shows) and the locale seat `t` (a translator over the real
// dictionaries, mocks/locale.ts), plus for the plan surfaces the plan store (`usePlans`), `openPlan` and the sidebar
// tab services (`useTabInfo`, `useResource`). The block is built as the Conversation Definitions build it (mocks/tool-blocks.ts).
import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { en, zh } from '@dsh/ui-conversation/src/client/locales.ts'
import { TodoPanel } from '@dsh/ui-conversation/src/client/skeleton/TodoPanel.tsx'
import { BashRow } from '@dsh/ui-tool/src/client/tool/toolviews/bash-sample.tsx'
import { FileMutationRow } from '@dsh/ui-tool/src/client/tool/toolviews/file-mutation-row.tsx'
import { GenericToolCard } from '@dsh/ui-tool/src/client/tool/toolviews/GenericToolCard.tsx'
import { ReadRow } from '@dsh/ui-tool/src/client/tool/toolviews/read-row.tsx'
import { SearchRow } from '@dsh/ui-tool/src/client/tool/toolviews/search-row.tsx'
import { WebRow } from '@dsh/ui-tool/src/client/tool/toolviews/web-row.tsx'
import { PlanCards } from '@dsh/ui-plan/src/client/PlanCard.tsx'
import { PlanPreview } from '@dsh/ui-plan/src/client/PlanPreview.tsx'
import { en as planEn, zh as planZh } from '@dsh/ui-plan/src/client/locales.ts'
import { Stack } from '../../parity-web/host/layout.tsx'
import { createTranslator, type Translate } from '../../parity-web/host/mocks/locale.ts'
import { toolBlock, type ToolCardItem } from '../../parity-web/host/mocks/tool-blocks.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

const SESSION_ID = 'session-1'

/** Tool name -> the toolview component dsh registers for it (`tool.call.toolview`, keyed by wire name). */
const TOOLVIEWS: Record<string, (props: any) => any> = {
  bash: BashRow,
  pwsh: BashRow,
  edit: FileMutationRow,
  write: FileMutationRow,
  read: ReadRow,
  grep: SearchRow,
  glob: SearchRow,
  web_search: SearchRow,
  web_fetch: WebRow,
}

/** Mock of ui-chat's `UseDisclosure`: one independent open state per call, initially collapsed. */
function disclosureHook(initial: boolean) {
  return function useDisclosure() {
    const [expanded, setExpanded] = useState(initial)
    const toggle = useCallback(() => setExpanded((open) => !open), [])
    return { expanded, setExpanded, toggle }
  }
}

const noop = () => {}

function ToolCard({ item, t }: { item: ToolCardItem; t: Translate }) {
  const ref = useRef<HTMLDivElement>(null)
  const useDisclosure = useMemo(() => disclosureHook(item.expanded === true), [item.expanded])
  const useSessions = useMemo(() => {
    const state = { byId: { [SESSION_ID]: { cwd: item.cwd } } }
    return <T,>(select: (state: typeof state) => T) => select(state)
  }, [item.cwd])
  const { phase, block } = useMemo(() => toolBlock(item), [item])
  // The row header is the click target of an interaction: `<id>-row` is the element dsh makes the toggle
  // (role=button, present only while the row is expandable), `<id>` is the whole row incl. its body.
  useLayoutEffect(() => {
    ref.current?.querySelector('[role="button"]')?.setAttribute('data-parity-id', `${item.id}-row`)
  })
  const View = TOOLVIEWS[item.toolName] ?? GenericToolCard
  return (
    <div ref={ref} data-parity-id={item.id}>
      <View
        phase={phase}
        block={block}
        callId={item.callId ?? 'call-1'}
        toolName={item.toolName}
        sessionId={SESSION_ID}
        useSessions={useSessions}
        useDisclosure={useDisclosure}
        cwd={item.cwd}
        home={item.home}
        openFile={noop}
        loadImage={noop}
        t={t}
      />
    </div>
  )
}

export const kinds: Record<string, KindRenderer> = {
  /** props {layout, items: ToolCardItem[]}; see mocks/tool-blocks.ts for the item schema. */
  'tool.card': (props, ctx) => {
    const t = createTranslator(ctx.case.locale, { en, zh })
    return (
      <Stack layout={props.layout}>
        {(props.items as ToolCardItem[]).map((item) => <ToolCard key={item.id} item={item} t={t} />)}
      </Stack>
    )
  },
  /**
   * props {layout?, todos: [{content, status: 'pending' | 'in_progress' | 'completed'}]}. The panel starts collapsed;
   * `todo-header` is its header button. In dsh the panel sizes itself from the composer's width variables
   * (ConversationRoot.module.css); they are zeroed here so it fills the frame.
   */
  'plan.todo-panel': (props, ctx) => {
    const t = createTranslator(ctx.case.locale, { en, zh })
    return (
      <div
        data-parity-id="todo-panel"
        style={{
          '--dsh-composer-side-clearance': '0px', '--dsh-composer-dock-inset': '0px', '--dsh-composer-card-max-width': '100%',
        } as React.CSSProperties}
        ref={(el) => el?.querySelector('button')?.setAttribute('data-parity-id', 'todo-header')}
      >
        <TodoPanel todos={props.todos} t={t as any} />
      </div>
    )
  },
  /**
   * props {plans: [{callId, title, markdown}]}: the plans submitted in one turn, in order (`usePlans` mock). Each card
   * is a button; parity ids `plan-cards` (the list) and `plan-card-<callId>`.
   */
  'plan.card': (props, ctx) => {
    const t = createTranslator(ctx.case.locale, { en: planEn, zh: planZh })
    const plans = props.plans as { callId: string; title: string; markdown: string }[]
    return (
      <div
        data-parity-id="plan-cards"
        ref={(el) => el?.querySelectorAll('[data-plan-card]').forEach((card) => card.setAttribute('data-parity-id', `plan-card-${card.getAttribute('data-plan-card')}`))}
      >
        <PlanCards turn={{ turn: 1 } as any} usePlans={() => plans} openPlan={noop} t={t as any} />
      </div>
    )
  },
  /**
   * props {plan: {callId, title, markdown}}: the sidebar tab of a logged plan (`useTabInfo` and `useResource` mocks
   * answer with the plan; the pane fills the frame like the sidebar's pane does). Parity id `plan-preview`.
   */
  'plan.preview': (props, ctx) => {
    const t = createTranslator(ctx.case.locale, { en: planEn, zh: planZh })
    const plan = props.plan as { callId: string; title: string; markdown: string }
    const address = `dsh-resource://plan/${plan.callId}`
    const useTabInfo = () => ({ tab: { title: plan.title, navigation: { address, params: undefined } } })
    const useResource = () => ({ status: 'ok', value: plan, failure: undefined })
    return (
      <div data-parity-id="plan-preview" style={{ height: '100%' }}>
        <PlanPreview useTabInfo={useTabInfo as any} useResource={useResource as any} t={t as any} />
      </div>
    )
  },
}
