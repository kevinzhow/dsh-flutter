import type { CSSProperties, ReactNode } from 'react'
import type { LayoutSpec } from './types.ts'

const ALIGN = { start: 'flex-start', center: 'center', end: 'flex-end', stretch: 'stretch' } as const

/**
 * The layout shared with the Flutter provider's `ParityStack`: a flex row/column with a fixed gap.
 * Every kind's props carry `layout` so both providers lay the same items out the same way.
 */
export function Stack({ layout, children }: { layout?: LayoutSpec; children: ReactNode }) {
  const style: CSSProperties = {
    display: 'flex',
    flexDirection: layout?.direction ?? 'row',
    gap: layout?.gap ?? 12,
    alignItems: ALIGN[layout?.align ?? 'start'],
  }
  return <div style={style}>{children}</div>
}
