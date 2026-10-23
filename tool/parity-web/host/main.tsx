import { createRoot } from 'react-dom/client'
import './styles.ts'
import { registry } from './registry.ts'
import type { ParityContext } from './types.ts'

// Boot values of dsh's theme bootstrap (ui-theme/src/boot-theme.ts): canvas colour, the palette selector and
// the default font sizes written on <body>.
const BOOT_BACKGROUND = { light: '#fff', dark: '#151517' } as const
const FONT_SIZES = { '--dsh-content-font-size': '14px', '--dsh-code-font-size': '11px', '--dsh-terminal-font-size': '13px' }

const ctx = (window as unknown as { __PARITY__?: ParityContext }).__PARITY__
const root = document.getElementById('root')!
if (!ctx) {
  root.textContent = 'parity host: window.__PARITY__ missing (open through capture.mjs)'
} else {
  const { case: c, variant } = ctx
  const dark = c.theme === 'dark'
  document.documentElement.style.colorScheme = c.theme
  document.documentElement.dataset.dsThemeSource = c.theme
  document.documentElement.lang = c.locale
  document.body.toggleAttribute('data-ds-dark-theme', dark)
  document.body.style.backgroundColor = BOOT_BACKGROUND[c.theme]
  document.body.style.setProperty('--dsh-boot-bg', BOOT_BACKGROUND[c.theme])
  for (const [name, value] of Object.entries(FONT_SIZES)) document.body.style.setProperty(name, value)

  const render = registry[c.kind]
  if (!render) {
    root.textContent = `parity host: no renderer for kind ${c.kind}`
    document.body.dataset.parityError = `no renderer for kind ${c.kind}`
  } else {
    const { width, height } = c.viewport
    // The parity frame: the same 16px-padded, token-filled box the Flutter provider builds.
    createRoot(root).render(
      <div
        data-parity-target
        style={{
          boxSizing: 'border-box', width, height, padding: 16, overflow: 'hidden',
          background: 'var(--dsw-alias-bg-base)',
        }}
      >
        {render(variant.props, ctx)}
      </div>,
    )
  }
  document.body.dataset.parityReady = 'true'
}
