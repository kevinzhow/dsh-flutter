// dsh's real ConnectionIndicator (ui-primitives): the inline outage / retry / recovered control.
import { ConnectionIndicator } from '@dsh/ui-primitives/src/ConnectionIndicator.tsx'
import { Stack } from '../../parity-web/host/layout.tsx'
import type { KindRenderer } from '../../parity-web/host/types.ts'

export const kinds: Record<string, KindRenderer> = {
  'connection.indicator': (props) => (
    <Stack layout={props.layout}>
      {props.items.map((item: any) => (
        <span key={item.id} data-parity-id={item.id}>
          <ConnectionIndicator
            state={item.state}
            disconnectedLabel={props.labels.disconnected}
            connectingLabel={props.labels.connecting}
            recoveredLabel={props.labels.recovered}
            reconnectActionLabel={props.labels.reconnectAction}
            restartActionLabel={props.labels.restartAction}
            onReconnect={() => {}}
          />
        </span>
      ))}
    </Stack>
  ),
}
