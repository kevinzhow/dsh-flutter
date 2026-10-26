#!/usr/bin/env python3
"""Check exact pinned turn deliverables, canonical paths and closing file mentions."""
import argparse,importlib.util,json,os,pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('vector_environment',pathlib.Path(__file__).with_name('gen_expected.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--write',action='store_true');ap.add_argument('--check',action='store_true');ap.add_argument('fixture',type=pathlib.Path);a=ap.parse_args()
dsh,node_dir,node=m.locate()
r=subprocess.run([node,str(root/'tool/vectors/ts/agents_tasks_behavior.mjs'),str(a.fixture.resolve())],cwd=root,env=dict(os.environ,DSH_SRC=dsh,DSH_VECTOR_NODE_DIR=node_dir),capture_output=True,text=True)
if r.returncode:print(r.stderr,file=sys.stderr);sys.exit(r.returncode)
payload=json.loads(a.fixture.read_text());expected=json.loads(r.stdout)
if a.write:
 payload['expected']=expected;payload['dshCommit']=json.loads((root/'docs/upstream-sync.json').read_text())['dsh']['commit'];a.fixture.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
elif payload.get('expected')!=expected:sys.exit('agents/tasks expectations changed')
print('agents/tasks: pinned schedule/Skill policies match upstream')
