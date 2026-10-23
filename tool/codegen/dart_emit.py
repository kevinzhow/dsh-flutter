"""IR -> Dart emitter (plain string generation, no build_runner).

Both IRs (session Remote namespace, session events) share one type model:
  str num bool null json void lit enum arr rec nullable ref obj union
Output conventions:
  * immutable final classes with `fromJson` (strict on missing/mistyped required
    fields, FormatException naming the JSON path; unknown extra fields ignored) and `toJson`
  * discriminated unions -> sealed classes with an `...Unknown` member holding raw JSON
  * string-literal unions -> open string "enums" (final class with const values and
    an unknown fallback that keeps the raw string)
  * required single-value literal props (`type: 'x'`, `accepted: true`) are class
    constants: validated on decode, written on encode, not stored as fields.
"""
from __future__ import annotations

import json
import re
import textwrap
from dataclasses import dataclass, field

RESERVED = {
    "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum",
    "extends", "false", "final", "finally", "for", "if", "in", "is", "new", "null", "rethrow", "return",
    "super", "switch", "this", "throw", "true", "try", "var", "void", "while", "with", "abstract", "as",
    "dynamic", "export", "extension", "external", "factory", "get", "implements", "import", "interface",
    "library", "mixin", "operator", "part", "required", "set", "static", "typedef", "late", "covariant",
    "hashCode", "runtimeType", "toString", "toJson", "noSuchMethod",
}

FIELD_RENAMES = {
    ("NativeFileApplication", "default"): "isDefault",
    ("ModelCatalog", "default"): "defaultSelection",
}

# `number` -> int only for names that are always integral on the wire; everything else stays `num`.
INT_NAME = re.compile(
    r"^(seq|time|index|turn|step|version|revision|round|bytes|width|height|cursor|start|end|offset|exitCode|"
    r"maxRetries|retry|attempt|delegationDepth|.*Seqs?|.*Index(es)?|.*At|.*Tokens?|.*Count|.*FormatVersion|"
    r"max[A-Z].*|min[A-Z].*|.*Messages|.*Images)$"
)


def pascal(s: str) -> str:
    parts = re.split(r"[^A-Za-z0-9]+", s)
    return "".join(p[:1].upper() + p[1:] for p in parts if p)


def camel(s: str) -> str:
    p = pascal(s)
    if not p:
        return "v"
    out = p[:1].lower() + p[1:]
    if out[0].isdigit():
        out = "v" + out
    return out


def q(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$").replace("\n", "\\n") + "'"


def doc_lines(text: str | None, indent: str = "") -> list[str]:
    if not text:
        return []
    text = re.sub(r"\{@link ([^}]+)\}", r"\1", text)
    return [f"{indent}/// {ln}" for ln in textwrap.wrap(text, 76 - len(indent), break_long_words=False, break_on_hyphens=False)]


@dataclass
class T:
    base: str  # Dart type without nullability
    dec: str  # expression of type `base Function(Object?, String)`
    enc: str  # template with {} for the expression, or "{}" for identity
    nullable: bool = False
    enc_inner: str | None = None  # encoder for a known non-null value (== enc unless nullable)

    @property
    def dart(self) -> str:
        return self.base + ("?" if self.nullable else "")

    def enc_expr(self, e: str) -> str:
        return self.enc.replace("{}", e)

    def enc_nn(self, e: str) -> str:
        return (self.enc_inner or self.enc).replace("{}", e)


def nullable_dart(base: str) -> str:
    return base if base.endswith("?") else base + "?"


def field_dart(f) -> str:
    return nullable_dart(f.t.base) if (f.optional or f.t.nullable) else f.t.base


@dataclass
class Field:
    json: str
    name: str
    t: T
    optional: bool
    doc: str | None = None


@dataclass
class Cls:
    name: str
    doc: str | None
    fields: list = field(default_factory=list)
    consts: list = field(default_factory=list)  # (json key, python value)
    extras: bool = False
    implements: list = field(default_factory=list)


@dataclass
class Member:
    cls: str
    tag: str  # tag value
    lit: bool  # bare-string member


@dataclass
class Sealed:
    name: str
    doc: str | None
    tag: str | None  # discriminant json key (None if only literal members)
    members: list = field(default_factory=list)
    unknown: str = ""


@dataclass
class EnumC:
    name: str
    doc: str | None
    values: list = field(default_factory=list)


class Emitter:
    def __init__(self, decls: dict, namespace_hint: str = ""):
        self.decls = decls
        self.classes: dict[str, Cls | Sealed | EnumC] = {}
        self.order: list[str] = []
        self.notes: list[str] = []
        self.pending_impl: dict[str, list[str]] = {}
        self.done_decl: dict[str, T] = {}
        self.taken: set[str] = set(decls)

    # ---- naming ---------------------------------------------------------
    def claim(self, name: str) -> str:
        if name not in self.taken:
            self.taken.add(name)
            return name
        i = 2
        while f"{name}{i}" in self.taken:
            i += 1
        self.taken.add(f"{name}{i}")
        return f"{name}{i}"

    def note(self, msg: str) -> None:
        if msg not in self.notes:
            self.notes.append(msg)

    def add(self, model) -> None:
        if model.name in self.classes:
            raise ValueError("duplicate class " + model.name)
        self.classes[model.name] = model
        self.order.append(model.name)

    # ---- type lowering ---------------------------------------------------
    def resolve(self, t: dict) -> dict:
        while t["k"] == "ref" and self.decls[t["name"]]["k"] in ("ref",):
            t = self.decls[t["name"]]
        return t

    def lower(self, t: dict, hint: str, leaf: str = "") -> T:
        k = t["k"]
        if k == "str":
            return T("String", "_str", "{}")
        if k == "num":
            if INT_NAME.match(leaf):
                return T("int", "_int", "{}")
            return T("num", "_num", "{}")
        if k == "bool":
            return T("bool", "_bool", "{}")
        if k in ("json", "null", "never", "undefined"):
            return T("Object?", "_json", "{}")
        if k == "void":
            return T("void", "_json", "{}")
        if k == "lit":
            v = t["v"]
            if isinstance(v, bool):
                return T("bool", "_bool", "{}")
            if isinstance(v, str):
                return T("String", "_str", "{}")
            return T("int", "_int", "{}")
        if k == "arr":
            inner = self.lower(t["of"], hint + "Item", leaf)
            return T(f"List<{inner.dart}>", f"_listOf({inner.dec})", "[for (final e in {}) " + inner.enc_expr("e") + "]")
        if k == "rec":
            inner = self.lower(t["of"], hint + "Value", leaf)
            return T(f"Map<String, {inner.dart}>", f"_mapOf({inner.dec})",
                     "{for (final e in {}.entries) e.key: " + inner.enc_expr("e.value") + "}")
        if k == "nullable":
            inner = self.lower(t["of"], hint, leaf)
            if inner.nullable:
                return inner
            return T(inner.base, f"_nullable({inner.dec})",
                     "switch ({}) { final v? => " + inner.enc_expr("v") + ", _ => null }", True, inner.enc)
        if k == "ref":
            return self.lower_ref(t["name"])
        if k == "enum":
            name = self.claim(hint)
            return self.make_enum(name, t)
        if k == "obj":
            name = self.claim(hint)
            return self.make_obj(name, t, None)
        if k == "union":
            name = self.claim(hint)
            return self.make_union(name, t, None)
        raise ValueError(f"cannot lower {k}")

    def lower_ref(self, name: str) -> T:
        if name in self.done_decl:
            return self.done_decl[name]
        d = self.decls[name]
        k = d["k"]
        if k == "obj":
            # register a provisional T first: recursive refs resolve to the class
            self.done_decl[name] = self.class_t(name, d)
            return self.make_obj(name, d, d.get("doc"), provisional=True)
        if k == "enum":
            self.done_decl[name] = T(name, f"{name}.fromJson", "{}.toJson()")
            return self.make_enum(name, d)
        if k == "union":
            self.done_decl[name] = T(name, f"{name}.fromJson", "{}.toJson()")
            return self.make_union(name, d, d.get("doc"), provisional=True)
        t = self.lower(d, name)
        self.done_decl[name] = t
        return t

    def class_t(self, name: str, d: dict) -> T:
        return T(name, f"{name}.fromJson", "{}.toJson()")

    # ---- builders -----------------------------------------------------------
    def make_enum(self, name: str, t: dict, provisional: bool = False) -> T:
        if name not in self.classes:
            self.add(EnumC(name, t.get("doc"), list(t["values"])))
        self.done_decl[name] = T(name, f"{name}.fromJson", "{}.toJson()")
        return self.done_decl[name]

    def literal_consts(self, props: list[dict]):
        consts, rest = [], []
        for p in props:
            ty = p["type"]
            if not p["optional"] and ty["k"] == "lit":
                consts.append((p["name"], ty["v"]))
            else:
                rest.append(p)
        return consts, rest

    def make_obj(self, name: str, t: dict, doc: str | None, provisional: bool = False) -> T:
        res = T(name, f"{name}.fromJson", "{}.toJson()")
        if name in self.classes:
            return res
        self.done_decl[name] = res
        consts, rest = self.literal_consts(t["props"])
        cls = Cls(name, doc if doc is not None else t.get("doc"))
        cls.consts = consts
        self.add(cls)
        used: set[str] = set()
        for p in rest:
            fname = FIELD_RENAMES.get((name, p["name"])) or camel(p["name"])
            if fname in RESERVED:
                fname += "_"
            while fname in used:
                fname += "_"
            used.add(fname)
            ft = self.lower(p["type"], name + pascal(p["name"]), p["name"])
            cls.fields.append(Field(p["name"], fname, ft, p["optional"], p.get("doc")))
        if "extras" in t and cls.fields:
            cls.extras = True
        elif "extras" in t and not cls.fields and not cls.consts:
            pass
        return res

    def tag_of(self, m: dict):
        """Discriminant candidates of an object member: {prop: literal}."""
        m = self.deref(m)
        if m["k"] != "obj":
            return None
        return {p["name"]: p["type"]["v"] for p in m["props"]
                if not p["optional"] and p["type"]["k"] == "lit" and isinstance(p["type"]["v"], str)}

    def deref(self, m: dict) -> dict:
        while m["k"] == "ref":
            m = self.decls[m["name"]]
        return m

    def make_union(self, name: str, t: dict, doc: str | None, provisional: bool = False) -> T:
        res = T(name, f"{name}.fromJson", "{}.toJson()")
        if name in self.classes:
            return res
        members = t["members"]
        lits = [m for m in members if m["k"] == "lit" and isinstance(m["v"], str)]
        objs = [m for m in members if self.deref(m)["k"] == "obj"]
        others = [m for m in members if m not in lits and m not in objs]
        tag = None
        if not others and (lits or objs) and len(lits) + len(objs) == len(members):
            cands = None
            for m in objs:
                tags = set(self.tag_of(m).keys())
                cands = tags if cands is None else cands & tags
            if objs and not cands:
                tag = None
                ok = False
            else:
                ok = True
                if objs:
                    for pref in ("type", "kind", "op", "mode"):
                        if pref in cands:
                            tag = pref
                            break
                    else:
                        tag = sorted(cands)[0]
                    values = [self.tag_of(m)[tag] for m in objs] + [m["v"] for m in lits]
                    ok = len(set(values)) == len(values)
            if ok:
                self.done_decl[name] = res
                sealed = Sealed(name, doc if doc is not None else t.get("doc"), tag, unknown=self.claim(name + "Unrecognized"))
                self.add(sealed)
                for m in members:
                    if m["k"] == "lit":
                        cname = self.claim(name + pascal(m["v"]))
                        self.add(Cls(cname, None, consts=[], implements=[name]))
                        self.classes[cname].lit_value = m["v"]  # type: ignore[attr-defined]
                        sealed.members.append(Member(cname, m["v"], True))
                    elif m["k"] == "ref":
                        ref_t = self.lower_ref(m["name"])
                        self.classes[m["name"]].implements.append(name)
                        sealed.members.append(Member(m["name"], self.tag_of(m)[tag], False))
                    else:
                        tv = self.tag_of(m)[tag]
                        cname = self.claim(name + pascal(tv))
                        self.make_obj(cname, m, None)
                        self.classes[cname].implements.append(name)
                        sealed.members.append(Member(cname, tv, False))
                return res
        # fallbacks
        if not others and objs and len(objs) == len(members):
            self.note(f"{name}: union without a unique discriminant merged into one class (props optional unless in every member)")
            merged = self.merge_objs([self.deref(m) for m in members])
            return self.make_obj(name, merged, doc if doc is not None else t.get("doc"))
        self.note(f"{name}: heterogeneous union degraded to Object?")
        self.done_decl[name] = T("Object?", "_json", "{}")
        return self.done_decl[name]

    def merge_objs(self, objs: list[dict]) -> dict:
        names: list[str] = []
        for o in objs:
            for p in o["props"]:
                if p["name"] not in names:
                    names.append(p["name"])
        props = []
        for n in sorted(names):
            seen = [next((p for p in o["props"] if p["name"] == n), None) for o in objs]
            present = [p for p in seen if p is not None]
            types = {json.dumps(p["type"], sort_keys=True) for p in present}
            optional = any(p is None or p["optional"] for p in seen)
            if len(types) == 1:
                ty = present[0]["type"]
            elif all(p["type"]["k"] == "lit" for p in present):
                vals = {p["type"]["v"] for p in present}
                if all(isinstance(v, bool) for v in vals):
                    ty = {"k": "bool"}
                elif all(isinstance(v, str) for v in vals):
                    ty = {"k": "enum", "values": sorted(vals)}
                else:
                    ty = {"k": "num"}
            else:
                ty = {"k": "json"}
            props.append({"name": n, "optional": optional, "type": ty})
        return {"k": "obj", "props": props}

    # ---- rendering ---------------------------------------------------------
    def render_all(self) -> str:
        out: list[str] = []
        for name in sorted(self.classes):
            m = self.classes[name]
            if isinstance(m, EnumC):
                out.append(self.render_enum(m))
            elif isinstance(m, Sealed):
                out.append(self.render_sealed(m))
            else:
                out.append(self.render_cls(m))
        return "\n".join(out)

    def render_enum(self, e: EnumC) -> str:
        names: list[str] = []
        for v in e.values:
            n = camel(v)
            if n in RESERVED or n in ("values", "value", "isKnown", "fromJson", "toJson"):
                n += "_"
            while n in names:
                n += "_"
            names.append(n)
        L = doc_lines(e.doc)
        L.append(f"final class {e.name} {{")
        L.append(f"  const {e.name}._(this.value);")
        L.append(f"  /// Wraps a value this generation does not know; kept verbatim.")
        L.append(f"  const {e.name}.unrecognized(this.value);")
        for n, v in zip(names, e.values):
            L.append(f"  static const {n} = {e.name}._({q(v)});")
        L.append(f"  static const List<{e.name}> values = [{', '.join(names)}];")
        L.append("  final String value;")
        L.append("  bool get isKnown => values.any((v) => v.value == value);")
        L.append(f"  factory {e.name}.fromJson(Object? json, [String path = r'$']) {{")
        L.append("    final s = _str(json, path);")
        L.append(f"    for (final v in values) {{ if (v.value == s) return v; }}")
        L.append(f"    return {e.name}.unrecognized(s);")
        L.append("  }")
        L.append("  String toJson() => value;")
        L.append("  @override")
        L.append(f"  bool operator ==(Object other) => other is {e.name} && other.value == value;")
        L.append("  @override")
        L.append("  int get hashCode => value.hashCode;")
        L.append("  @override")
        L.append(f"  String toString() => '{e.name}($value)';")
        L.append("}")
        L.append("")
        return "\n".join(L)

    def render_sealed(self, s: Sealed) -> str:
        has_lit = any(m.lit for m in s.members)
        ret = "Object?" if has_lit else "Map<String, Object?>"
        L = doc_lines(s.doc)
        L.append(f"sealed class {s.name} {{")
        L.append(f"  const {s.name}();")
        L.append(f"  factory {s.name}.fromJson(Object? json, [String path = r'$']) {{")
        for m in s.members:
            if m.lit:
                L.append(f"    if (json == {q(m.tag)}) return const {m.cls}();")
        if s.tag is not None:
            L.append("    final m = _obj(json, path);")
            L.append(f"    return switch (m[{q(s.tag)}]) {{")
            for m in s.members:
                if not m.lit:
                    L.append(f"      {q(m.tag)} => {m.cls}.fromJson(m, path),")
            L.append(f"      _ => {s.unknown}(m),")
            L.append("    };")
        else:
            L.append(f"    throw FormatException('$path: unknown {s.name} value $json');")
        L.append("  }")
        L.append(f"  {ret} toJson();")
        L.append("}")
        L.append("")
        L.append(f"/// A {s.name} variant this generation does not know; raw JSON is kept.")
        L.append(f"final class {s.unknown} implements {s.name} {{")
        L.append(f"  const {s.unknown}(this.raw);")
        L.append("  final Map<String, Object?> raw;")
        L.append("  @override")
        L.append(f"  {ret} toJson() => raw;")
        L.append("}")
        L.append("")
        return "\n".join(L)

    def render_cls(self, c: Cls) -> str:
        L = doc_lines(c.doc)
        impl = f" implements {', '.join(sorted(set(c.implements)))}" if c.implements else ""
        L.append(f"final class {c.name}{impl} {{")
        lit = getattr(c, "lit_value", None)
        if lit is not None:
            L.append(f"  const {c.name}();")
            L.append("  @override")
            L.append(f"  Object? toJson() => {q(lit)};")
            L.append("}")
            L.append("")
            return "\n".join(L)
        # constructor
        params = []
        for f in c.fields:
            if f.optional:
                params.append(f"this.{f.name}")
            else:
                params.append(f"required this.{f.name}")
        if c.extras:
            params.append("this.extra = const {}")
        if params:
            L.append(f"  const {c.name}({{{', '.join(params)}}});")
        else:
            L.append(f"  const {c.name}();")
        # fromJson
        L.append(f"  factory {c.name}.fromJson(Object? json, [String path = r'$']) {{")
        if c.fields or c.consts or c.extras:
            L.append("    final m = _obj(json, path);")
        else:
            L.append("    _obj(json, path);")
        for k, v in c.consts:
            L.append(f"    _expect(m, {q(k)}, {self.lit(v)}, path);")
        if c.fields or c.extras:
            L.append(f"    return {c.name}(")
            for f in c.fields:
                fn = "_opt" if f.optional else "_req"
                L.append(f"      {f.name}: {fn}<{f.t.dart}>(m, {q(f.json)}, path, {f.t.dec}),")
            if c.extras:
                keys = ", ".join(q(f.json) for f in c.fields)
                L.append(f"      extra: _rest(m, const {{{keys}}}),")
            L.append("    );")
        else:
            L.append(f"    return const {c.name}();")
        L.append("  }")
        for f in c.fields:
            L.extend(doc_lines(f.doc, "  "))
            L.append(f"  final {field_dart(f)} {f.name};")
        if c.extras:
            L.append("  /// Keys this generation does not model, kept verbatim.")
            L.append("  final Map<String, Object?> extra;")
        if c.implements:
            L.append("  @override")
        ret = "Map<String, Object?>"
        L.append(f"  {ret} toJson() => {{")
        if c.extras:
            L.append("    ...extra,")
        for k, v in c.consts:
            L.append(f"    {q(k)}: {self.lit(v)},")
        for f in c.fields:
            if f.optional:
                L.append(f"    if ({f.name} case final v?) {q(f.json)}: {f.t.enc_nn('v')},")
            else:
                L.append(f"    {q(f.json)}: {f.t.enc_expr(f.name)},")
        L.append("  };")
        L.append("}")
        L.append("")
        return "\n".join(L)

    @staticmethod
    def lit(v) -> str:
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, str):
            return q(v)
        return str(v)


HELPERS = r"""
// ---- runtime helpers (private to this generated file) -----------------------

typedef _Dec<T> = T Function(Object?, String);

Map<String, Object?> _obj(Object? v, String path) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw FormatException('$path: expected a JSON object, got ${_kind(v)}');
}

String _kind(Object? v) => v == null ? 'null' : v.runtimeType.toString();

String _str(Object? v, String path) {
  if (v is String) return v;
  throw FormatException('$path: expected a string, got ${_kind(v)}');
}

bool _bool(Object? v, String path) {
  if (v is bool) return v;
  throw FormatException('$path: expected a boolean, got ${_kind(v)}');
}

num _num(Object? v, String path) {
  if (v is num) return v;
  throw FormatException('$path: expected a number, got ${_kind(v)}');
}

int _int(Object? v, String path) {
  if (v is int) return v;
  if (v is double && v == v.truncateToDouble() && v.isFinite) return v.toInt();
  throw FormatException('$path: expected an integer, got ${_kind(v)}');
}

Object? _json(Object? v, String path) => v;

_Dec<T?> _nullable<T>(_Dec<T> d) => (v, p) => v == null ? null : d(v, p);

_Dec<List<T>> _listOf<T>(_Dec<T> d) => (v, p) {
  if (v is! List) {
    throw FormatException('$p: expected a JSON array, got ${_kind(v)}');
  }
  return List<T>.unmodifiable([
    for (var i = 0; i < v.length; i++) d(v[i], '$p[$i]'),
  ]);
};

_Dec<Map<String, T>> _mapOf<T>(_Dec<T> d) => (v, p) {
  final m = _obj(v, p);
  return Map<String, T>.unmodifiable({
    for (final e in m.entries) e.key: d(e.value, '$p.${e.key}'),
  });
};

T _req<T>(Map<String, Object?> m, String key, String path, _Dec<T> d) {
  if (!m.containsKey(key)) {
    throw FormatException('$path.$key: required field is missing');
  }
  return d(m[key], '$path.$key');
}

T? _opt<T>(Map<String, Object?> m, String key, String path, _Dec<T> d) {
  final v = m[key];
  return v == null ? null : d(v, '$path.$key');
}

void _expect(Map<String, Object?> m, String key, Object value, String path) {
  if (m[key] != value) {
    throw FormatException('$path.$key: expected $value, got ${m[key]}');
  }
}

Map<String, Object?> _rest(Map<String, Object?> m, Set<String> known) =>
    Map<String, Object?>.unmodifiable({
      for (final e in m.entries)
        if (!known.contains(e.key)) e.key: e.value,
    });
"""


# =============================================================================
# File-level emitters
# =============================================================================


def header(meta: dict, title: str, extra: list[str]) -> str:
    L = [
        "// GENERATED FILE. DO NOT EDIT.",
        "//",
        f"// {title}",
        "// Generated by tool/codegen/gen.py (emitter: tool/codegen/dart_emit.py).",
        f"// Pinned dsh: {meta['repo']} commit {meta['commit']} ({meta.get('tag') or 'untagged'}, npm {meta['npmVersion']}).",
    ]
    for ln in extra:
        L.append("// " + ln if ln else "//")
    L += ["// To regenerate: python3 tool/codegen/gen.py --write", "",
          "// ignore_for_file: type=lint", "// ignore_for_file: unused_element", ""]
    return "\n".join(L)


def method_hint(ns: str, name: str) -> str:
    return pascal(ns) + pascal(name)


def emit_remote(ir: dict, meta: dict, skipped: list[str]) -> str:
    ns = ir["namespace"]
    em = Emitter(ir["decls"])
    cls_name = pascal(ns) + "Remote"
    streams_name = pascal(ns) + "Streams"
    method_src: list[str] = []
    stream_src: list[str] = []
    stream_names: list[str] = []
    for m in ir["methods"]:
        if m["name"] in skipped:
            continue
        hint = method_hint(ns, m["name"])
        params = []
        for p in m["params"]:
            t = em.lower(p["type"], hint + pascal(p["name"].lstrip("_")), p["name"])
            dname = camel(p["name"].lstrip("_"))
            if dname in RESERVED:
                dname += "_"
            params.append((p, dname, t))
        res = em.lower(m["result"], hint + "Value", "") if m["result"]["k"] != "void" else None
        if m["mode"] == "stream":
            if len(params) > 1:
                raise ValueError("stream methods with several params are not supported: " + m["name"])
            frame = res
            if params:
                p, dname, t = params[0]
                arg_t = t.dart
                enc = f"{{{q(p['name'])}: {t.enc_expr('a')}}}"
            else:
                arg_t = "NoStreamArgs"
                enc = "const <String, Object?>{}"
            ep = f"{ns}/{m['name']}"
            stream_src += doc_lines(m.get("doc"), "  ")
            stream_src.append(f"  static final {camel(m['name'])} = StreamDescriptor<{arg_t}, {frame.dart}>(")
            stream_src.append(f"    endpoint: {q(ep)},")
            stream_src.append(f"    encodeArgs: ({'a' if params else '_'}) => {enc},")
            stream_src.append(f"    decodeFrame: (v) => {frame.dec}(v, {q(ep)}),")
            stream_src.append("  );")
            stream_names.append(camel(m["name"]))
            continue
        sig = ", ".join(f"{t.dart if not p['optional'] else nullable_dart(t.base)} {dname}" for p, dname, t in params)
        opt = [x for x in params if x[0]["optional"]]
        if opt:
            req = ", ".join(f"{t.dart} {d}" for p, d, t in params if not p["optional"])
            op = ", ".join(f"{nullable_dart(t.base)} {d}" for p, d, t in params if p["optional"])
            sig = req + (", " if req and op else "") + "[" + op + "]"
        entries = []
        for p, dname, t in params:
            if p["optional"]:
                entries.append(f"if ({dname} case final v?) {q(p['name'])}: {t.enc_nn('v')}")
            else:
                entries.append(f"{q(p['name'])}: {t.enc_expr(dname)}")
        args = "{" + ", ".join(entries) + "}" if entries else "const <String, Object?>{}"
        call = f"_caller.call({q(ns)}, {q(m['name'])}, {args})"
        rtype = "void" if res is None else res.dart
        method_src += doc_lines(m.get("doc"), "  ")
        if res is None:
            method_src.append(f"  Future<void> {camel(m['name'])}({sig}) async {{")
            method_src.append(f"    await {call};")
            method_src.append("  }")
        else:
            method_src.append(f"  Future<{rtype}> {camel(m['name'])}({sig}) async =>")
            method_src.append(f"      {res.dec}(await {call}, {q(ns + '/' + m['name'])});")
        method_src.append("")
    extra = [
        f"Namespace `{ns}` ({pascal(ns)}Remote), package {ir['package']}.",
        "Remote methods: " + ", ".join(f"{m['name']}{' (stream)' if m['mode'] == 'stream' else ''}" for m in ir["methods"] if m["name"] not in skipped) + ".",
        "Wire args are the Host parameter names verbatim (`list` sends `_request`).",
        "Not covered: raw HTTP `POST /api/session/uploadFileBinary` (not a @Remote method) and other namespaces.",
        "SessionWireEvent keeps data/surfaceOp/sourceEventSeqs as raw JSON; the models layer decodes it with",
        "SessionEvent.fromJson(event.toJson()).",
    ]
    if skipped:
        extra.append("Skipped: " + "; ".join(skipped))
    else:
        extra.append("Skipped Remote methods: none.")
    for n in sorted(set(ir.get("notes", [])) | set(em.notes)):
        extra.append("Note: " + n)
    body = em.render_all()
    out = [header(meta, f"Dart client for the dsh `{ns}` Remote namespace.", extra),
           "import '../remote_caller.dart';", "",
           HELPERS, "",
           "/// Describes one multiplexed stream method (`/api/remote.mux`). Streams are not",
           "/// callable through [RemoteCaller]; the transport opens `endpoint` with",
           "/// `payload: {args: encodeArgs(arg)}` and decodes every item with `decodeFrame`.",
           "class StreamDescriptor<Arg, Frame> {",
           "  const StreamDescriptor({",
           "    required this.endpoint,",
           "    required this.encodeArgs,",
           "    required this.decodeFrame,",
           "  });",
           "  final String endpoint;",
           "  final Map<String, Object?> Function(Arg) encodeArgs;",
           "  final Frame Function(Object?) decodeFrame;",
           "}", "",
           "/// Argument of a stream method that takes no parameters.",
           "final class NoStreamArgs {",
           "  const NoStreamArgs();",
           "}", "",
           f"/// Unary `{ns}` methods over a [RemoteCaller].",
           f"class {cls_name} {{",
           f"  {cls_name}(this._caller);",
           "  final RemoteCaller _caller;",
           f"  static const namespace = {q(ns)};", ""]
    out += method_src
    out += ["}", "", f"/// Stream methods of the `{ns}` namespace.", f"abstract final class {streams_name} {{"]
    out += stream_src
    out += ["}", "", body]
    return "\n".join(out) + "\n"


def emit_events(ir: dict, meta: dict) -> str:
    em = Emitter(ir["decls"])
    for name in sorted(ir["decls"]):
        em.lower_ref(name)
    ev_src: list[str] = []
    types = []
    for ev in ir["events"]:
        cls = ev["className"]
        types.append(ev["type"])
        data_t = em.lower(ev["data"], cls + "Data", "data") if ev["data"] is not None else None
        sop_t = em.lower(ev["surfaceOp"], cls + "SurfaceOp", "surfaceOp") if ev.get("surfaceOp") else None
        seq_t = em.lower(ev["sourceEventSeqs"], cls + "SourceEventSeqs", "sourceEventSeqs") if ev.get("sourceEventSeqs") else None
        seq_opt = ev.get("sourceEventSeqsOptional", True)
        ctor = ["required super.seq", "required super.time", "super.ignorable"]
        fields = []
        decode = ["seq: _req(m, 'seq', path, _int)", "time: _req(m, 'time', path, _int)",
                  "ignorable: _opt(m, 'ignorable', path, _bool) ?? false"]
        enc = ["'type': type", "'seq': seq", "'time': time", "if (ignorable) 'ignorable': true"]
        if data_t is not None:
            ctor.append("required this.data")
            fields.append((data_t.dart, "data", None))
            decode.append(f"data: _req<{data_t.dart}>(m, 'data', path, {data_t.dec})")
            enc.append(f"'data': {data_t.enc_expr('data')}")
        if sop_t is not None:
            ctor.append("required this.surfaceOp")
            fields.append((sop_t.base, "surfaceOp", "@override"))
            decode.append(f"surfaceOp: _req<{sop_t.dart}>(m, 'surfaceOp', path, {sop_t.dec})")
            enc.append(f"'surfaceOp': {sop_t.enc_expr('surfaceOp')}")
        if seq_t is not None:
            ctor.append("this.sourceEventSeqs" if seq_opt else "required this.sourceEventSeqs")
            fields.append((nullable_dart(seq_t.base) if seq_opt else seq_t.base, "sourceEventSeqs", "@override"))
            fn = "_opt" if seq_opt else "_req"
            decode.append(f"sourceEventSeqs: {fn}<{seq_t.dart}>(m, 'sourceEventSeqs', path, {seq_t.dec})")
            if seq_opt:
                enc.append(f"if (sourceEventSeqs case final v?) 'sourceEventSeqs': {seq_t.enc_nn('v')}")
            else:
                enc.append(f"'sourceEventSeqs': {seq_t.enc_expr('sourceEventSeqs')}")
        L = [f"/// Session event `{ev['type']}`.", f"final class {cls} extends SessionEvent {{",
             f"  const {cls}({{{', '.join(ctor)}}});",
             f"  static const typeName = {q(ev['type'])};",
             "  @override", "  String get type => typeName;"]
        for ty, nm, ov in fields:
            if ov:
                L.append(ov)
            L.append(f"  final {ty} {nm};")
        L += [f"  factory {cls}.fromJson(Object? json, [String path = r'$']) {{",
              "    final m = _obj(json, path);",
              f"    return {cls}(", *[f"      {d}," for d in decode], "    );", "  }",
              "  @override", "  Map<String, Object?> toJson() => {", *[f"    {e}," for e in enc], "  };", "}", ""]
        ev_src.append("\n".join(L))
    sop_name = "SessionSurfaceOp"
    base = [
        "/// One session log event (the envelope `{type, seq, time, data, ...}`).",
        "///",
        "/// [SessionEvent.fromJson] dispatches on `type`. A type outside",
        "/// [knownSessionEventTypes] becomes [UnknownSessionEvent]; dsh's rule",
        "/// (known-event-types.ts) is that an unknown event carrying `ignorable: true`",
        "/// may be skipped, while an unknown event without it means the log was written",
        "/// by a newer harness and must not be interpreted ([UnknownSessionEvent.mustUnderstand]).",
        "sealed class SessionEvent {",
        "  const SessionEvent({required this.seq, required this.time, this.ignorable = false});",
        "  final int seq;",
        "  final int time;",
        "  final bool ignorable;",
        "  String get type;",
        f"  /// Placement on the surface; null for log-only events.",
        f"  {sop_name}? get surfaceOp => null;",
        "  /// Earlier source events of a surface event.",
        "  List<int>? get sourceEventSeqs => null;",
        "  /// True when this build has a typed class for [type].",
        "  bool get isKnown => this is! UnknownSessionEvent;",
        "  /// True for an unknown event that is explicitly safe to skip.",
        "  bool get isSkippable => this is UnknownSessionEvent && ignorable;",
        "  factory SessionEvent.fromJson(Object? json, [String path = r'$']) {",
        "    final m = _obj(json, path);",
        "    final type = _req(m, 'type', path, _str);",
        "    return switch (type) {",
        *[f"      {q(ev['type'])} => {ev['className']}.fromJson(m, path)," for ev in ir["events"]],
        "      _ => UnknownSessionEvent.fromJson(m, path),",
        "    };",
        "  }",
        "  Map<String, Object?> toJson();",
        "}", "",
        "/// An event whose `type` this generation does not know. Raw JSON is kept.",
        "final class UnknownSessionEvent extends SessionEvent {",
        "  const UnknownSessionEvent({",
        "    required this.type,",
        "    required super.seq,",
        "    required super.time,",
        "    super.ignorable,",
        "    required this.raw,",
        "  });",
        "  factory UnknownSessionEvent.fromJson(Object? json, [String path = r'$']) {",
        "    final m = _obj(json, path);",
        "    return UnknownSessionEvent(",
        "      type: _req(m, 'type', path, _str),",
        "      seq: _req(m, 'seq', path, _int),",
        "      time: _req(m, 'time', path, _int),",
        "      ignorable: _opt(m, 'ignorable', path, _bool) ?? false,",
        "      raw: m,",
        "    );",
        "  }",
        "  @override",
        "  final String type;",
        "  final Map<String, Object?> raw;",
        "  /// An unknown event without `ignorable` must not be skipped silently.",
        "  bool get mustUnderstand => !ignorable;",
        "  @override",
        "  Map<String, Object?> toJson() => raw;",
        "}", "",
        f"/// Every event type this build understands (dsh format version {ir['formatVersion']}).",
        "const knownSessionEventTypes = <String>{",
        *[f"  {q(t)}," for t in types],
        "};", "",
        "/// Schema digest per event type from docs/persistence-schema.json; a changed",
        "/// digest after a pin move means the payload shape changed.",
        "const sessionEventSchemaDigests = <String, String>{",
        *[f"  {q(ev['type'])}: {q(ev['digest'])}," for ev in ir["events"]],
        "};", "",
        f"const sessionEventFormatVersion = {ir['formatVersion']};", "",
    ]
    extra = [f"Session event schema: docs/persistence-schema.json formatVersion {ir['formatVersion']} ({len(types)} event types).",
             "Numbers are `int` for seq/time/index/count/token style names and `num` otherwise."]
    for n in sorted(set(ir.get("notes", [])) | set(em.notes)):
        extra.append("Note: " + n)
    out = [header(meta, "Typed session events for the dsh log and follow stream.", extra), HELPERS, "",
           "\n".join(base), em.render_all(), "\n".join(ev_src)]
    return "\n".join(out) + "\n"
