// Real dsh atoms with no Flutter counterpart yet: Input, Tag, Pill, Switch (ui-primitives).
import { Input } from '@dsh/ui-primitives/src/Input.tsx'
import { Pill } from '@dsh/ui-primitives/src/Pill.tsx'
import { Switch } from '@dsh/ui-primitives/src/Switch.tsx'
import { Tag } from '@dsh/ui-primitives/src/Tag.tsx'
import { Stack } from '../../parity-web/host/layout.tsx'
import type { KindRenderer } from '../../parity-web/host/types.ts'

export const kinds: Record<string, KindRenderer> = {
  'input.fields': (props) => (
    <Stack layout={props.layout}>
      {props.items.map((item: any) => (
        // uncontrolled (defaultValue): the host never changes the value after mount
        <Input key={item.id} data-parity-id={item.id} placeholder={item.placeholder} defaultValue={item.value} disabled={item.disabled} />
      ))}
    </Stack>
  ),
  'tag.items': (props) => (
    <Stack layout={props.layout}>
      {props.items.map((item: any) => <span key={item.id} data-parity-id={item.id}><Tag tone={item.tone}>{item.label}</Tag></span>)}
    </Stack>
  ),
  'pill.items': (props) => (
    <Stack layout={props.layout}>
      {props.items.map((item: any) => (
        <Pill key={item.id} data-parity-id={item.id} active={item.active} onClick={item.interactive ? () => {} : undefined}>{item.label}</Pill>
      ))}
    </Stack>
  ),
  'switch.items': (props) => (
    <Stack layout={props.layout}>
      {props.items.map((item: any) => (
        <span key={item.id} data-parity-id={item.id}><Switch checked={item.checked} onChange={() => {}} label={item.label} disabled={item.disabled} /></span>
      ))}
    </Stack>
  ),
}
