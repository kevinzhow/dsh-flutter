import { useState } from 'react'
import { QueueDock } from '@dsh/ui-conversation/src/client/queue/QueueDock.tsx'
import { EnterBehaviorRow } from '@dsh/ui-conversation/src/client/settings/EnterBehaviorRow.tsx'
import { en, zh } from '@dsh/ui-conversation/src/client/locales.ts'
import { createTranslator } from '../../parity-web/host/mocks/locale.ts'
import { UserText } from '@dsh/ui-conversation/src/client/user-text/UserText.tsx'
import type { KindRenderer } from '../../parity-web/host/types.ts'

function Queue({props,ctx}: any) {
  const t=createTranslator(ctx.case.locale,{en,zh})
  const bind=(el: HTMLElement | null) => {
    const dock=el?.firstElementChild as HTMLElement | null
    // Crop the actual panel, removing only its outer attached-to-composer seat.
    if (dock) {dock.style.width='100%';dock.style.maxWidth='none';dock.style.padding='0';dock.style.margin='0'}
    dock?.firstElementChild?.setAttribute('data-parity-id','queue-panel')
    dock?.querySelector('button[aria-controls]')?.setAttribute('data-parity-id','queue-header')
    const edit=dock?.querySelector('li button')
    edit?.setAttribute('data-parity-id','queue-edit-a')
  }
  return <div style={{width:Number(props.width)}} ref={bind}><QueueDock
    useProjection={((name: string)=> name==='inbox'?{'next-turn':props.rows,'next-step':[]}:undefined) as any}
    useSession={((select:any)=>select({pendingSubmissions:props.pending??[],running:props.running??true,
      subagent:props.mutable===false?{address:{mode:'one-shot'}}:null})) as any}
    updateQueue={async()=>{}} notify={()=>{}} loadImage={async()=>''} t={t}
    renderFactorySlot={((_:string,owner:any)=><UserText {...owner}
      useUserTextRevision={((select:any)=>select(0)) as any}
      createUserTextEvaluator={()=>({text}:any)=>[{id:'text',start:0,end:text.length,data:{text,display:text.replace(/\s+/g,' ').trim()}}]}
      reportTransformFailure={()=>{}} renderSlot={((_:any,__:any,options:any)=>options.fallback) as any} {...{} as any}/>) as any} {...{} as any}/></div>
}
function Settings({props,ctx}:any) {
  const [value,setValue]=useState(props.value)
  const t=createTranslator(ctx.case.locale,{en,zh})
  const bind=(el:HTMLElement|null)=>el?.firstElementChild?.setAttribute('data-parity-id','settings-enter')
  return <div style={{width:Number(props.width)}} ref={bind}><EnterBehaviorRow useBusyEnter={((select:any)=>select(value)) as any}
    setBusyEnter={setValue} t={t} {...{} as any}/></div>
}
export const kinds:Record<string,KindRenderer>={
  'conversation.queue':(props,ctx)=><Queue props={props} ctx={ctx}/>,
  'conversation.enter-setting':(props,ctx)=><Settings props={props} ctx={ctx}/>,
}
