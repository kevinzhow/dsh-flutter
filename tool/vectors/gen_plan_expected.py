#!/usr/bin/env python3
"""Check plan address, review intent and Markdown summary contracts against pinned TS."""
import argparse
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
root=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('vector_environment',pathlib.Path(__file__).with_name('gen_expected.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--write',action='store_true');ap.add_argument('--check',action='store_true');ap.add_argument('fixture',type=pathlib.Path);a=ap.parse_args()
dsh,node_dir,node=m.locate()
web=pathlib.Path(os.environ.get('PARITY_WEB_DEPS',root/'.local/parity-web'))
if not (web/'node_modules/mdast-util-from-markdown').exists():sys.exit(2)
r=subprocess.run([node,str(root/'tool/vectors/ts/plan_behavior.mjs'),str(a.fixture.resolve())],cwd=root,
 env=dict(os.environ,DSH_SRC=dsh,DSH_VECTOR_NODE_DIR=node_dir,PARITY_WEB_DEPS=str(web)),capture_output=True,text=True)
if r.returncode:print(r.stderr,file=sys.stderr);sys.exit(r.returncode)
payload=json.loads(a.fixture.read_text());expected=json.loads(r.stdout)
if a.write:
 payload['expected']=expected;payload['dshCommit']=json.loads((root/'docs/upstream-sync.json').read_text())['dsh']['commit']
 a.fixture.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
elif payload.get('expected')!=expected:sys.exit('plan behavior expectations changed')
for name,part in [
 ('features/dsh_feature_user_questions/test/fixtures/plan_reviews.json','reviews'),
 ('packages/dsh_ui/test/fixtures/markdown_summaries.json','markdown')]:
 out=root/name
 derived={'format':'dsh-plan-'+part+'/1','cases':expected[part],
  'dshCommit':json.loads((root/'docs/upstream-sync.json').read_text())['dsh']['commit']}
 if a.write:
  out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(derived,ensure_ascii=False,indent=2)+'\n')
 elif json.loads(out.read_text())!=derived:sys.exit('derived plan fixture changed: '+part)
print('plan behavior: upstream addresses, intent and Markdown summaries match')
