"""Convert dsh's docs/persistence-schema.json (formatVersion 2) into the codegen IR.

The schema is a per-root node graph (object / literal / primitive / union / array /
opaque / tuple). This module expands each event root into an IR tree, names nested
objects by path, and de-duplicates structurally identical nested shapes so that a
shape shared by several events becomes one Dart class.
"""
from __future__ import annotations

import json
import re

IR_VERSION = 1
SURFACE_OP_NAME = "SessionSurfaceOp"


def pascal(s: str) -> str:
    parts = re.split(r"[^A-Za-z0-9]+", s)
    return "".join(p[:1].upper() + p[1:] for p in parts if p)


class _Conv:
    def __init__(self, nodes: list, notes: list[str], where: str):
        self.nodes = nodes
        self.notes = notes
        self.where = where

    def note(self, msg: str) -> None:
        full = f"{self.where}: {msg}"
        if full not in self.notes:
            self.notes.append(full)

    def is_json_union(self, members: list) -> bool:
        kinds = set()
        for m in members:
            if m["kind"] == "primitive":
                kinds.add(m["type"])
            elif m["kind"] == "array":
                kinds.add("array")
            elif m["kind"] == "object":
                kinds.add("object")
            elif m["kind"] == "literal":
                kinds.add("lit")
        return {"null", "number", "string", "boolean", "array", "object"} <= kinds and len(members) <= 8

    def conv(self, i: int, stack: tuple) -> dict:
        n = self.nodes[i]
        k = n["kind"]
        if i in stack:
            self.note("recursive type degraded to Object?")
            return {"k": "json"}
        stack = stack + (i,)
        if k == "primitive":
            t = n["type"]
            return {"k": {"string": "str", "number": "num", "boolean": "bool", "null": "null", "never": "never"}[t]}
        if k == "literal":
            return {"k": "lit", "v": n["value"]}
        if k == "opaque":
            self.note("opaque node (reason: %s) degraded to Object?" % n.get("reason"))
            return {"k": "json"}
        if k == "tuple":
            self.note("tuple degraded to Object?")
            return {"k": "json"}
        if k == "array":
            return {"k": "arr", "of": self.conv(n["element"], stack)}
        if k == "object":
            idx = n.get("indices") or []
            props = []
            for p in n["properties"]:
                t = self.conv(p["type"], stack)
                if t["k"] == "never":
                    continue
                props.append({"name": p["name"], "optional": bool(p["optional"]), "type": t})
            if idx and not props:
                return {"k": "rec", "of": self.conv_index(idx, stack)}
            out = {"k": "obj", "props": props}
            if idx:
                out["extras"] = self.conv_index(idx, stack)
            return out
        if k == "union":
            members = [self.nodes[t] for t in n["types"]]
            if self.is_json_union(members):
                return {"k": "json"}
            nullable = False
            rest = []
            for t in n["types"]:
                m = self.nodes[t]
                if m["kind"] == "primitive" and m["type"] == "null":
                    nullable = True
                else:
                    rest.append(t)
            bools = [t for t in rest if self.nodes[t]["kind"] == "literal" and isinstance(self.nodes[t]["value"], bool)]
            conv_members = []
            seen_bool = False
            for t in rest:
                m = self.nodes[t]
                if t in bools and len(bools) == 2:
                    if not seen_bool:
                        conv_members.append({"k": "bool"})
                        seen_bool = True
                    continue
                conv_members.append(self.conv(t, stack))
            if len(conv_members) == 1:
                ir = conv_members[0]
            elif all(m["k"] == "lit" and isinstance(m["v"], str) for m in conv_members):
                ir = {"k": "enum", "values": sorted(m["v"] for m in conv_members)}
            else:
                ir = {"k": "union", "members": sorted(conv_members, key=canon)}
            return {"k": "nullable", "of": ir} if nullable else ir
        raise ValueError("unknown node kind " + k)

    def conv_index(self, idx, stack):
        # indices: list of {key, value} style entries; only string-keyed records are used.
        first = idx[0]
        vt = first.get("type", first.get("value"))
        if isinstance(vt, int):
            return self.conv(vt, stack)
        return {"k": "json"}


def tag_of(member: dict):
    """(prop name, literal value) of an object member's discriminant, if any."""
    if member["k"] != "obj":
        return None
    lits = [p for p in member["props"] if not p["optional"] and p["type"]["k"] == "lit" and isinstance(p["type"]["v"], str)]
    for pref in ("type", "kind", "op", "mode"):
        for p in lits:
            if p["name"] == pref:
                return p["name"], p["type"]["v"]
    return (lits[0]["name"], lits[0]["type"]["v"]) if lits else None


def canon(t) -> str:
    return json.dumps(t, sort_keys=True, separators=(",", ":"))


def event_class_name(type_: str) -> str:
    return pascal(type_) + "Event"


def build(schema: dict, schema_sha: str, pin: dict) -> dict:
    notes: list[str] = []
    roots = {r["key"]: r for r in schema["roots"]}
    event_roots = sorted((r for r in schema["roots"] if r["kind"] == "event"), key=lambda r: r["key"])
    events = []
    # first pass: expand every event's data tree with path names
    occurrences: dict[str, list[tuple[str, str]]] = {}  # canon -> [(path-name, leafprop)]
    expanded = []
    for r in event_roots:
        type_ = r["key"].split(":", 1)[1]
        cls = event_class_name(type_)
        nodes = r["schema"]["nodes"]
        c = _Conv(nodes, notes, "event " + type_)
        root = c.conv(r["schema"]["root"], ())
        if root["k"] != "obj":
            raise ValueError("event root is not an object: " + type_)
        props = {p["name"]: p for p in root["props"]}
        data = props.get("data")
        extra = {}
        for name in ("surfaceOp", "sourceEventSeqs"):
            if name in props:
                extra[name] = props[name]
        expanded.append((type_, cls, r, data, extra))

    def walk(t, path, leaf, register=True):
        """Collect structure occurrences of nameable shapes (objects, unions, enums)."""
        k = t["k"]
        if k in ("obj", "union", "enum") and register:
            occurrences.setdefault(canon(t), []).append((path, leaf))
        if k == "obj":
            for p in t["props"]:
                walk(p["type"], path + pascal(p["name"]), p["name"])
            if "extras" in t:
                walk(t["extras"], path + "Value", "extras")
        elif k in ("arr", "rec"):
            walk(t["of"], path + ("Item" if k == "arr" else "Value"), leaf)
        elif k == "nullable":
            walk(t["of"], path, leaf)
        elif k == "union":
            for m in t["members"]:
                tg = tag_of(m)
                walk(m, path + (pascal(tg[1]) if tg else ""), leaf, register=False)

    for type_, cls, r, data, extra in expanded:
        if data is not None:
            walk(data["type"], cls + "Data", "data", register=False)
        for name, p in extra.items():
            walk(p["type"], cls + pascal(name), name)

    # name assignment: shortest path wins, deterministic tie-break
    names: dict[str, str] = {}
    used: set[str] = set()
    for key in sorted(occurrences, key=lambda c: (min((len(p), p) for p, _ in occurrences[c]), c)):
        occ = occurrences[key]
        paths = sorted(occ, key=lambda x: (len(x[0]), x[0]))
        name = paths[0][0].replace("Event", "", 0)
        if all(leaf == "surfaceOp" for _, leaf in occ):
            name = SURFACE_OP_NAME
        if name in used:
            i = 2
            while f"{name}{i}" in used:
                i += 1
            name = f"{name}{i}"
        used.add(name)
        names[key] = name

    decls: dict[str, dict] = {}

    def lower(t, root_name=None, register=True):
        k = t["k"]
        key = canon(t)
        if k == "obj":
            out = {"k": "obj", "props": [dict(p, type=lower(p["type"])) for p in t["props"]]}
            if "extras" in t:
                out["extras"] = lower(t["extras"])
        elif k in ("arr", "rec"):
            return {"k": k, "of": lower(t["of"])}
        elif k == "nullable":
            return {"k": "nullable", "of": lower(t["of"])}
        elif k == "union":
            out = {"k": "union", "members": [lower(m, register=False) for m in t["members"]]}
        elif k == "enum":
            out = dict(t)
        else:
            return t
        if not register:
            return out
        name = root_name or names[key]
        if name not in decls:
            decls[name] = out
        return {"k": "ref", "name": name}

    for type_, cls, r, data, extra in expanded:
        ev = {"type": type_, "className": cls, "digest": r["digest"], "surface": "surfaceOp" in extra}
        if data is not None:
            ev["data"] = lower(data["type"], cls + "Data") if data["type"]["k"] in ("obj", "union") else lower(data["type"])
        else:
            ev["data"] = None
        if "surfaceOp" in extra:
            ev["surfaceOp"] = lower(extra["surfaceOp"]["type"])
        if "sourceEventSeqs" in extra:
            ev["sourceEventSeqs"] = lower(extra["sourceEventSeqs"]["type"])
            ev["sourceEventSeqsOptional"] = extra["sourceEventSeqs"]["optional"]
        events.append(ev)

    # the generic envelope's surface op shape is shared; make sure its decl exists even if unused
    env = roots["SessionEventEnvelope"]
    return {
        "irVersion": IR_VERSION,
        "kind": "events",
        "formatVersion": schema["formatVersion"],
        "schemaSha256": schema_sha,
        "events": events,
        "decls": dict(sorted(decls.items())),
        "notes": sorted(notes),
        "envelopeDigest": env["digest"],
    }
