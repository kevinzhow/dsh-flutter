import fs from 'node:fs'
import {register} from 'node:module'
import {loadDsh} from './settings_loader.mjs'
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'))
const {load}=await loadDsh({extraNodeDirs:[process.env.PARITY_WEB_DEPS,process.env.PARITY_VT_DEPS].filter(Boolean)})
register(new URL('./sidebar-sequence-loader.mjs',import.meta.url),import.meta.url)
const source=await load('packages/client/ui-sidebar-right/src/client/persistence.ts')
const storage=new Map()
globalThis.localStorage={getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)}
const accepted=input.cases.map(c=>{
 storage.set(`${source.sidebarPersistence}.synthetic`,JSON.stringify({bySession:{synthetic:c.value}}))
 return source.readSidebarLayout('synthetic')!==undefined
})
process.stdout.write(JSON.stringify({accepted}))
