import { GoalCommandInputView } from '@dsh/ui-goal/src/client/GoalCommandInputView.tsx'
import { QuestionReplyBubble } from '@dsh/ui-user-questions/src/client/QuestionReplyView.tsx'
import { ContextInjectionRow } from '@dsh/ui-chat/src/client/chat/ContextInjectionRow.tsx'
import { WorkflowRunPanel } from '@dsh/ui-workflow-run/src/client/WorkflowRunPanel.tsx'
import { ReferenceChip, UserTextRun } from '@deepseek-ai/dsh-client-ui-primitives'
import { en as goalEn, zh as goalZh } from '@dsh/ui-goal/src/client/locales.ts'
import { en as questionEn, zh as questionZh } from '@dsh/ui-user-questions/src/client/locales.ts'
import { en as chatEn, zh as chatZh } from '@dsh/ui-chat/src/client/locale.ts'
import { en as workflowEn, zh as workflowZh } from '@dsh/ui-workflow-run/src/client/locales.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

const dictionaries: Record<string, any> = {
  'command-input': {en: goalEn, zh: goalZh}, 'question-reply': {en: questionEn, zh: questionZh},
  'context-injection': {en: chatEn, zh: chatZh}, 'workflow-run': {en: workflowEn, zh: workflowZh},
}

function Fixture({props, ctx, family}: any) {
  const t = createTranslator(ctx.case.locale, dictionaries[family])
  const bind = (el: HTMLElement | null) => el?.querySelector('[data-disclosure-row][role="button"], button')?.setAttribute('data-parity-id', 'node-toggle')
  const data = props.data
  let child
  if (family === 'command-input') {
    // The real view supplies the confirmed leading command fact. Its ordinary
    // user-text factory delegates to these actual primitive display components.
    child = <GoalCommandInputView node={{data} as any} t={t} renderFactorySlot={((_: string, owner: any) => <>
      <ReferenceChip appearance="command" label={owner.text.slice(0, 5)} />
      <UserTextRun text={owner.text.slice(5)} />
    </>) as any} {...{} as any} />
  } else if (family === 'question-reply') child = <QuestionReplyBubble data={data} t={t} />
  else if (family === 'context-injection') child = <ContextInjectionRow {...data} t={t} />
  else {
    const byId = Object.fromEntries(data.phases.flatMap((p: any) => p.members.map((m: any) => [m.childId, {id: m.childId, parentId: 'parent-fixture', running: m.status === 'running'}])))
    const projectionsBySession = Object.fromEntries(Object.keys(byId).map(id => [id, {values: {subagent: {mode: 'one-shot'}}}]))
    child = <WorkflowRunPanel node={{data} as any} sessionId={'parent-fixture' as any} t={t}
      useSessions={((select: any) => select({byId, projectionsBySession})) as any}
      useSessionStatus={((select: any) => select(new Map())) as any} openSession={() => {}} {...{} as any} />
  }
  return <div data-parity-id="node-el" style={{width: Number(props.width)}} ref={bind}>{child}</div>
}
export const kinds: Record<string, KindRenderer> = Object.fromEntries(
  Object.keys(dictionaries).map(family => [`chat.${family}`, (props: any, ctx: any) => <Fixture props={props} ctx={ctx} family={family} />]),
)
