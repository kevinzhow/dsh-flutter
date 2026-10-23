import type { ReactElement } from 'react'

/** A manifest case + the variant being captured, as the capture script injects them. */
export interface ParityContext {
  case: {
    id: string
    kind: string
    theme: 'light' | 'dark'
    locale: string
    viewport: { width: number; height: number; density: number }
    fixture?: unknown
  }
  variant: { id: string; name: string; props: Record<string, any> }
}

/** One renderer per `kind`; host files export `kinds` (see host/registry.ts). */
export type KindRenderer = (props: Record<string, any>, ctx: ParityContext) => ReactElement

export interface LayoutSpec {
  direction?: 'row' | 'column'
  gap?: number
  align?: 'start' | 'center' | 'end' | 'stretch'
}
