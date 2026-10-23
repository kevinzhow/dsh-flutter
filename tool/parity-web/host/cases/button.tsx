// dsh's real Button atom (packages/client/ui-primitives/src/Button.tsx).
import { Button } from '@dsh/ui-primitives/src/Button.tsx'
import { Stack } from '../layout.tsx'
import type { KindRenderer } from '../types.ts'

interface ButtonItem {
  id: string
  label: string
  variant?: 'primary' | 'ghost' | 'outline' | 'toolbar'
  size?: 'md' | 'sm'
  disabled?: boolean
}

/** `button.items`: a row/column of buttons; props {layout, items:[{id,label,variant,size,disabled}]}. */
export const kinds: Record<string, KindRenderer> = {
  'button.items': (props) => (
    <Stack layout={props.layout}>
      {(props.items as ButtonItem[]).map((item) => (
        <Button
          key={item.id}
          data-parity-id={item.id}
          variant={item.variant}
          size={item.size}
          disabled={item.disabled}
        >
          {item.label}
        </Button>
      ))}
    </Stack>
  ),
}
