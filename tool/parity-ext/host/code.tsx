// dsh's code surfaces (ui-primitives), the real components with fixture text:
//
//   code.block   CodeBlock in its card form (markdown fences, file preview): toolbar, optional line-number gutter,
//                wrapped or horizontally scrolling source (markdown/CodeBlock.tsx + CodeToolbar.tsx)
//   code.read    ReadBlock: the line-numbered file window of a read tool result, with its height cap and fold row
//
// Highlighting is dsh's real shiki highlighter (markdown/highlight.ts): the grammars load lazily, so the capture waits
// (window.__parityReady) until every block of a supported language carries coloured spans. Labels come from the real
// conversation dictionary through ui-tool's own label adapters.
import { useLayoutEffect, useRef } from 'react'
import { CodeBlock, ReadBlock } from '@deepseek-ai/dsh-client-ui-primitives'
import { supportsHighlighting } from '@dsh/ui-primitives/src/markdown/highlight.ts'
import { en, zh } from '@dsh/ui-conversation/src/client/locales.ts'
import { codeToolbarLabels, readBlockLabels } from '@dsh/ui-tool/src/client/tool/models/primitive-labels.ts'
import { Stack } from '../../parity-web/host/layout.tsx'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'
import { publishSettle, tagChild } from './settle.ts'
import './code.css'

interface BlockProps { id: string; code: string; lang?: string; lineNumbers?: boolean; wrap?: boolean }
interface ReadProps {
  label?: string; lang?: string; totalLines: number; maxLines?: number; lines: { number: number; text: string }[]
}

function highlighted(root: ParentNode, expected: number): boolean {
  return root.querySelectorAll('[style*="shiki"]').length > 0 || expected === 0
}

/** Tag the card and its toolbar actions and fold row: parity ids `code-block` / `read-block`, `code-wrap`, `code-copy`, `read-fold`. */
function Tagged({ cardId, children }: { cardId: string; children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null)
  useLayoutEffect(() => {
    const host = ref.current
    tagChild(host?.firstElementChild ?? null, cardId)
    tagChild(host?.querySelector('button[aria-pressed]') ?? null, 'code-wrap')
    tagChild(host?.querySelector('[data-code-block-banner] button:not([aria-pressed])') ?? null, 'code-copy')
    tagChild(host?.querySelector('button[aria-expanded]') ?? null, 'read-fold')
  })
  return <div ref={ref} style={{ display: 'contents' }}>{children}</div>
}

export const kinds: Record<string, KindRenderer> = {
  /** props {layout, blocks: [{id, code, lang?, lineNumbers?, wrap?}]}: `wrap` omitted keeps the block's own wrap toggle. */
  'code.block': (props, ctx) => {
    const t = createTranslator(ctx.case.locale, { en, zh })
    const blocks = props.blocks as BlockProps[]
    const expected = blocks.filter((b) => supportsHighlighting(b.lang)).length
    publishSettle(() => document.querySelectorAll('pre.shiki').length >= expected, 'code blocks highlighted')
    return (
      <Stack layout={props.layout}>
        {blocks.map((block) => (
          <Tagged key={block.id} cardId="code-block">
            <CodeBlock
              className="parity-flat-code"
              code={block.code}
              lang={block.lang}
              lineNumbers={block.lineNumbers === true}
              copyLabel={t('copy')}
              copiedLabel={t('copied')}
              toolbarLabels={codeToolbarLabels(t as any)}
              {...block.wrap === undefined ? {} : { wrap: block.wrap }}
            />
          </Tagged>
        ))}
      </Stack>
    )
  },
  /** props {layout, block: {label?, lang?, lines: [{number, text}], totalLines, maxLines?}}. */
  'code.read': (props, ctx) => {
    const t = createTranslator(ctx.case.locale, { en, zh })
    const block = props.block as ReadProps
    const expected = supportsHighlighting(block.lang) ? 1 : 0
    publishSettle(() => highlighted(document, expected), 'read block highlighted')
    return (
      <Stack layout={props.layout}>
        <Tagged cardId="read-block">
          <ReadBlock
            className="parity-flat-code"
            label={block.label}
            lang={block.lang}
            lines={block.lines}
            totalLines={block.totalLines}
            {...block.maxLines === undefined ? {} : { maxLines: block.maxLines }}
            labels={readBlockLabels(t as any)}
          />
        </Tagged>
      </Stack>
    )
  },
}
