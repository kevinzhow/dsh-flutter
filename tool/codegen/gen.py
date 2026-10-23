#!/usr/bin/env python3
"""Generate the dsh protocol Dart code from the pinned dsh checkout.

  gen.py [--write]          regenerate IRs (when the dsh checkout / node install exist),
                            Dart outputs, docs/upstream-sync.json
  gen.py --check            offline staleness check from the committed IRs (fast)
  gen.py --check --full     also re-run the TypeScript extractor and compare the IR

Stdlib only. Runs from any cwd. See docs/upstream-sync.json for the pin.

Environment (all optional):
  DSH_SRC                  dsh checkout (default .local/dsh-src)
  DSH_CODEGEN_NODE_DIR     dir with node_modules/typescript (default .local/node)
  DSH_CODEGEN_NODE         node binary (default ~/.local/opt/node24/bin/node)
  DSH_CODEGEN_TMP          scratch dir for --check (default .local/codegen-check)
  DART                     dart binary (default: pinned SDK from .fvmrc under ~/flutter-sdks/versions)
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
import dart_emit  # noqa: E402
import events_ir  # noqa: E402

SYNC = REPO / "docs" / "upstream-sync.json"
IR_DIR = HERE / "ir"
SESSION_IR = IR_DIR / "session.ir.json"
EVENTS_IR = IR_DIR / "events.ir.json"
OUT_REMOTE = "packages/dsh_client/lib/src/generated/session_remote.g.dart"
OUT_EVENTS = "packages/dsh_models/lib/src/generated/session_events.g.dart"
DEFAULT_SRC = str(REPO / ".local" / "dsh-src")
DEFAULT_NODE_DIR = str(REPO / ".local" / "node")
REPO_NAME = "deepseek-ai/deepseek-harness"
PINNED_AT = "2026-10-23"
GENERATOR = "tool/codegen/gen.py"
SCHEMA_PATH = "docs/persistence-schema.json"
KNOWN_TYPES_PATH = "packages/core/session/src/known-event-types.ts"
SKIPPED_METHODS: list[str] = []  # nothing skipped; see emit_remote header


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(p: Path) -> str:
    return sha(p.read_bytes())


def dsh_src() -> Path | None:
    p = Path(os.environ.get("DSH_SRC", DEFAULT_SRC))
    return p if (p / "package.json").exists() else None


def node_dir() -> Path:
    return Path(os.environ.get("DSH_CODEGEN_NODE_DIR", DEFAULT_NODE_DIR))


def dart_bin() -> str | None:
    if os.environ.get("DART"):
        return os.environ["DART"]
    try:
        ver = json.loads((REPO / ".fvmrc").read_text())["flutter"]
        cand = Path.home() / "flutter-sdks" / "versions" / ver / "bin" / "dart"
        if cand.exists():
            return str(cand)
    except (OSError, KeyError, ValueError):
        pass
    return None


def dart_format(src: str, dart: str) -> str:
    r = subprocess.run([dart, "format", "--stdin-name", "x.dart"], input=src, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("dart format failed: " + r.stderr[:2000])
    return r.stdout


def git_pin(src: Path) -> dict:
    def g(*a: str) -> str:
        return subprocess.run(["git", "-C", str(src), *a], capture_output=True, text=True, check=True).stdout.strip()

    commit = g("rev-parse", "HEAD")
    tags = [t for t in g("tag", "--points-at", "HEAD").splitlines() if t]
    pkg = json.loads((src / "package.json").read_text())
    session_pkg = json.loads((src / "packages/api/session-controller/package.json").read_text())
    return {
        "repo": REPO_NAME,
        "commit": commit,
        "npmVersion": session_pkg.get("version", pkg.get("version")),
        "tag": tags[0] if tags else None,
        "pinnedAt": PINNED_AT,
    }


# ----------------------------------------------------------------------------
# IR production
# ----------------------------------------------------------------------------


def run_extractor(src: Path, out: Path) -> None:
    node = os.environ.get("DSH_CODEGEN_NODE", str(Path.home() / ".local/opt/node24/bin/node"))
    nd = node_dir()
    if not (nd / "node_modules" / "typescript").exists():
        raise SystemExit(f"typescript not installed under {nd}; see tool/codegen/extract/package.json (pnpm install --ignore-workspace there)")
    r = subprocess.run(
        [node, str(HERE / "extract" / "extract_session.mjs"), "--dsh", str(src), "--node-dir", str(nd), "--out", str(out)],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("extractor failed:\n" + r.stdout + r.stderr)


def build_events_ir(src: Path) -> tuple[dict, str]:
    raw = (src / SCHEMA_PATH).read_bytes()
    ir = events_ir.build(json.loads(raw), sha(raw), {})
    check_known_types(src, ir)
    return ir, sha(raw)


def check_known_types(src: Path, ir: dict) -> None:
    """Cross-check the schema's event list against known-event-types.ts."""
    p = src / KNOWN_TYPES_PATH
    if not p.exists():
        return
    body = p.read_text()
    m = re.search(r"KNOWN_SESSION_EVENT_TYPES[^=]*=\s*new Set\(\[(.*?)\]\)", body, re.S)
    ts_types = set(re.findall(r"'([^']+)'", m.group(1))) if m else set()
    schema_types = {e["type"] for e in ir["events"]}
    if ts_types != schema_types:
        raise SystemExit("persistence-schema.json and known-event-types.ts disagree: "
                         f"only in schema {sorted(schema_types - ts_types)}, only in TS {sorted(ts_types - schema_types)}")


def dump(ir: dict) -> str:
    return json.dumps(ir, indent=2, ensure_ascii=False) + "\n"


# ----------------------------------------------------------------------------
# Emission
# ----------------------------------------------------------------------------


def render_raw(meta: dict, session_ir: dict, events_ir_: dict) -> dict[str, str]:
    return {
        OUT_REMOTE: dart_emit.emit_remote(session_ir, meta, SKIPPED_METHODS),
        OUT_EVENTS: dart_emit.emit_events(events_ir_, meta),
    }


def format_all(raw: dict[str, str], dart: str) -> dict[str, str]:
    return {k: dart_format(v, dart) for k, v in raw.items()}


# ----------------------------------------------------------------------------
# upstream-sync.json
# ----------------------------------------------------------------------------


def load_sync() -> dict | None:
    return json.loads(SYNC.read_text()) if SYNC.exists() else None


def input_entries(src: Path, rels: list[str]) -> list[dict]:
    return [{"path": r, "sha256": sha_file(src / r)} for r in sorted(rels)]


def build_sync(pin: dict, session_ir: dict, events_ir_: dict, src: Path | None, old: dict | None,
               raw: dict[str, str], formatted: dict[str, str]) -> dict:
    def entry(out: str, irfile: Path, ir: dict, rels: list[str]) -> dict:
        if src is not None:
            inputs = input_entries(src, rels)
        else:
            inputs = next((g["inputs"] for g in (old or {}).get("generated", []) if g["output"] == out), [])
        return {
            "output": out,
            "generator": f"{GENERATOR} (tool/codegen/extract/extract_session.mjs + dart_emit.py)" if out == OUT_REMOTE
            else f"{GENERATOR} (tool/codegen/events_ir.py + dart_emit.py)",
            "ir": str(irfile.relative_to(REPO)),
            "irSha256": sha_file(irfile),
            "inputs": inputs,
            "rawSha256": sha(raw[out].encode()),
            "outputSha256": sha(formatted[out].encode()),
        }

    session_inputs = session_ir["inputs"]
    mine = {OUT_REMOTE, OUT_EVENTS}
    others = [g for g in (old or {}).get("generated", []) if g["output"] not in mine]
    return {
        "schemaVersion": 1,
        "dsh": pin,
        "generated": [
            entry(OUT_REMOTE, SESSION_IR, session_ir, session_inputs),
            entry(OUT_EVENTS, EVENTS_IR, events_ir_, [SCHEMA_PATH, KNOWN_TYPES_PATH]),
            *others,
        ],
    }


# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------


def cmd_write(args: argparse.Namespace) -> int:
    src = dsh_src()
    dart = dart_bin()
    if dart is None:
        raise SystemExit("pinned dart not found; set DART or install the SDK from .fvmrc")
    old = load_sync()
    if src is not None:
        pin = git_pin(src)
        if old and old["dsh"]["commit"] == pin["commit"]:
            pin["pinnedAt"] = old["dsh"].get("pinnedAt", pin["pinnedAt"])
        tmp = Path(tempfile.mkdtemp(prefix="dsh-gen-", dir=scratch_parent()))
        try:
            extracted = tmp / "session.ir.json"
            run_extractor(src, extracted)
            session_ir = json.loads(extracted.read_text())
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        events, _ = build_events_ir(src)
        IR_DIR.mkdir(parents=True, exist_ok=True)
        SESSION_IR.write_text(dump(session_ir))
        EVENTS_IR.write_text(dump(events))
    else:
        if old is None:
            raise SystemExit(f"dsh checkout not found (DSH_SRC) and no committed pin")
        print("dsh checkout not found: regenerating Dart from the committed IR only", file=sys.stderr)
        pin = old["dsh"]
        session_ir = json.loads(SESSION_IR.read_text())
        events = json.loads(EVENTS_IR.read_text())
    raw = render_raw(pin, session_ir, events)
    formatted = format_all(raw, dart)
    for out, text in formatted.items():
        p = REPO / out
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    SYNC.parent.mkdir(parents=True, exist_ok=True)
    SYNC.write_text(dump(build_sync(pin, session_ir, events, src, old, raw, formatted)))
    print(f"gen: wrote {len(formatted)} files from dsh {pin['commit'][:9]} "
          f"({len(session_ir['methods'])} session methods, {len(events['events'])} event types)")
    return 0


def scratch_parent() -> str:
    p = Path(os.environ.get("DSH_CODEGEN_TMP", str(REPO / ".local" / "codegen-check")))
    try:
        p.mkdir(parents=True, exist_ok=True)
        return str(p)
    except OSError:
        return tempfile.gettempdir()


def cmd_check(args: argparse.Namespace) -> int:
    stale: list[str] = []
    sync = load_sync()
    if sync is None:
        print("gen --check: STALE docs/upstream-sync.json missing")
        return 1
    pin = sync["dsh"]
    try:
        session_ir = json.loads(SESSION_IR.read_text())
        events = json.loads(EVENTS_IR.read_text())
    except OSError as e:
        print(f"gen --check: STALE missing IR ({e})")
        return 1
    by_out = {g["output"]: g for g in sync["generated"]}
    # 1. IR files match the recorded sha
    for out, irfile in ((OUT_REMOTE, SESSION_IR), (OUT_EVENTS, EVENTS_IR)):
        if sha_file(irfile) != by_out[out]["irSha256"]:
            stale.append(str(irfile.relative_to(REPO)) + " (IR sha differs from docs/upstream-sync.json)")
    # 2. Dart regenerated from the committed IR equals the committed files
    raw = render_raw(pin, session_ir, events)
    dart = dart_bin()
    if dart is not None and not args.no_format:
        formatted = format_all(raw, dart)
        for out, text in formatted.items():
            p = REPO / out
            if not p.exists() or p.read_text() != text:
                stale.append(out + " (differs from regeneration)")
            elif sha(text.encode()) != by_out[out]["outputSha256"]:
                stale.append(out + " (docs/upstream-sync.json outputSha256 differs)")
    else:
        for out, text in raw.items():
            if sha(text.encode()) != by_out[out]["rawSha256"]:
                stale.append(out + " (emitter output differs from recorded rawSha256)")
            p = REPO / out
            if not p.exists() or sha_file(p) != by_out[out]["outputSha256"]:
                stale.append(out + " (committed file differs from recorded outputSha256)")
    # 3. inputs vs a dsh checkout, when one is around
    src = dsh_src()
    notes = ""
    if src is not None:
        head = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        if head == pin["commit"]:
            for g in (by_out[OUT_REMOTE], by_out[OUT_EVENTS]):
                for i in g["inputs"]:
                    f = src / i["path"]
                    if not f.exists() or sha_file(f) != i["sha256"]:
                        stale.append(f"{i['path']} (input changed, rerun gen.py --write)")
        else:
            notes = " (dsh checkout is at another commit, inputs not compared)"
    else:
        notes = " (no dsh checkout, inputs not compared)"
    # 4. --full: re-run extractors and compare the IR
    if args.full:
        if src is None:
            print("gen --check --full: needs a dsh checkout (DSH_SRC)")
            return 2
        tmp = Path(tempfile.mkdtemp(prefix="dsh-full-", dir=scratch_parent()))
        try:
            ex = tmp / "session.ir.json"
            run_extractor(src, ex)
            if ex.read_text() != SESSION_IR.read_text():
                stale.append("tool/codegen/ir/session.ir.json (re-extraction differs)")
            ev, _ = build_events_ir(src)
            if dump(ev) != EVENTS_IR.read_text():
                stale.append("tool/codegen/ir/events.ir.json (rebuild differs)")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    if stale:
        print("gen --check: STALE " + str(len(stale)) + " item(s): " + "; ".join(stale))
        return 1
    mode = "full" if args.full else ("offline" if dart is None or args.no_format else "offline+format")
    print(f"gen --check: OK ({mode}) 2 files match dsh {pin['commit'][:9]}{notes}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--write", action="store_true", help="regenerate everything (default)")
    g.add_argument("--check", action="store_true", help="verify committed outputs are fresh; exit 1 if stale")
    ap.add_argument("--full", action="store_true", help="with --check: also re-run the TypeScript extractor")
    ap.add_argument("--no-format", action="store_true", help="with --check: skip dart format, compare shas only")
    args = ap.parse_args()
    return cmd_check(args) if args.check else cmd_write(args)


if __name__ == "__main__":
    sys.exit(main())
