// Render the real source Modal/RiskConfirmation without restyling its shell.
import {useLayoutEffect, useState} from 'react'
import {RiskConfirmation} from '@dsh/ui-primitives/src/RiskConfirmation.tsx'
import {accessEn, accessZh} from '@dsh/ui-permission-presets/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'

function Risk({props, ctx}: any) {
  const [checked, setChecked] = useState(Boolean(props.checked))
  const [open, setOpen] = useState(true)
  const t = createTranslator(ctx.case.locale, {en: accessEn, zh: accessZh})
  const description = Array.from({length: Number(props.repeat ?? 1)}, () => t('confirm.description')).join(' ')

  useLayoutEffect(() => {
    const tag = () => {
      const dialog = document.querySelector<HTMLElement>('[role="dialog"]')
      if (!dialog) return
      const content = dialog.firstElementChild
      const header = content?.firstElementChild
      const body = content?.lastElementChild
      const footer = dialog.lastElementChild
      const checkbox = content?.querySelector<HTMLInputElement>('input[type="checkbox"]')
      const nodes: Record<string, Element | null | undefined> = {
        'risk-dialog': dialog,
        'risk-content': content,
        'risk-header': header,
        'risk-title': header?.querySelector('h2'),
        'risk-close': header?.querySelector('button'),
        'risk-body': body,
        'risk-warning': body?.firstElementChild,
        'risk-description': body?.querySelector('p'),
        'risk-acknowledge': checkbox?.closest('label'),
        'risk-checkbox': checkbox,
        'risk-footer': footer,
        'risk-cancel': footer?.querySelectorAll('button')[0],
        'risk-confirm': footer?.querySelectorAll('button')[1],
      }
      for (const [id, node] of Object.entries(nodes)) node?.setAttribute('data-parity-id', id)
    }
    tag()
    const observer = new MutationObserver(tag)
    observer.observe(document.body, {childList: true, subtree: true})
    return () => observer.disconnect()
  }, [open])

  const finish = (outcome: string) => {
    document.body.dataset.riskOutcome = outcome
    setOpen(false)
  }
  return <RiskConfirmation open={open} title={t('confirm.title')} description={description}
    acknowledgeLabel={t('confirm.acknowledge')} cancelLabel={t('confirm.cancel')}
    closeLabel={t('close')} confirmLabel={t('confirm.enable')} acknowledged={checked}
    disabled={Boolean(props.disabled)} onAcknowledgedChange={setChecked}
    onCancel={() => finish('cancel')} onConfirm={() => finish('confirm')} />
}

export const kinds: Record<string, KindRenderer> = {
  'headed-dialogs.risk': (props, ctx) => <Risk props={props} ctx={ctx} />,
}
