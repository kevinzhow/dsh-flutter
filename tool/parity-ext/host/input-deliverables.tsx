import {ReferenceChip} from '@dsh/ui-primitives/src/user-text.tsx'
import {SecretText} from '@dsh/ui-secret-mask/src/client/SecretText.tsx'
import {createSecretRule} from '@dsh/ui-secret-mask/src/client/secret-rule.ts'
import {PresentedFileCard} from '@dsh/ui-deliverables/src/client/PresentedFileCard.tsx'
import {ChangedFiles} from '@dsh/ui-deliverables/src/client/ChangedFiles.tsx'
import {FileDiff} from '@dsh/ui-deliverables/src/client/FileDiff.tsx'
import {en,zh} from '@dsh/ui-deliverables/src/client/locales.ts'
import {en as secretEn,zh as secretZh} from '@dsh/ui-secret-mask/src/client/locales.ts'
import {createTranslator} from '../../parity-web/host/mocks/locale.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
import deliverCss from '@dsh/ui-deliverables/src/client/Deliverables.module.css'
const code='const report = "Synthetic report";'
const hunks=[{oldStart:1,oldLines:2,newStart:1,newLines:2,lines:[' const name = "Synthetic";','-const old = true;',`+${code}`]}]
function Surface({props,ctx,family}:any){
 const t=createTranslator(ctx.case.locale,{en,zh}),st=createTranslator(ctx.case.locale,{en:secretEn,zh:secretZh})
 let content:any
 if(family==='reference'){
  const appearance=props.name==='long'?'file':props.name
  const label=props.name==='long'?'a very long synthetic file name with multiple words.dart':props.name==='session'?'Synthetic session':props.name==='folder'?'documents':'report.dart'
  content=<div style={{fontSize:14,lineHeight:'22px',whiteSpace:'pre-wrap'}}>Read <ReferenceChip appearance={appearance} label={label} title={label} /> for this synthetic task.</div>
 }else if(family==='secret'){
  const raw=props.name==='block'?'-----BEGIN PRIVATE KEY-----\nSynthetic only\n-----END PRIVATE KEY-----':'sk-'+ 'Q7'.repeat(16)
  const node=createSecretRule().match(raw,0)!
  const bind=(el:HTMLElement|null)=>el?.querySelector('button')?.setAttribute('data-parity-id','secret-toggle')
  content=<div ref={bind} style={{fontSize:14,lineHeight:'22px',whiteSpace:'pre-wrap'}}>Use <SecretText node={node as any} raw={raw} interactive={props.name!=='readonly'} t={st} /> safely.</div>
 }else if(family==='card'){
  const phase=props.name==='ready'?undefined:props.name
  content=<div className={deliverCss.root}><PresentedFileCard file={{path:'/synthetic/report.md',description:'Synthetic report (Markdown)',seq:8,index:0}} cwd="/synthetic" phase={phase} host={{name:'Synthetic remote',available:true,fileManager:'finder'}} onPreview={()=>{}} actions={null} t={t}/></div>
 }else if(family==='changes'){
  const count=props.name==='single'?1:5
  const files=Array.from({length:count},(_,i)=>({path:`/synthetic/file${i}.dart`,display:`file${i}.dart`,added:1,deleted:i===0?1:0}))
  content=<ChangedFiles changes={{seq:7,files,total:count,added:count,deleted:1}} cwd="/synthetic" openReview={()=>{}} t={t} sessionId={'fixture' as any} useChangesDiff={((select:any)=>select({})) as any} loadChangesDiff={async()=>{}}/>
 }else{
  const state=['missing','error'].includes(props.name)?props.name:{kind:['binary','oversized'].includes(props.name)?props.name:'text',path:'/synthetic/report.dart',display:'report.dart',before:true,after:true,coarse:false,hunks}
  content=<FileDiff state={state as any} split={props.name==='split'} wrap={props.name==='wrap'} retry={()=>{}} t={t}/>
 }
 return <div data-parity-id="input-deliverables-surface" style={{width:props.width}}>{content}</div>
}
export const kinds:Record<string,KindRenderer>=Object.fromEntries(['reference','secret','card','changes','diff'].map(family=>[`input-deliverables.${family}`,(props:any,ctx:any)=><Surface props={props} ctx={ctx} family={family}/>]))
