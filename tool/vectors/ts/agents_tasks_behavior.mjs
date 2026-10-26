import fs from 'node:fs'
import {register} from 'node:module'
import {loadDsh} from './settings_loader.mjs'
register(new URL('./ignore-css-loader.mjs',import.meta.url),import.meta.url)
process.env.TZ='UTC'
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh({extraNodeDirs:[process.env.PARITY_WEB_DEPS,process.env.PARITY_VT_DEPS].filter(Boolean)})
const timing=await load('packages/client/ui-schedule/src/client/task-timing.ts')
const cron=await load('packages/client/ui-schedule/src/client/task-cron.ts')
const detail=await load('packages/client/ui-schedule/src/client/TaskDetail.tsx')
const card=await load('packages/client/ui-schedule/src/client/schedule-create-card.ts')
const {skillReferenceRule}=await load('packages/client/ui-skill/src/client/user-text-rules.ts')
const {UserTextDocument}=await load('packages/client/ui-conversation/src/client/conversation/user-text-document.ts')
process.stdout.write(JSON.stringify({
 shapes:input.crons.map(v=>{const p=cron.parseCronExpression(v);return p===undefined?null:cron.recognizeCronShape(p)??null}),
 expressions:input.crons.map(v=>{const p=cron.parseCronExpression(v),s=p===undefined?undefined:cron.recognizeCronShape(p);return s===undefined?null:cron.cronShapeExpression(s)}),
 crons:input.crons.map(v=>cron.parseCronExpression(v)??null),
 snapshots:input.records.map(timing.timingSnapshot),
 drafts:input.records.map(timing.timingDraft),
 clocks:input.clocks.map(v=>timing.zonedWallClock(v.instant,v.zone)),
 failures:input.failures.map(timing.timingError),
 merges:input.merges.map(v=>detail.mergeRuleDraft(v.fresh,v.draft,v.stored)),
 records:input.created.map(v=>card.narrowScheduleRecord(v)??null),
 skillDocs:input.skillDocs.map(v=>new UserTextDocument().evaluate({text:v.text,facts:{skillNames:v.names}},[skillReferenceRule])),
}))
