import { useLayoutEffect, useRef, useState } from 'react'
import { TurnProcessNodeView } from '@dsh/ui-chat/src/client/chat/TurnProcessNodeView.tsx'
import { ChatGroupSeat } from '@dsh/ui-chat/src/client/chat/ChatGroupSeat.tsx'
import { TranscriptViewRow } from '@dsh/ui-chat/src/client/settings/TranscriptViewRow.tsx'
import { presentationPolicyFor } from '@dsh/ui-chat/src/client/presentation-policy.ts'
import { en, zh } from '@dsh/ui-chat/src/client/locale.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

function useFixtureGroupAction(hidden: boolean) {
  const ref = useRef<HTMLElement | null>(null)
  useLayoutEffect(() => { if (ref.current) ref.current.hidden = hidden }, [hidden])
  return ref
}

function Fixture({ props, ctx, family }: any) {
  const [open, setOpen] = useState(false)
  const [mode, setMode] = useState(props.mode ?? 'standard')
  const [timing, setTiming] = useState(props.nextInput ? 'next-input' : 'completion')
  const t = createTranslator(ctx.case.locale, { en, zh })
  const reason = props.reason ?? 'completed'
  const turn = { turn: 1, status: 'closed', start: props.partial ? undefined : {seq: 1, time: 1000},
    end: {seq: 9, time: 1000 + Number(props.elapsed ?? 5000), data: {reason: {kind: reason}}}, steps: [] }
  const spec = {turn: 1, controlAnchorSeq: 1, processStartSeq: 1, answerAnchorSeq: 8, answerStep: 2,
    inlineReasoning: false, messageCount: 1, toolCallCount: 2, subagentCount: 0}
  const control = { key: 'fixture-control', kind: 'turn-process', data: spec, location: { kind: 'turn', turn } } as any
  const bind = (el: HTMLElement | null) => el?.querySelector('button')?.setAttribute('data-parity-id', 'work-toggle')
  if (family === 'turn-process') return <div data-parity-id="work-el" style={{width: Number(props.width)}} ref={bind}>
    <TurnProcessNodeView node={control} turnProcess={{spec, open, foldable: mode !== 'verbose', hasContent: !props.empty, setOpen}} t={t} />
  </div>
  if (family === 'work-settings') {
    return <div data-parity-id="work-el" style={{width: Number(props.width)}} ref={bind}>
      <TranscriptViewRow useTranscriptView={(select: any) => select(mode)} useCollapseTiming={(select: any) => select(timing)}
        setTranscriptView={setMode} setCollapseTiming={setTiming} t={t} {...{} as any} />
    </div>
  }
  const names: string[] = props.names ?? ['read']
  const counts = new Map<string, number>()
  const category = (name: string) => name === 'read' ? 'read' : 'commands'
  names.forEach(name => counts.set(category(name), (counts.get(category(name)) ?? 0) + 1))
  const summary = { counts: [...counts].map(([kind,count]) => ({kind,count})).sort((a,b) => b.count-a.count),
    running: props.closed ? undefined : category(names.at(-1)!), runningDetail: props.closed ? '' : 'synthetic.txt', preparing: props.preparing }
  const members = names.map((_, i) => ({kind: 'node', key: `fixture-${i}`}))
  const group = {key:'fixture-group', members, data:{turn:1, closed:props.closed, summary}}
  const node = {key:'fixture-node', kind:'tool-call', anchorSeq:4, data:{}, location:{kind:'turn',turn}, groupTree: undefined}
  const policy = presentationPolicyFor('standard')
  const hook = (_: unknown, select?: (v:any)=>any) => select ? select(node) : node
  return <div data-parity-id="work-el" style={{width: Number(props.width)}} ref={bind}>
    <ChatGroupSeat groupKey="fixture-group" useChatGroup={(_:unknown,select:any)=>select(group)} useChatNode={hook}
      useChatNodeBottom={()=>false} useChatNodeProcess={()=>undefined} usePresentation={(select:any)=>select(policy)}
      useStore={(select:any)=>select({turnProcesses:[]})} actions={{setTurnProcessOpen:()=>{}}}
      useGroupAction={useFixtureGroupAction} useGroupHeaderAction={()=>{}} deferCollapse={false} t={t}
      renderSlot={()=> <div style={{fontSize:14,lineHeight:'24px'}}>Synthetic step</div>} {...{} as any} />
  </div>
}
export const kinds: Record<string, KindRenderer> = Object.fromEntries(
  ['turn-process','work-settings','process-group'].map(family => [`chat.${family}`, (props:any,ctx:any)=><Fixture props={props} ctx={ctx} family={family}/>]),
)
