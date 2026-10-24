// Glue that runs dsh's REAL conversation engine and chat Definitions over a
// Session's event source and projects the resulting chat snapshot to a
// language-neutral JSON shape the Dart port must reproduce exactly.
//
// REAL dsh code (loaded from DSH_SRC, nothing copied or patched):
//   ui-conversation  ConversationNodeAssembler, ConversationEventRegistry,
//                    ConversationViewRegistry, ConversationLocationIndex,
//                    inspectSystemPrompt, inspectRequestPrompt
//   ui-chat          the Definitions the Dart port covers (inbox, message,
//                    developer message, system/request prompt, assistant, tool,
//                    turn-error, turn-max-tokens, turn-tail, unknown fallback)
//                    and the Chat snapshot builder (ordering)
//   ui-plan          planDefinition (submitted-plan nodes, hidden, turn data)
//   ui-tool          the todo history Definitions and view (`tool-todo-history`)
// NOT registered (deferred to later phases, see the PR): turn-process,
// request-prompt, command, compaction, process groups.
//
// GLUE written here:
//   - a stand-in for the cordis Context (`effect` runs immediately),
//   - the BoundConversation feed loop, a copy of the loop in
//     ui-conversation/src/client/conversation/assembly.ts (replace on first
//     window, prepend / append / settle-assistant per exact delta, immediate
//     flush because node has no requestAnimationFrame),
//   - the projection below.

export async function createChatGlue(load) {
  const dir = 'packages/client/ui-conversation/src/client/'
  const chat = 'packages/client/ui-chat/src/client/conversation-nodes/'
  const { ConversationNodeAssembler } = await load(dir + 'conversation/assembler.ts')
  const { ConversationEventRegistry } = await load(dir + 'conversation/event-registry.ts')
  const { ConversationViewRegistry } = await load(dir + 'conversation/view-registry.ts')
  const { inspectSystemPrompt } = await load(dir + 'contract/system-prompt.ts')
  const { inspectRequestPrompt } = await load(dir + 'contract/request-inspection.ts')
  const { registerInboxConversationNodes } = await load(chat + 'inbox.ts')
  const { registerMessageConversationNode } = await load(chat + 'message.ts')
  const { systemMessageDefinition, requestPromptDefinition } = await load(chat + 'request-prompt.ts')
  const { registerAssistantConversationNode } = await load(chat + 'assistant.ts')
  const { registerToolConversationNode } = await load(chat + 'tool.ts')
  const { registerRetryConversationNode } = await load(chat + 'retry.ts')
  const { registerTurnErrorConversationNode } = await load(chat + 'turn-error.ts')
  const { registerTurnMaxTokensConversationNode } = await load(chat + 'turn-max-tokens.ts')
  const { registerTurnTailConversationNode } = await load(chat + 'turn-tail.ts')
  const { registerUnknownConversationFallback } = await load(chat + 'fallback.ts')
  const { registerChatConversationView } = await load(chat + 'chat-snapshot-builder.ts')
  const { planDefinition } = await load('packages/client/ui-plan/src/client/plan-definition.ts')
  const { registerTodoHistory } = await load('packages/client/ui-tool/src/client/tool/models/todo-history.ts')

  const ctx = { effect: fn => { const dispose = fn(); return () => dispose?.() } }
  const events = new ConversationEventRegistry(ctx)
  const views = new ConversationViewRegistry(ctx)
  const uiConversation = { events, views }
  const scope = { ...ctx, uiConversation }
  registerInboxConversationNodes(scope)
  registerMessageConversationNode(scope)
  events.register(systemMessageDefinition(inspectSystemPrompt))
  events.register(requestPromptDefinition(inspectRequestPrompt))
  registerAssistantConversationNode(scope)
  registerToolConversationNode(scope)
  registerRetryConversationNode(scope)
  registerTurnErrorConversationNode(scope)
  registerTurnMaxTokensConversationNode(scope)
  registerTurnTailConversationNode(scope)
  events.register(planDefinition)
  registerTodoHistory(scope)
  registerUnknownConversationFallback(scope)
  registerChatConversationView(scope)

  return {
    /** Bind the assembler to one Session event source, as BoundConversation does. */
    bind(feed) {
      const assembler = new ConversationNodeAssembler(events, views)
      let revision = -1
      const flush = () => { assembler.flush() }
      const publish = publication => { if (publication !== 'none') flush() }
      const replace = window => {
        revision = window.revision
        publish(assembler.replaceWindow(window.entries, window.hasMore))
      }
      assembler.activateTarget('chat')
      assembler.activateTarget('tool-todo-history')
      replace(feed.getSnapshot())
      const unsubscribe = feed.subscribe(() => {
        const window = feed.getSnapshot()
        if (window.revision === revision) return
        if (window.revision !== revision + 1 || window.change.kind === 'replace') { replace(window); return }
        revision = window.revision
        switch (window.change.kind) {
          case 'prepend':
            publish(assembler.prepend(window.change.entries, window.hasMore))
            return
          case 'append': {
            let publication = 'none'
            for (const event of window.change.entries) {
              const next = assembler.append(event)
              if (next === 'immediate' || publication === 'none') publication = next
            }
            publish(publication)
            return
          }
          case 'settle-assistant':
            publish(assembler.settleAssistant(window.change.attemptId, window.change.entry))
        }
      })
      return { assembler, unsubscribe, project: options => projectChat(assembler, options) }
    },
  }
}

// ---- projection ------------------------------------------------------------

const json = value => (value === undefined ? null : JSON.parse(JSON.stringify(value)))

function argsText(args) {
  // The view's own source text (its enumerable fields); reading it does not
  // register observed reads, so projecting never changes publication.
  if (args === undefined) return null
  return args.object !== undefined ? JSON.stringify(args.object) : args.chunks.join('')
}

function blockJson(block) {
  switch (block.kind) {
    case 'text': case 'reasoning': return [block.kind, block.text]
    case 'tool-call': return ['tool-call', block.callId, block.name, block.argsRaw]
    case 'image': return ['image']
    default: return ['other']
  }
}

function finalJson(node) {
  if (node === undefined) return null
  return {
    seq: node.seq,
    messageId: node.messageId ?? null,
    time: node.time,
    turn: node.turn,
    step: node.step,
    blocks: node.blocks.map(blockJson),
    usage: json(node.usage),
    interrupted: node.interrupted === true,
    stepStartTime: node.timing?.stepStartTime ?? null,
    firstTokenTime: node.timing?.firstTokenTime ?? null,
    completedTime: node.timing?.completedTime ?? null,
  }
}

function toolJson(block) {
  const base = { callId: block.callId, parentCallId: block.parentCallId ?? null, name: block.name }
  if ('kind' in block) {
    return {
      state: 'settled', ...base, args: argsText(block.args), callArgsRaw: block.call?.argsRaw ?? null,
      callTime: block.callTime ?? null, seq: block.seq, time: block.time, isError: block.isError,
      error: json(block.error), content: json(block.content), meta: json(block.meta),
      subCalls: block.subCalls.map(toolJson),
    }
  }
  if (block.phase === 'preparing') {
    return { state: 'preparing', ...base, args: argsText(block.args), turn: block.turn, step: block.step, time: block.time, subCalls: block.subCalls.map(toolJson) }
  }
  return {
    state: 'started', ...base, args: argsText(block.args), argsRaw: block.argsRaw,
    turn: block.turn, step: block.step, time: block.time, subCalls: block.subCalls.map(toolJson),
  }
}

function dataJson(node) {
  const d = node.data
  switch (node.kind) {
    case 'user': case 'steering': case 'context': case 'turn-trigger':
      return {
        kind: d.kind, seq: d.seq, time: d.time, content: json(d.content), source: json(d.source),
        messageId: d.kind === 'steering' ? d.messageId : null,
        producer: d.producer === undefined ? null : [d.producer.role, d.producer.label ?? null],
        form: d.form ?? null, waking: d.waking === true,
      }
    case 'assistant-step':
      return {
        status: d.status, turn: d.turn, step: d.step, time: d.time, blocks: d.blocks.map(blockJson),
        usage: json(d.usage), final: finalJson(d.finalNode),
      }
    case 'tool-call': return toolJson(d.root)
    case 'model-retry':
      return { attempts: d.attempts.map(a => ({
        seq: a.seq, time: a.time, retryId: a.retryId, turn: a.turn, step: a.step,
        retry: a.retry, delayMs: a.delayMs, maxRetries: a.mode === 'normal' ? a.maxRetries : null,
        failureCode: a.failure.code, failureMessage: a.failure.message, state: a.retryState,
      })) }
    case 'turn-tail':
      return { turn: d.turn, seq: d.seq, time: d.time, closingSeq: d.closing?.finalNode.seq ?? null, branchUnavailable: d.branchUnavailable }
    case 'turn-error':
      return { seq: d.seq, time: d.time, turn: d.turn, step: d.step, message: d.message, code: d.code ?? null }
    case 'turn-max-tokens': return { seq: d.seq, time: d.time, turn: d.turn, step: d.step }
    case 'unknown': return { seq: d.seq, time: d.time, type: d.type }
    default: throw new Error(`chat projection: unhandled node kind ${node.kind}`)
  }
}

function coordinates(location) {
  if (location.kind === 'step') return { turn: location.turn.turn, step: location.step.step }
  if (location.kind === 'turn') return { turn: location.turn.turn, step: null }
  return { turn: null, step: null }
}

export function projectChat(assembler, options = {}) {
  const snapshot = assembler.get('chat')
  const nodes = snapshot.order.map((key) => {
    const node = snapshot.nodes.get(key)
    return {
      kind: node.kind, id: node.id, anchorSeq: node.anchorSeq, groupTree: node.groupTree ?? null,
      location: node.location.kind, ...coordinates(node.location), data: dataJson(node),
    }
  })
  const timeline = snapshot.timeline.turnOrder.map((turn) => {
    const location = snapshot.timeline.turns.get(turn)
    return {
      turn, status: location.status, startSeq: location.start?.seq ?? null, endSeq: location.end?.seq ?? null,
      steps: location.steps.map(step => ({
        step: step.step, status: step.status, startSeq: step.start?.seq ?? null, endSeq: step.end?.seq ?? null,
      })),
    }
  })
  // Hidden plan nodes (turn data, not rows) and the todo call -> predecessor lookup.
  const plans = [...snapshot.nodes.values()]
    .filter(node => node.kind === 'submitted-plan')
    .sort((a, b) => a.anchorSeq - b.anchorSeq || (a.key < b.key ? -1 : 1))
    .map(node => ({ callId: node.data.callId, title: node.data.title, markdown: node.data.markdown, anchorSeq: node.anchorSeq, ...coordinates(node.location) }))
  const history = assembler.get('tool-todo-history')
  const todoHistory = [...history.entries()]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([callId, baseline]) => ({ callId, todos: baseline.todos === undefined ? null : baseline.todos.map(todo => [todo.content, todo.status]) }))
  return {
    nodes,
    ...(options.systemPrompts ? { systemPrompts: [...snapshot.nodes.values()]
      .filter(node => node.kind === 'system-prompt')
      .sort((a,b) => a.anchorSeq-b.anchorSeq || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
      .map(node => ({id:node.id, anchorSeq:node.anchorSeq, visible:node.visibility !== 'hidden',
        text:node.data.text, update:node.data.update === true, ...coordinates(node.location)})) } : {}),
    plans,
    todoHistory,
    timeline,
    nodeCount: snapshot.nodes.values().filter(node => node.kind !== 'system-prompt').length,
    openTurn: assembler.openTurn() ?? null,
  }
}
