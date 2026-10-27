// Real source consumers: the risk dialog and model input-type editor.
import {useLayoutEffect, useRef, useState} from 'react'
import {RiskConfirmation} from '@dsh/ui-primitives/src/RiskConfirmation.tsx'
import {ModelInputTypes} from '@dsh/ui-settings-models/src/client/ModelInputTypes.tsx'
import {en as modelEn, zh as modelZh} from '@dsh/ui-settings-models/src/client/locales.ts'
import {en as permissionEn, zh as permissionZh} from '@dsh/ui-permission-presets/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'

function Risk({ctx}: any) {
  const [checked, setChecked] = useState(false)
  const t = createTranslator(ctx.case.locale, {en: permissionEn, zh: permissionZh})
  useLayoutEffect(() => {
    document.querySelector('[data-modal-autofocus]')?.parentElement?.setAttribute('data-parity-id', 'risk-acknowledge')
  }, [])
  return <RiskConfirmation open title={t('confirm.title')} description={t('confirm.description')}
    acknowledgeLabel={t('confirm.acknowledge')} cancelLabel={t('confirm.cancel')}
    closeLabel={t('close')} confirmLabel={t('confirm.enable')} acknowledged={checked}
    onAcknowledgedChange={setChecked} onCancel={() => {}} onConfirm={() => {}} />
}

function Model({props, ctx}: any) {
  const ref = useRef<HTMLDivElement>(null)
  const [model, setModel] = useState({inputModalities: props.checked ? ['text', 'image'] : ['text']})
  const t = createTranslator(ctx.case.locale, {en: modelEn, zh: modelZh})
  useLayoutEffect(() => {
    const labels = ref.current?.querySelectorAll('label')
    labels?.[0]?.setAttribute('data-parity-id', 'model-text')
    labels?.[1]?.setAttribute('data-parity-id', 'model-image')
  }, [])
  return <div ref={ref} data-parity-id="model-checkbox-area" style={{width: props.width}}>
    <ModelInputTypes {...{model, field: 'inputModalities', position: 1, disabled: props.disabled, t, onChange: setModel} as any} />
  </div>
}

export const kinds: Record<string, KindRenderer> = {
  'checkbox-family.risk': (props, ctx) => <Risk props={props} ctx={ctx} />,
  'checkbox-family.model': (props, ctx) => <Model props={props} ctx={ctx} />,
}
