// dsh's real composer overlays, mounted over fixture stores (no session, no host):
//
//   input.menu      ui-input-trigger MenuView: the candidate menu for `/` and `@`
//                     props {groups: [{source, status, items: [{name, label?, description?, icon?, section?, drill?}]}],
//                            highlight: {source, index} | null, crumbs: {source: [{label, value, current?}]} | null}
//   input.popup     ui-commands PopupSelectView: the popupSelect card of `/model`, `/permission`
//                     props {command, search, status, options: [{id, label, badge?, detail?, group?, active?}], active, error?}
//
// The menu is `position: absolute; bottom: calc(100% + 4px)` in the composer card; the host gives it a card-sized
// relative frame and the capture crops to the menu surface itself (`data-parity-id="menu"`), so the composer is not in
// the picture. Icons the commands pass as components are mapped from the same glyph keys the Flutter menu uses.
import { useLayoutEffect, useMemo, useRef } from 'react'
import { MenuView } from '@dsh/ui-input-trigger/src/client/MenuView.tsx'
import { en as menuEn, zh as menuZh } from '@dsh/ui-input-trigger/src/client/locales.ts'
import { PopupSelectView } from '@dsh/ui-commands/src/client/PopupSelectView.tsx'
import { en as commandEn, zh as commandZh } from '@dsh/ui-commands/src/client/locales.ts'
import {
  IconCompactOutlineRegular, IconDownloadOutlineRegular, IconGoalOutlineRegular, IconPaperPlaneOutlineRegular,
  IconPaperclipOutlineRegular, IconPlanOutlineRegular, IconDataOutlineRegular,
} from '@dsh/ui-primitives/src/icons/index.tsx'
import { PermissionIconFullAccessRegular } from '@dsh/ui-primitives/src/PermissionIcon.tsx'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer } from '../../parity-web/host/types.ts'

const GLYPHS: Record<string, any> = {
  goal: IconGoalOutlineRegular, plan: IconPlanOutlineRegular, feedback: IconPaperPlaneOutlineRegular,
  compact: IconCompactOutlineRegular, permission: PermissionIconFullAccessRegular, export: IconDownloadOutlineRegular,
  model: IconDataOutlineRegular, paperclip: IconPaperclipOutlineRegular,
}

const store = <T,>(value: T) => ({ getSnapshot: () => value, subscribe: () => () => {} })

function Menu({ props, locale }: { props: any; locale: string }) {
  const t = useMemo(() => createTranslator(locale, { en: menuEn, zh: menuZh }), [locale])
  const menu = useMemo(() => {
    const groups = props.groups.map((g: any) => ({
      source: g.source,
      ...(g.showGroupTitle === false ? { showGroupTitle: false } : {}),
      status: g.status ?? 'ready',
      items: g.items.map((i: any) => ({ ...i, icon: i.icon === undefined ? undefined : (GLYPHS[i.icon] ?? i.icon) })),
    }))
    return store({ open: true, hit: null, generation: 1, groups, highlight: props.highlight ?? null })
  }, [props])
  const headers = useMemo(() => store(new Map(Object.entries(props.crumbs ?? {}))), [props])
  const none = () => {}
  return (
    <div style={{ position: 'relative', width: props.width ?? 380, height: props.height ?? 440 }}>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 0 }}>
        <MenuView {...({ menu, headers, onPick: none, onHover: none, onCrumb: none, onDismiss: none, t } as any)} />
      </div>
    </div>
  )
}

function Popup({ props, locale }: { props: any; locale: string }) {
  const host = useRef<HTMLDivElement>(null)
  useLayoutEffect(() => {
    const list = host.current?.querySelector('[role="listbox"]')
    if (list) list.setAttribute('data-parity-id', 'popup-list')
  }, [props])
  const t = useMemo(() => createTranslator(locale, { en: commandEn, zh: commandZh }), [locale])
  const popup = useMemo(() => {
    const state = {
      open: true, command: props.command, status: props.status ?? 'ready', options: props.options, search: props.search ?? '',
      searchLabels: props.searchLabels ?? null, searchMode: props.searchMode ?? 'substring', active: props.active ?? 0,
      submitting: false, confirming: null, acknowledged: false, error: props.error ?? null,
    }
    const none = () => {}
    return { state: store(state), setSearch: none, move: none, highlight: none, select: none, retry: none, dismiss: none,
      acknowledge: none, cancelConfirmation: none, confirm: none }
  }, [props])
  return (
    <div ref={host} style={{ position: 'relative', width: props.width ?? 380, height: props.height ?? 360 }}>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 0 }}>
        <PopupSelectView {...({ popup, t } as any)} />
      </div>
    </div>
  )
}

export const kinds: Record<string, KindRenderer> = {
  'input.menu': (props, ctx) => <Menu props={props} locale={ctx.case.locale} />,
  'input.popup': (props, ctx) => <Popup props={props} locale={ctx.case.locale} />,
}
