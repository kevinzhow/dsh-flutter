// dsh's General settings rows (ui-theme, ui-permission-presets, ui-settings-general), the real components with fixture state:
//
//   settings.appearance  AppearanceRow: title and the three preference cubes (ui-theme client/AppearanceRow.tsx)
//   settings.font        FontSettingsGroup: the text size row with its expander; the expanded region (three FontFamilyRow
//                        and the code and terminal FontSizeRow) is reached by clicking `font-expander`, as a user does
//   settings.permission  PermissionRow: the new-session default permission selector pill (ui-permission-presets); only the
//                        closed row exists (the Menu and the RiskConfirmation dialog are portal overlays)
//   settings.general     GeneralSection with the three rows in dsh's registered order (permission -20, appearance 10,
//                        font-size 11) inside the wrapper element ui-renderer's slot outlet emits for a list slot
//
// Host services mocked: the settings locale seats (`t`, a translator over the real `settings.theme` and
// `settings.permission` dictionaries, mocks/locale.ts), the theme and permission stores (`useStore` / `usePermission`
// are selector hooks over fixed state: `selector(state)`) and every write (no-ops).
import { useLayoutEffect, useRef } from 'react'
import { en as themeEn, zh as themeZh } from '@dsh/ui-theme/src/client/locales.ts'
import { AppearanceRow } from '@dsh/ui-theme/src/client/AppearanceRow.tsx'
import { FontSettingsGroup } from '@dsh/ui-theme/src/client/FontSettingsGroup.tsx'
import { en as permissionEn, zh as permissionZh } from '@dsh/ui-permission-presets/src/client/locales.ts'
import { PermissionRow } from '@dsh/ui-permission-presets/src/client/PermissionRow.tsx'
import { GeneralSection } from '@dsh/ui-settings-general/src/client/GeneralSection.tsx'
import { Stack } from '../../parity-web/host/layout.tsx'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import type { KindRenderer, ParityContext } from '../../parity-web/host/types.ts'
import { tagChild } from './settle.ts'

const noop = () => {}
const noopAsync = async () => {}

type Role = 'text' | 'code' | 'terminal'
const ROLES: Role[] = ['text', 'code', 'terminal']

interface PermissionState {
  status: 'idle' | 'loading' | 'ready' | 'saving' | 'unavailable' | 'error'
  error: string | null
  writable: boolean
  currentValue: string
  options: { id: string; label: string }[]
}
interface ThemeProps {
  preference: 'light' | 'dark' | 'system'
  fontSizes: Record<Role, number>
  fontFamilies: Record<Role, string>
}

const themeTranslator = (locale: string) => createTranslator(locale, { en: themeEn, zh: themeZh })
const permissionTranslator = (locale: string) => createTranslator(locale, { en: permissionEn, zh: permissionZh })

/** `useStore` of the theme rows: a selector hook over one fixed snapshot. */
function themeStore(props: ThemeProps) {
  const state = { preference: props.preference, fontSizes: props.fontSizes, fontFamilies: props.fontFamilies, revision: 1 }
  return (selector: (s: typeof state) => unknown) => selector(state)
}

/** `usePermission` of the permission row: a selector hook over one fixed snapshot. */
function permissionStore(permission: PermissionState) {
  const state = { ...permission, revision: 1 }
  return (selector: (s: typeof state) => unknown) => selector(state)
}

/**
 * Tags the real elements the interactions target and checks that the content fills the case frame. The font region
 * mounts after a click inside the rows, so a mutation observer re-tags whenever the subtree changes.
 */
function Tagged({ locale, ctx, children }: { locale: string; ctx: ParityContext; children: React.ReactNode }) {
  const height = ctx.case.viewport.height
  // The variant's own click on the expander: until the region (its text fields) exists the content is still collapsed.
  const expands = ((ctx.variant as { interactions?: { type: string; target?: string }[] }).interactions ?? [])
    .some((step) => step.type === 'click' && step.target === 'font-expander')
  const ref = useRef<HTMLDivElement>(null)
  useLayoutEffect(() => {
    const host = ref.current!
    const t = themeTranslator(locale)
    const tag = () => {
      const label = (text: string) => host.querySelector(`[aria-label="${CSS.escape(text)}"]`)
      host.querySelectorAll('button[aria-pressed]').forEach((cube, index) => tagChild(cube, `cube-${['light', 'dark', 'system'][index]}`))
      tagChild(label(t('fontSize.more')), 'font-expander')
      for (const role of ROLES) {
        tagChild(label(t(`fontSize.${role}.increase`)), `font-${role}-up`)
        tagChild(label(t(`fontSize.${role}.decrease`)), `font-${role}-down`)
        tagChild(label(t(`fontFamily.${role}.title`)), `font-${role}-family`)
      }
      tagChild(host.querySelector('button[aria-haspopup="menu"]'), 'permission-selector')
    }
    tag()
    const observer = new MutationObserver(tag)
    observer.observe(host, { childList: true, subtree: true })
    // The case frame has a fixed height (the builder encodes it from the content measured with an emulated density, where
    // every border is a whole CSS pixel): the content column must fill it to the CSS pixel the element crop rounds up to.
    // At a native density the `0.5px` separators are one device pixel (0.5 CSS px at 2x), so the same content is up to
    // half a CSS pixel per separator shorter and the frame has a little blank space under it, on both providers; a
    // shortfall below one text line is accepted there, a wrapped or missing line (and any overflow) is not. Checked on
    // every size change, so after fonts load and after the region expands; a mismatch is a console error, which fails the
    // capture with the measured height.
    const column = host.parentElement!
    const nativeDensity = () => {
      const probe = document.createElement('div')
      probe.style.cssText = 'position:absolute;visibility:hidden;border:0.5px solid'
      document.body.appendChild(probe)
      const border = parseFloat(getComputedStyle(probe).borderTopWidth)
      probe.remove()
      return window.devicePixelRatio > 1 && border < 1
    }
    const check = () => {
      if (document.fonts.status !== 'loaded') return // text still being laid out with a fallback face
      if (expands && host.querySelector('input') === null) return // the click has not expanded the region yet
      const measured = column.getBoundingClientRect().height
      const frame = height - 32
      const ok = nativeDensity() ? measured <= frame + 0.01 && measured > frame - 8 : Math.ceil(measured - 0.01) === frame
      if (!ok) {
        console.error(`parity: settings content is ${measured}px high but the case frame holds ${frame}px`)
      }
    }
    const fit = new ResizeObserver(check)
    fit.observe(column)
    document.fonts.addEventListener('loadingdone', check)
    return () => { observer.disconnect(); fit.disconnect(); document.fonts.removeEventListener('loadingdone', check) }
  }, [locale, height, expands])
  // display: contents keeps the wrapper out of layout: the rows stay direct children of the case's stack.
  return <div ref={ref} style={{ display: 'contents' }}>{children}</div>
}

function appearanceRow(props: ThemeProps, locale: string) {
  return <AppearanceRow {...{ t: themeTranslator(locale), setTheme: noop, useStore: themeStore(props) } as any} />
}

function fontRow(props: ThemeProps, locale: string) {
  return (
    <FontSettingsGroup
      {...{ t: themeTranslator(locale), setFontFamily: noop, setFontSize: noop, useStore: themeStore(props) } as any}
    />
  )
}

function permissionRow(permission: PermissionState, locale: string) {
  return (
    <PermissionRow
      {...{ t: permissionTranslator(locale), load: noopAsync, select: noopAsync, usePermission: permissionStore(permission) } as any}
    />
  )
}

export const kinds: Record<string, KindRenderer> = {
  /** props {layout, preference}; parity ids `cube-light`, `cube-dark`, `cube-system`. */
  'settings.appearance': (props, ctx) => (
    <Stack layout={props.layout}>
      <Tagged locale={ctx.case.locale} ctx={ctx}>{appearanceRow(props as ThemeProps, ctx.case.locale)}</Tagged>
    </Stack>
  ),
  /**
   * props {layout, fontSizes, fontFamilies}; parity ids `font-expander`, `font-<role>-up|down` and `font-<role>-family`
   * (the family inputs exist once the region is expanded).
   */
  'settings.font': (props, ctx) => (
    <Stack layout={props.layout}>
      <Tagged locale={ctx.case.locale} ctx={ctx}>{fontRow(props as ThemeProps, ctx.case.locale)}</Tagged>
    </Stack>
  ),
  /** props {layout, state}; parity id `permission-selector`. */
  'settings.permission': (props, ctx) => (
    <Stack layout={props.layout}>
      <Tagged locale={ctx.case.locale} ctx={ctx}>{permissionRow(props.state as PermissionState, ctx.case.locale)}</Tagged>
    </Stack>
  ),
  /**
   * props {layout, permission, preference, fontSizes, fontFamilies}: the real GeneralSection column whose
   * `settings.general.item` slot renders the three rows in registered order inside ui-renderer's list-slot anchor
   * (`<div data-slot="settings.general.item" style="display: contents">`, the element the outlet always emits, so
   * GeneralSection.module.css strips the trailing separator). All parity ids of the rows above exist.
   */
  'settings.general': (props, ctx) => {
    const locale = ctx.case.locale
    const renderSlot = () => (
      <div data-slot="settings.general.item" style={{ display: 'contents' }}>
        {permissionRow(props.permission as PermissionState, locale)}
        {appearanceRow(props as ThemeProps, locale)}
        {fontRow(props as ThemeProps, locale)}
      </div>
    )
    return (
      <Stack layout={props.layout}>
        <Tagged locale={locale} ctx={ctx}>
          <GeneralSection {...{ renderSlot } as any} />
        </Tagged>
      </Stack>
    )
  },
}
