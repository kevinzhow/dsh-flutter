// Actual published-version primitive; whole plugin/workspace screens accompany
// this matrix, which checks the three source sizing profiles.
import {Menu} from '@dsh/ui-primitives/src/Menu.tsx'
import {IconDownloadOutlineRegular} from '@dsh/ui-primitives/src/icons/index.tsx'
import type {KindRenderer} from '../../parity-web/host/types.ts'
export const kinds:Record<string,KindRenderer>={
 'menu-family.profiles':(props)=><div style={{display:'flex'}}><Menu open anchor={<span/>} onClose={()=>{}} onSelect={()=>{}}
   dense={props.profile==='dense'} compact={props.profile==='compact'} selectedId="checked"
   items={[{type:'label',id:'heading',text:'Actions'},
    {id:'install',label:'Install package',icon:<IconDownloadOutlineRegular/>},
    {id:'checked',label:'Selected'}, {type:'separator',id:'separator'},
    {id:'off',label:'Unavailable',disabled:true},{id:'remove',label:'Remove',danger:true}]}/></div>,
}
