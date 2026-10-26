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

// Acceptance in the actual dock surface, in addition to the row-state matrix.
import {DockSurface} from '@dsh/ui-dockkit/src/components/DockSurface.tsx'
import {DockController} from '@dsh/ui-dockkit/src/engine/controller.ts'
import {useSyncExternalStore} from 'react'
function DockScreen({props}:any){
 const [controller]=useState(()=>{const c=new DockController({makeInitialTab:id=>({id,kind:'synthetic',contentId:'synthetic-tab',title:'Synthetic tab'})});c.setExpanded(true);return c})
 const snapshot=useSyncExternalStore(controller.subscribe,controller.getSnapshot)
 useLayoutEffect(()=>{
  const tab=document.querySelector('[data-dockkit-tab]')
  tab?.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}))
  publishSettle(()=>!!document.querySelector('[data-dockkit-tab-menu]'),'actual dock surface menu')
 },[])
 const labels={emptyPane:'Empty pane',splitPane:'Split pane',splitPaneDisabled:'Pane limit',splitPaneNarrow:'Too narrow',closeTab:props.label,addTab:'Add tab',dockFloat:'Dock',closeFloat:'Close panel',dropZone:{center:'Move here',left:'Left',right:'Right',top:'Top',bottom:'Bottom'}}
 return <div style={{display:'flex',width:props.width,height:400}}><DockSurface state={snapshot.state} canSplit={snapshot.canSplit} intents={controller} labels={labels} renderTab={()=><div style={{display:'grid',height:'100%',placeItems:'center',fontSize:'var(--dsh-content-font-size, 14px)'}}>Synthetic body</div>}/></div>
}
kinds['menu-geometry.screen']=p=><DockScreen props={p}/>
