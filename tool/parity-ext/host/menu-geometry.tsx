import {useLayoutEffect,useRef,useState} from 'react'
import {TabMenu} from '@dsh/ui-dockkit/src/components/TabMenu.tsx'
import {publishSettle} from './settle.ts'
import type {KindRenderer} from '../../parity-web/host/types.ts'
function DockMenu({props}:any){
 const ref=useRef<HTMLButtonElement>(null),[anchor,setAnchor]=useState<HTMLButtonElement|null>(null)
 useLayoutEffect(()=>{setAnchor(ref.current);publishSettle(()=>!!document.querySelector('[data-dockkit-menu-close]'),'dock menu')},[])
 useLayoutEffect(()=>{document.querySelector('[data-dockkit-menu-close]')?.setAttribute('data-parity-id','dock-menu-close')},[anchor])
 return <><button ref={ref} style={{display:'block',width:120,height:28,padding:0,border:0}}>Synthetic tab</button>
  {anchor&&<TabMenu labels={{closeTab:props.label} as any} anchor={anchor} onClose={()=>{}} onDismiss={()=>{}} extras={null}/>}</>
}
export const kinds:Record<string,KindRenderer>={'menu-geometry.dock':p=><DockMenu props={p}/>}
