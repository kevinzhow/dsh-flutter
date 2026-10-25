import {PlanChip} from '@dsh/ui-plan/src/client/PlanModeControl.tsx'
import {PlanPreview} from '@dsh/ui-plan/src/client/PlanPreview.tsx'
import {PlanReviewOpen} from '@dsh/ui-plan/src/client/PlanCard.tsx'
import {PlanReviewPanel} from '@dsh/ui-user-questions/src/client/PlanReviewPanel.tsx'
import {en,zh} from '@dsh/ui-plan/src/client/locales.ts'
import {en as questionEn,zh as questionZh} from '@dsh/ui-user-questions/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
const markdown='# **Synthetic plan**\n\nRead the synthetic files before making changes.\n\n## Verification\n\n- Inspect the fixture\n- Keep request identity'
const wait=()=>new Promise<void>(()=>{})
function Chip({props,ctx}:any){
 const t=createTranslator(ctx.case.locale,{en,zh})
 const bind=(el:HTMLElement|null)=>el?.querySelector('button')?.setAttribute('data-parity-id','plan-chip')
 return <div style={{width:props.width}}><span data-parity-id="plan-chip-surface" style={{display:'inline-block'}} ref={bind}>
  <PlanChip useProjection={(()=>props.projection??{active:true,pending:false}) as any} locked={props.locked??false}
   exitPlanMode={async()=>props.busy?wait():props.failure?'Synthetic refusal':null} t={t} {...{} as any}/>
 </span></div>
}
function Review({props,ctx}:any){
 const t=createTranslator(ctx.case.locale,{en:questionEn,zh:questionZh})
 const pt=createTranslator(ctx.case.locale,{en,zh})
 const review={id:'decision',question:'Approve synthetic plan?',plan:markdown,callId:'plan-call',approve:{label:'Start building'}}
 const pending={key:'review-fixture',snapshot:()=>({channel:'rpc'}),answer:async()=>props.busy?wait():props.failure?Promise.reject(new Error('Synthetic refusal')):undefined,dismiss:async()=>{}}
 const bind=(el:HTMLElement|null)=>{
  el?.querySelector('section')?.setAttribute('data-parity-id','plan-review-card')
  el?.querySelector('section > div:last-child button:last-child')?.setAttribute('data-parity-id','plan-review-approve')
 }
 return <div ref={bind} style={{width:props.width+64,'--dsh-composer-side-clearance':'16px'} as any}>
  <PlanReviewPanel pending={pending as any} review={review as any} t={t} renderSlot={(()=>
   <PlanReviewOpen review={review as any} requestKey="review-fixture" openReview={()=>{}} t={pt}
    useSidebarMounted={((select:any)=>select('fixture')) as any} useStore={((select:any)=>select({opened:{}})) as any}
    actions={{markOpened:()=>{}} as any} {...{} as any}/>) as any}/>
 </div>
}
function Preview({props,ctx}:any){
 const t=createTranslator(ctx.case.locale,{en,zh})
 const temporary=['temporary','expired'].includes(props.name)
 const address=temporary?'dsh-resource://plan-review/s/review':'dsh-resource://plan/s/call'
 const params=props.name==='temporary'?{planReview:{markdown,title:'Synthetic plan'}}:undefined
 const failure=props.name==='not-found'?{code:'plan/not-found',message:'not found'}:{code:'plan/read-failed',message:'Synthetic history refused'}
 return <div data-parity-id="plan-preview-surface" style={{width:props.width,height:props.height}}>
  <PlanPreview useTabInfo={(()=>({tab:{navigation:{address,params}}})) as any}
    useResource={(()=>({status:'failed',failure})) as any} t={t} {...{} as any}/></div>
}
export const kinds:Record<string,KindRenderer>={
 'plan-mode.chip':(props,ctx)=><Chip props={props} ctx={ctx}/>,
 'plan-mode.review':(props,ctx)=><Review props={props} ctx={ctx}/>,
 'plan-mode.preview':(props,ctx)=><Preview props={props} ctx={ctx}/>,
}
