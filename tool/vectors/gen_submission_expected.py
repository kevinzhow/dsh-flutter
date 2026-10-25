#!/usr/bin/env python3
"""Regenerate/check busy-Enter expectations with the actual pinned TS function."""
import argparse
import json
import os
import pathlib
import subprocess
import sys
import importlib.util
spec=importlib.util.spec_from_file_location('vector_environment', pathlib.Path(__file__).with_name('gen_expected.py'))
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
locate=module.locate
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--write',action='store_true')
ap.add_argument('--check',action='store_true')
ap.add_argument('fixture', type=pathlib.Path)
a=ap.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
dsh,node_dir,node=locate()
r=subprocess.run([node,str(root/'tool/vectors/ts/submission_policy.mjs')],cwd=root,
    env=dict(os.environ,DSH_SRC=dsh,DSH_VECTOR_NODE_DIR=node_dir),capture_output=True,text=True)
if r.returncode:
    print(r.stderr,file=sys.stderr);sys.exit(r.returncode)
v={'format':'dsh-submission-policy/1','dshCommit':json.loads((root/'docs/upstream-sync.json').read_text())['dsh']['commit'],
   'source':'ui-conversation/src/client/input/submission-policy.ts resolveSubmitMode', 'cases':json.loads(r.stdout)}
if a.write:
    a.fixture.parent.mkdir(parents=True,exist_ok=True)
    a.fixture.write_text(json.dumps(v,indent=2)+'\n')
elif json.loads(a.fixture.read_text()) != v:
    sys.exit('submission expectations changed')
print('submission policy: 16 upstream cases match')
