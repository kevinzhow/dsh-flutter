// Tool call blocks the way dsh's Conversation Definitions build them (ui-chat/src/client/conversation-nodes/tool.ts:
// `rootCall` for a dispatched call, `rootResult` for a settled one, a `tool-call-delta` fold for a call still
// being prepared). The block shapes are the real contract (ui-chat/src/client/contract/snapshot.ts); `args` is the real
// lazy reader, `PartialArguments` from @deepseek-ai/dsh-util-values.
import { PartialArguments } from '@deepseek-ai/dsh-util-values'

/** A fixture item of the `tool.card` kind: the same JSON feeds the React host and the Flutter widget. */
export interface ToolCardItem {
  id: string
  toolName: string
  phase: 'preparing' | 'start' | 'result'
  callId?: string
  /** JSON text of the tool arguments (a prefix of it for `preparing`). */
  argsRaw: string
  /** Only for phase `result`. */
  result?: {
    content: { type: string; [key: string]: unknown }[]
    isError?: boolean
    error?: { name: string; code: string; reason?: string } | null
    meta?: unknown
  }
  cwd?: string
  home?: string
  /** The row's initial disclosure state (default collapsed). */
  expanded?: boolean
}

// Fixed clocks: nothing on the surfaces reads them, but the blocks carry them.
const CALL_TIME = 1_700_000_000_000
const RESULT_TIME = CALL_TIME + 1_000

/** The `ToolCallBlock` of one fixture item, with the phase prop that goes with it. */
export function toolBlock(item: ToolCardItem) {
  const callId = item.callId ?? 'call-1'
  if (item.phase === 'preparing') {
    const args = new PartialArguments()
    args.append(item.argsRaw)
    args.refresh()
    return { phase: 'preparing' as const, block: { phase: 'preparing' as const, callId, name: item.toolName, turn: 1, step: 1, time: CALL_TIME, subCalls: [], args } }
  }
  const started = {
    phase: 'start' as const,
    callId,
    name: item.toolName,
    argsRaw: item.argsRaw,
    args: PartialArguments.fromText(item.argsRaw),
    turn: 1,
    step: 1,
    time: CALL_TIME,
    subCalls: [],
  }
  if (item.phase === 'start') return { phase: 'start' as const, block: started }
  const result = item.result ?? { content: [] }
  return {
    phase: 'result' as const,
    block: {
      kind: 'tool-result' as const,
      seq: 2,
      time: RESULT_TIME,
      callId,
      name: started.name,
      args: started.args,
      call: { name: started.name, argsRaw: started.argsRaw },
      callTime: started.time,
      content: result.content,
      isError: result.isError === true,
      ...(result.error == null ? {} : { error: result.error }),
      meta: result.meta,
      subCalls: [],
    },
  }
}
