#!/usr/bin/env python3
"""Write the synthetic inputs of the `dsh-settings-vector/1` fixtures.

    synth_settings_trace.py schema OUT.json      settings_schema_vector.json
    synth_settings_trace.py form OUT.json        settings_form_vector.json
    synth_settings_trace.py form-model OUT.json  settings_form_model_vector.json

No recorded content: every string is generic. The expectations are NOT written
here: run `gen_settings_expected.py --write` on the output so dsh's own
TypeScript code produces them.

schema      Cases {name, schema, value}. Schemas are serialized schemastery
            envelopes ({uid, refs}), either a key of the fixture's `schemas`
            map (`schemaRef`) or inline (`schema`, the malformed ones). They come from the committed
            real `settings.describe` answer (packages/dsh_models/test/fixtures/
            describe_default_host.json: every namespace, with its resolved value
            and systematic mutations of each field) and from hand-built schemas
            covering every resolver. `messageExact: false` marks a case whose
            failure text depends on the JavaScript engine (TypeError texts,
            RegExp syntax errors, JS function stringification); the verdict is
            still compared.
form        Scripted traces through the describe mirror and configuration forms.
form-model  Scripted scope and edits through the staged settings form model.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DESCRIBE = os.path.join(ROOT, 'packages/dsh_models/test/fixtures/describe_default_host.json')


def compact(value):
    return json.dumps(value, separators=(',', ':'), sort_keys=True, allow_nan=False)


# ===================================================================== schema


class Env:
    """Builds a serialized schemastery envelope (`schema.toJSON()` shape)."""

    def __init__(self, start=1):
        self.refs = {}
        self.next = start

    def add(self, node):
        uid = self.next
        self.next += 1
        self.refs[str(uid)] = node
        return uid

    def node(self, type_, meta=None, **extra):
        out = {'type': type_, 'meta': {} if meta is None else meta}
        out.update(extra)
        return self.add(out)

    def string(self, **meta):
        return self.node('string', meta)

    def number(self, **meta):
        return self.node('number', meta)

    def boolean(self, **meta):
        return self.node('boolean', meta)

    def const(self, value, required=True, **meta):
        if required:
            meta['required'] = True
        return self.node('const', meta, value=value)

    def any(self, **meta):
        return self.node('any', meta)

    def union(self, members, **meta):
        return self.node('union', meta, list=list(members))

    def intersect(self, members, **meta):
        return self.node('intersect', meta, list=list(members))

    def tuple(self, members, **meta):
        meta.setdefault('default', [])
        return self.node('tuple', meta, list=list(members))

    def array(self, inner, **meta):
        meta.setdefault('default', [])
        return self.node('array', meta, inner=inner)

    def dict(self, inner, key=None, **meta):
        meta.setdefault('default', {})
        extra = {'inner': inner}
        if key is not None:
            extra['sKey'] = key
        return self.node('dict', meta, **extra)

    def object(self, fields, **meta):
        meta.setdefault('default', {})
        return self.node('object', meta, dict=dict(fields))

    def bitset(self, bits, **meta):
        meta.setdefault('default', 0)
        return self.node('bitset', meta, bits=dict(bits))

    def envelope(self, root):
        return {'uid': root, 'refs': json.loads(json.dumps(self.refs))}


class Schemas:
    def __init__(self):
        self.schemas = {}
        self.cases = []
        self.seen = set()

    def schema(self, name, envelope):
        assert name not in self.schemas, name
        self.schemas[name] = envelope

    def case(self, schema, value, label=None, exact=True, inline=False):
        # a str names an entry of `schemas` (`schemaRef`) unless `inline`: then it is an inline envelope (`schema`)
        ref = isinstance(schema, str) and not inline
        key = (('ref', schema) if ref else ('inline', compact(schema)), compact(value))
        if key in self.seen:
            return
        self.seen.add(key)
        name = '%s: %s' % (schema if ref else 'inline', label or compact(value)[:80])
        entry = {'name': name, 'schemaRef': schema, 'value': value} if ref else {'name': name, 'schema': schema, 'value': value}
        if not exact:
            entry['messageExact'] = False
        self.cases.append(entry)

    def values(self, schema, values, exact=True):
        for value in values:
            self.case(schema, value, exact=exact)


POOL = [
    None, True, False, 0, 1, -1, 1.5, 0.1, 1e21, 9007199254740991, 9007199254740992, -0.0, '', 'x', ' ', 'light',
    '0', [], [1], ['a'], [None], [[1]], {}, {'a': 1}, {'a': None},
]


def specific_variants(refs, uid, depth=0):
    """Type-aware values for one schema node: boundary, near-miss and structured ones."""
    node = refs[str(uid)]
    kind = node.get('type')
    meta = node.get('meta') or {}
    out = []
    if kind == 'number':
        lo, hi, step = meta.get('min'), meta.get('max'), meta.get('step')
        for base in (lo, hi):
            if base is not None:
                out += [base, base - 1, base + 1, base - 0.5, base + 0.5]
        if lo is not None and step:
            out += [lo + step, lo + 2 * step, lo + step / 2, lo + 1.5 * step]
        if lo is not None and hi is not None:
            out += [(lo + hi) // 2, (lo + hi) / 2 + 0.25]
        if meta.get('default') is not None:
            out += [meta['default'], meta['default'] + 0.5, -meta['default']]
    elif kind == 'string':
        lo, hi = meta.get('min'), meta.get('max')
        out += ['a', 'ab', 'a' * 200, '\u00e9', '\U0001F600', '\U0001F600' * 3, 'line\nbreak', 'with "quotes"']
        for edge in (lo, hi):
            if edge is not None and edge < 50:
                out += ['a' * max(edge - 1, 0), 'a' * edge, 'a' * (edge + 1)]
    elif kind == 'boolean':
        out += ['true', 1, 0]
    elif kind == 'union':
        for member in node.get('list') or []:
            member_node = refs[str(member)]
            if member_node.get('type') == 'const':
                value = member_node.get('value')
                out.append(value)
                if isinstance(value, str):
                    out += [value.upper(), value + ' ', value[:-1], ' ' + value, value.capitalize()]
            else:
                out += specific_variants(refs, member, depth + 1)
    elif kind == 'array':
        inner = specific_variants(refs, node['inner'], depth + 1)
        good = inner[:6]
        out += [good, good * 2, [None], [good[0] if good else 0, None]]
        out += [[v] for v in inner[:30]]
    elif kind == 'object' and depth < 3:
        out += [{k: None for k in (node.get('dict') or {})}]
    return out


def graph_value_variants(refs, uid):
    return POOL + specific_variants(refs, uid)


def describe_cases(s):
    with open(DESCRIBE, encoding='utf-8') as handle:
        describe = json.load(handle)
    for row in describe['namespaces']:
        ns, envelope, value = row['ns'], row['schema'], row['value']
        name = 'describe/' + ns
        s.schema(name, envelope)
        refs = envelope['refs']
        root = refs[str(envelope['uid'])]
        # whole-value shapes
        s.case(name, value, 'resolved value')
        s.case(name, {}, 'empty object')
        for item in POOL:
            s.case(name, item, 'root %s' % compact(item)[:40])
        s.case(name, dict(value, extraKey='x'), 'unknown key kept')
        s.case(name, dict(value, extraKey=None), 'unknown key null')
        for field, uid in (root.get('dict') or {}).items():
            without = {k: v for k, v in value.items() if k != field}
            s.case(name, without, 'field %s absent' % field)
            for variant in graph_value_variants(refs, uid):
                s.case(name, dict(value, **{field: variant}), '%s=%s' % (field, compact(variant)[:50]))
            node = refs[str(uid)]
            if node.get('type') == 'array':
                inner = refs[str(node['inner'])]
                if inner.get('type') == 'object':
                    keys = list(inner.get('dict') or {})
                    elements = [
                        {k: 'a' for k in keys},
                        {keys[0]: 'a'},
                        {keys[0]: '', keys[-1]: 'b'},
                        {k: 'a' for k in keys} | {'extra': 1},
                        {keys[0]: 1, keys[-1]: 'b'},
                        {},
                    ]
                    for element in elements:
                        s.case(name, dict(value, **{field: [element]}), '%s[0]=%s' % (field, compact(element)))
                        s.case(name, dict(value, **{field: [elements[0], element]}), '%s[1]=%s' % (field, compact(element)))


def number_cases(s):
    e = Env()
    fields = {
        'pct': e.number(step=0.01, min=0, max=1),
        'tenth': e.number(step=0.1),
        'tenthMin': e.number(step=0.1, min=0.1, max=5),
        'half': e.number(step=0.5, min=-2),
        'three': e.number(step=3, min=1),
        'frac': e.number(step=1, min=0.5),
        'zeroStep': e.number(step=0),
        'negStep': e.number(step=-2, min=0),
        'milli': e.number(step=0.001),
        'sevenE': e.number(step=1e-7),
        'safe': e.number(step=1, min=0, max=9007199254740991),
        'minOnly': e.number(min=5),
        'maxOnly': e.number(max=-3),
        'plain': e.number(),
        'big': e.number(step=1e21),
        'fracStep': e.number(step=2.5, min=1),
    }
    s.schema('hand/numbers', e.envelope(e.object(fields)))
    table = {
        'pct': [0, 0.01, 0.07, 0.29, 0.57, 0.58, 0.3, 0.1 + 0.2, 1, 1.01, -0.01, 0.005, 0.999, 0.5, 0.14, 0.15, 0.28],
        'tenth': [0, 0.1, 0.2, 0.3, 0.7, 1.1, 0.15, -0.3, 2.3000000000000003, 1e-7, 1e21, 0.30000000000000004, 12.3, 1e-6],
        'tenthMin': [0.1, 0.2, 0.25, 4.9, 5, 5.1, 0.05, 0.3, 0.30000000000000004, 4.95],
        'half': [-2, -1.5, -1.25, 0, 0.5, 1e300, 3, 2.5, -2.5],
        'three': [1, 4, 7, 2, 3, -2, 1e21, 10, 13, 12.5],
        'frac': [0.5, 1.5, 1, 2, 2.5, 0.25],
        'zeroStep': [1.234, 0, -5],
        'negStep': [0, 2, 3, 4, -2, 1.5],
        'milli': [0.001, 0.002, 0.0015, 1e-7, 0.0010000000000000002, 1.234, 12, 0.003, 0.007],
        'sevenE': [1e-7, 2e-7, 1.5e-7, 3e-7, 0, 1, 5e-7, 6e-7, 7e-7],
        'safe': [9007199254740991, 9007199254740992, 1e15, 0, -1, 123456789012345],
        'minOnly': [4.999999, 5, 5.000001, 1e21],
        'maxOnly': [-3, -2.999, -3.001, -1e21],
        'plain': [1e21, 1.5e-7, 123456789.123456789, 5e-324, 1.7976931348623157e308, 0.000001, 0.0000001, 100, 1e20, 1e22, -1e21,
                  4.35, 2 ** 53, 2 ** 53 + 2, 0.1, 123e18],
        'big': [0, 1e21, 2e21, 3e20, 5e21],
        'fracStep': [1, 3.5, 6, 4, 8.5, 1.1],
    }
    for field, values in table.items():
        for v in values:
            s.case('hand/numbers', {field: v}, '%s=%s' % (field, compact(v)))
        s.case('hand/numbers', {field: 'x'}, '%s=string' % field)
    s.case('hand/numbers', {'plain': 3, 'pct': 0.25, 'tenth': 0.3, 'three': 4}, 'several valid')


def string_cases(s):
    e = Env()
    fields = {
        'len': e.string(min=2, max=4),
        'pat': e.string(pattern={'source': '^[a-z]+$', 'flags': ''}),
        'patI': e.string(pattern={'source': '^abc$', 'flags': 'i'}),
        'patM': e.string(pattern={'source': '^b$', 'flags': 'm'}),
        'patS': e.string(pattern={'source': 'a.b', 'flags': 's'}),
        'patDot': e.string(pattern={'source': '^.$', 'flags': ''}),
        'patU': e.string(pattern={'source': '^\\p{L}+$', 'flags': 'u'}),
        'patSlash': e.string(pattern={'source': 'a/b', 'flags': ''}),
        'patSlashEsc': e.string(pattern={'source': 'a\\/b', 'flags': ''}),
        'patEmpty': e.string(pattern={'source': '', 'flags': ''}),
        'patFlagsMI': e.string(pattern={'source': '^b$', 'flags': 'mi'}),
        'patG': e.string(pattern={'source': 'ab', 'flags': 'g'}),
        'patLookbehind': e.string(pattern={'source': '(?<=a)b', 'flags': ''}),
        'patNamed': e.string(pattern={'source': '^(?<n>a)\\k<n>$', 'flags': ''}),
        'patDigit': e.string(pattern={'source': '^\\d{3}$', 'flags': ''}),
        'patWord': e.string(pattern={'source': '^\\w+$', 'flags': ''}),
        'patBoundary': e.string(pattern={'source': '\\bfoo\\b', 'flags': ''}),
        'patSticky': e.string(pattern={'source': 'b', 'flags': 'y'}),
        'patWithLen': e.string(pattern={'source': '^[a-z]*$', 'flags': ''}, min=2, max=3),
        'patNoFlags': e.string(pattern={'source': '^a$'}),
        'patEscapedLine': e.string(pattern={'source': 'a\\nb', 'flags': ''}),
        'noMax': e.string(min=1),
    }
    s.schema('hand/strings', e.envelope(e.object(fields)))
    table = {
        'len': ['', 'a', 'ab', 'abc', 'abcd', 'abcde', '\U0001F600', '\U0001F600\U0001F600', '\U0001F600' * 3, 'éé', 'éé'],
        'pat': ['abc', 'ABC', '', 'abc\n', 'a b', 'a1', 'z'],
        'patI': ['ABC', 'abc', 'abd', 'AbC', 'abc\n'],
        'patM': ['a\nb\nc', 'abc', 'b', 'b\n', 'a\nb'],
        'patS': ['a\nb', 'a.b', 'axb', 'ab'],
        'patDot': ['a', '\n', '\r', ' ', ' ', '\U0001F600', '', 'ab', '\u0085'],
        'patU': ['été', '123', '日本語', 'abc', '', '\U0001F600'],
        'patSlash': ['a/b', 'ab', 'a\\/b'],
        'patSlashEsc': ['a/b', 'ab'],
        'patEmpty': ['', 'x'],
        'patFlagsMI': ['B', 'a\nB', 'abc'],
        'patG': ['ab', 'cab', 'ba', 'abab'],
        'patLookbehind': ['ab', 'b', 'cb'],
        'patNamed': ['aa', 'ab'],
        'patDigit': ['123', '12', '1234', '١٢٣', '12a'],
        'patWord': ['abc_1', 'é', '', 'a b', 'A_9'],
        'patBoundary': ['foo', 'a foo b', 'food', 'xfoo', 'foo.'],
        'patSticky': ['b', 'ab', 'ba', ''],
        'patWithLen': ['ab', 'a', 'abcd', 'AB', 'abc'],
        'patNoFlags': ['a', 'A', 'aa'],
        'patEscapedLine': ['a\nb', 'anb', 'a\\nb'],
        'noMax': ['', 'a', 'a' * 1000],
    }
    for field, values in table.items():
        for v in values:
            s.case('hand/strings', {field: v}, '%s=%s' % (field, compact(v)[:40]))
        s.case('hand/strings', {field: 5}, '%s=number' % field)
    s.case('hand/strings', {}, 'nothing given')
    # failing pattern constructions: the engine's own error text
    inexact = Env()
    bad = {
        'badSource': inexact.string(pattern={'source': '(', 'flags': ''}),
        'badFlags': inexact.string(pattern={'source': 'a', 'flags': 'ii'}),
        'unknownFlag': inexact.string(pattern={'source': 'a', 'flags': 'z'}),
        'badBackref': inexact.string(pattern={'source': '\\k<nope>(?<x>a)', 'flags': 'u'}),
    }
    s.schema('hand/bad-patterns', inexact.envelope(inexact.object(bad)))
    for field in bad:
        s.case('hand/bad-patterns', {field: 'a'}, '%s string' % field, exact=False)
        s.case('hand/bad-patterns', {field: None}, '%s null' % field)
        s.case('hand/bad-patterns', {field: 5}, '%s number (type check precedes the pattern)' % field)
    s.case('hand/bad-patterns', {}, 'no values')


def union_cases(s):
    e = Env()
    mixed = e.union([e.string(min=2), e.number(step=1), e.const('a')], default='ab')
    arr_union = e.array(e.union([e.string(), e.number()]))
    obj_union = e.union([
        e.object({'a': e.string(required=True), 'b': e.number()}),
        e.array(e.string()),
        e.const(5, required=True),
    ])
    nested = e.union([e.union([e.const('x'), e.const('y')]), e.number()])
    flags_union = e.union([e.boolean(), e.const('on'), e.const('off')])
    num_consts = e.union([e.const(1), e.const(2), e.const(3.5), e.const(True), e.const(False)])
    root = e.object({
        'mixed': mixed, 'arrUnion': arr_union, 'objUnion': obj_union, 'nested': nested, 'flags': flags_union,
        'numConsts': num_consts,
        'looseUnion': e.union([e.const('a'), e.const('b')], loose=True, default='a'),
        'requiredUnion': e.union([e.const('a'), e.const('b')], required=True),
    })
    s.schema('hand/unions', e.envelope(root))
    values = [
        'ab', 'a', 'b', '', 3, 3.5, True, None, [], {}, [1, 2], {'x': 'y'}, 'quote"d', 'new\nline', 'tab\t', 'é',
        '\u0001', '\\', '\U0001F600', [None], [[1, [2]]], {'b': 1, '2': 2, 'a': 3, '1': 4}, {'z': None},
        0.1, 1e21, -0.0, 1e-7, 5, {'a': 'x'}, {'a': 1}, ['s', 's'], [1], 'on', 'off', 'ON', 2, 3, 4, 1.0, '1',
        {'nested': {'k': [1, 'two', None, True]}}, {'a': {'b': {'c': {}}}}, -5, 123456789012345678901234567890.0,
        [{'a': 1}], ['quo"te'], {'k"ey': 1}, {'\n': 1},
    ]
    for field in ('mixed', 'arrUnion', 'objUnion', 'nested', 'flags', 'numConsts', 'looseUnion', 'requiredUnion'):
        for v in values:
            s.case('hand/unions', {'requiredUnion': 'a', field: v}, '%s=%s' % (field, compact(v)[:40]))
    s.case('hand/unions', {'mixed': 'a', 'arrUnion': ['a', 1], 'objUnion': 5}, 'valid combination')
    s.case('hand/unions', {'requiredUnion': 'a'}, 'required union present')
    s.case('hand/unions', {}, 'required union absent')


def const_cases(s):
    e = Env()
    fields = {
        'str': e.const('x'),
        'num': e.const(5),
        'zero': e.const(0),
        'yes': e.const(True),
        'no': e.const(False),
        'empty': e.const(''),
        'optional': e.const('x', required=False),
        'float': e.const(0.5),
    }
    s.schema('hand/consts', e.envelope(e.object(fields)))
    CONST_BASE = {'str': 'x', 'num': 5, 'zero': 0, 'yes': True, 'no': False, 'empty': '', 'float': 0.5}
    s.case('hand/consts', CONST_BASE, 'all constants matched')
    s.case('hand/consts', {}, 'all constants missing')
    values = ['x', 'X', 5, 5.0, '5', 0, False, True, '', None, [], {}, 1, 0.5, [5], {'x': 1}, 'x ', -0.0]
    for field in fields:
        for v in values:
            s.case('hand/consts', {**CONST_BASE, field: v}, '%s=%s' % (field, compact(v)))
    # constants that are not plain scalars: schemastery prints them through its own toString rules
    w = Env()
    weird = {
        'obj': w.const({'a': 1, 'b': [1, 2]}),
        'arr': w.const([1, 'two']),
        'nulOpt': w.const(None, required=False),
        'inUnion': w.union([w.const({'a': 1}), w.const(None, required=False), w.const('s')]),
    }
    s.schema('hand/weird-consts', w.envelope(w.object(weird)))
    wvalues = [{'a': 1, 'b': [1, 2]}, {'a': 1}, {'b': [1, 2], 'a': 1}, {'a': 1, 'b': [1, 3]}, [1, 'two'], [1], None, 0, 'x', 's',
               {'a': 1, 'b': None}, {'a': None}, {}]
    for field in weird:
        for v in wvalues:
            s.case('hand/weird-consts', {'obj': {'a': 1, 'b': [1, 2]}, 'arr': [1, 'two'], field: v}, '%s=%s' % (field, compact(v)), exact=False)


def dict_cases(s):
    e = Env()
    lower = e.string(pattern={'source': '^[a-z]+$', 'flags': ''})
    enum_key = e.union([e.const('read'), e.const('write')])
    fields = {
        'byName': e.dict(e.number(min=0), lower),
        'defaultKey': e.dict(e.string()),
        'enumKeys': e.dict(e.boolean(), enum_key),
        'nested': e.dict(e.object({'n': e.number(required=True)})),
        'ofArrays': e.dict(e.array(e.number(max=3))),
        'strictInter': e.intersect([e.dict(e.number(), lower), e.dict(e.number())]),
        'requiredInner': e.dict(e.string(required=True)),
    }
    s.schema('hand/dicts', e.envelope(e.object(fields)))
    table = {
        'byName': [{'abc': 1}, {'ABC': 1}, {'a': -1}, {'': 0}, {'abc': 1, 'x1': 2}, {}, [], 'x', {'abc': None}, {'abc': 'x'}, {'a': 1, 'b': 2.5}],
        'defaultKey': [{'a': 'x'}, {'': ''}, {'a': 1}, {'a': None}, {'1': 'x'}, {'a': {}}, {'a': 'b', 'c': 5}],
        'enumKeys': [{'read': True}, {'write': False}, {'exec': True}, {'read': 'yes'}, {}, {'read': True, 'x': True}],
        'nested': [{'k': {'n': 1}}, {'k': {}}, {'k': None}, {'k': {'n': 'x'}}, {'a': {'n': 1}, 'b': {'n': None}}, {'k': 5}],
        'ofArrays': [{'k': [1, 2]}, {'k': [4]}, {'k': []}, {'k': None}, {'k': 'x'}, {'k': [1, 'x']}],
        'strictInter': [{'abc': 1}, {'ABC': 1}, {'abc': 'x'}, {'a': 1, 'B': 2}, {}],
        'requiredInner': [{'a': 'x'}, {'a': None}, {'a': ''}, {}],
    }
    for field, values in table.items():
        for v in values:
            s.case('hand/dicts', {field: v}, '%s=%s' % (field, compact(v)))


def array_cases(s):
    e = Env()
    fields = {
        'bounded': e.array(e.string(), min=1, max=2, default=['a']),
        'innerDefault': e.array(e.number(default=0), min=2),
        'matrix': e.array(e.array(e.number(min=0))),
        'objects': e.array(e.object({'id': e.string(required=True), 'n': e.number(step=1)})),
        'requiredInner': e.array(e.string(required=True)),
        'unionInner': e.array(e.union([e.const('a'), e.const('b')])),
        'maxOnly': e.array(e.number(), max=0),
        'nonNullInnerDefault': e.array(e.string(default='z', min=1), min=1, max=3),
    }
    s.schema('hand/arrays', e.envelope(e.object(fields)))
    table = {
        'bounded': [[], ['a'], ['a', 'b'], ['a', 'b', 'c'], [1], ['a', None], None, 'a', {}, [['a']]],
        'innerDefault': [[], [1], [1, 2], [None], [1, 'x'], [None, None, None]],
        'matrix': [[[1]], [[]], [[-1]], [[1], [2, -3]], [None], [[None]], [1], 'x'],
        'objects': [[{'id': 'a'}], [{}], [{'id': 'a', 'n': 1.5}], [{'id': 1}], [None], [{'id': 'a'}, {'n': 1}], [[]], [{'id': 'a', 'x': 1}]],
        'requiredInner': [['a'], [None], ['a', None], [''], []],
        'unionInner': [['a', 'b'], ['c'], [1], ['a', 'c'], [[]]],
        'maxOnly': [[], [1]],
        'nonNullInnerDefault': [[], ['a'], [None], ['a', 'b', 'c', 'd'], [''], [None, None]],
    }
    for field, values in table.items():
        for v in values:
            s.case('hand/arrays', {field: v}, '%s=%s' % (field, compact(v)))


def tuple_cases(s):
    e = Env()
    fields = {
        'triple': e.tuple([e.string(), e.number(min=0), e.boolean()]),
        'requiredFirst': e.tuple([e.string(required=True), e.number()]),
        'withDefaults': e.tuple([e.string(default='d'), e.number(default=7, min=5)]),
        'nested': e.tuple([e.array(e.number()), e.object({'a': e.string(required=True)})]),
        'empty': e.tuple([]),
    }
    s.schema('hand/tuples', e.envelope(e.object(fields)))
    TUPLE_BASE = {'requiredFirst': ['a'], 'nested': [[1], {'a': 'x'}]}
    s.case('hand/tuples', {}, 'nothing given: required first element and nested required field missing')
    s.case('hand/tuples', TUPLE_BASE, 'bases only')
    table = {
        'triple': [['a', 1, True], ['a'], [], ['a', -1], ['a', 1, True, 'extra', {}], ['a', 'b'], None, {}, 'a', [None, None, None], [1, 1, True], ['a', 1, 'no']],
        'requiredFirst': [[], ['a'], [None, 1], ['a', 'b'], [1]],
        'withDefaults': [[], ['x'], ['x', 9], ['x', 1], None, [None, None]],
        'nested': [[[1], {'a': 'x'}], [[], {}], [[1, 'x'], {'a': 'x'}], [None, None], [[1], None]],
        'empty': [[], [1, 2], None, 'x'],
    }
    for field, values in table.items():
        for v in values:
            s.case('hand/tuples', {**TUPLE_BASE, field: v}, '%s=%s' % (field, compact(v)))


def intersect_cases(s):
    e = Env()
    fields = {
        'objects': e.intersect([e.object({'a': e.number(min=0)}), e.object({'b': e.string()})]),
        'numbers': e.intersect([e.number(min=0), e.number(max=10)]),
        'mismatch': e.intersect([e.string(), e.number()]),
        'empty': e.intersect([]),
        'withDefault': e.intersect([e.object({'a': e.number(default=1)}), e.object({'b': e.string(default='x')})]),
        'anyAndConst': e.intersect([e.any(), e.const(5)]),
        'requiredFirst': e.intersect([e.string(required=True), e.string(min=2)]),
        'withArrays': e.intersect([e.array(e.number()), e.array(e.number(max=5))]),
        'defaultInFirst': e.intersect([e.number(default=7), e.number(max=3)]),
    }
    s.schema('hand/intersects', e.envelope(e.object(fields)))
    table = {
        'objects': [{'a': 1, 'b': 'x'}, {'a': -1}, {'b': 1}, {}, None, 'x', {'a': 1}, {'a': 1, 'c': 3}, [], {'b': 'x', 'a': 'x'}],
        'numbers': [5, -1, 11, 'x', None, 0, 10],
        'mismatch': ['x', 5, None, True, {}],
        'empty': [1, 'x', None, {}],
        'withDefault': [{}, None, {'a': 2}, {'a': 'x'}, {'b': 5}],
        'anyAndConst': [5, 6, '5', None, {}],
        'requiredFirst': ['ab', 'a', None, '', 5],
        'withArrays': [[1, 2], [6], [], None, 'x', [1, 'x']],
        'defaultInFirst': [None, 2, 7, 4, 3],
    }
    for field, values in table.items():
        for v in values:
            s.case('hand/intersects', {'requiredFirst': 'ab', 'defaultInFirst': 2, field: v}, '%s=%s' % (field, compact(v)))


def bitset_cases(s):
    e = Env()
    fields = {
        'perms': e.bitset({'read': 1, 'write': 2, 'exec': 4}),
        'empty': e.bitset({}),
        'tagged': e.bitset({'a': 1}, required=True),
    }
    s.schema('hand/bitsets', e.envelope(e.object(fields)))
    values = [3, 0, -1, 7.5, 2 ** 31, 1e21, [], ['read'], ['read', 'nope'], [1], ['read', None], ['read', ['write']], [{}], [[]], [None],
              'read', None, True, {}, ['toString'], ['constructor'], ['__proto__'], [[1, 2]], [True], [0.5]]
    for field in fields:
        for v in values:
            s.case('hand/bitsets', {'tagged': 1, field: v}, '%s=%s' % (field, compact(v)))


def loose_cases(s):
    e = Env()
    fields = {
        'a': e.number(min=0, loose=True, default=5),
        'b': e.union([e.const('x'), e.const('y')], loose=True),
        'c': e.object({'d': e.string(loose=True, default='z'), 'e': e.number(required=True)}),
        'looseObj': e.object({'n': e.number(min=0)}, loose=True),
        'looseRequired': e.string(required=True, loose=True, default='d'),
        'looseArray': e.array(e.number(max=2, loose=True, default=0)),
    }
    s.schema('hand/loose', e.envelope(e.object(fields)))
    table = {
        'a': [-1, 1, 'x', None, {}],
        'b': ['x', 'z', 1, None],
        'c': [{'d': 'ok', 'e': 1}, {'d': 5, 'e': 1}, {'d': 5}, {}, None, 'x'],
        'looseObj': [{'n': 1}, {'n': -1}, 'x', None, [], {'n': 'x'}],
        'looseRequired': [None, 'x', 5],
        'looseArray': [[1, 2], [3], [1, 3, 'x'], 'x', [None]],
    }
    for field, values in table.items():
        for v in values:
            s.case('hand/loose', {'c': {'e': 1}, field: v}, '%s=%s' % (field, compact(v)))
    r = Env()
    s.schema('hand/loose-root', r.envelope(r.object({'n': r.number()}, loose=True, default={'n': 1})))
    s.values('hand/loose-root', [{'n': 'x'}, 5, None, [], {'n': 2}])


def required_cases(s):
    e = Env()
    fields = {
        'a': e.string(required=True),
        'b': e.object({'c': e.number(required=True)}, required=True),
        'd': e.array(e.string(required=True)),
        'withDefault': e.string(required=True, default='x'),
        'deep': e.object({'x': e.object({'y': e.object({'z': e.boolean(required=True)}, default=None)}, default=None)}, default=None),
        'viaDefault': e.object({'k': e.string(required=True)}, default={'k': 'v'}),
    }
    s.schema('hand/required', e.envelope(e.object(fields)))
    values = [
        {}, {'a': 'x'}, {'a': 'x', 'b': {}}, {'a': None}, {'a': ''}, {'a': 'x', 'b': {'c': 1}}, {'a': 'x', 'b': None},
        {'a': 'x', 'b': {'c': 1}, 'd': [None]}, {'a': 'x', 'b': {'c': 1}, 'd': ['x', None]},
        {'a': 'x', 'b': {'c': 1}, 'withDefault': None}, {'a': 'x', 'b': {'c': 1}, 'withDefault': 'q'},
        {'a': 'x', 'b': {'c': 1}, 'deep': {'x': {'y': {}}}}, {'a': 'x', 'b': {'c': 1}, 'deep': {'x': {'y': {'z': False}}}},
        {'a': 'x', 'b': {'c': 1}, 'deep': {'x': {'y': {'z': None}}}},
        {'a': 'x', 'b': {'c': 1}, 'withDefault': 'q', 'viaDefault': {}}, {'a': 'x', 'b': {'c': 1}, 'withDefault': 'q', 'viaDefault': {'k': 1}},
    ]
    s.values('hand/required', values)
    base = {'a': 'x', 'b': {'c': 1}, 'withDefault': 'q'}
    for v in values:
        s.case('hand/required', {**base, **v}, 'with required base %s' % compact(v)[:60])
    r = Env()
    s.schema('hand/required-root', r.envelope(r.object({'a': r.string()}, required=True)))
    s.values('hand/required-root', [None, {}, {'a': 'x'}, 'x', []])


def volatile_cases(s):
    e = Env()
    ok = e.object({
        'a': e.string(volatile=True),
        'b': e.object({'c': e.number(volatile=True)}),
        'd': e.object({'e': e.object({'f': e.boolean(volatile=True, default=True)})}),
        'g': e.number(volatile=True, required=True),
    })
    s.schema('hand/volatile-ok', e.envelope(ok))
    s.values('hand/volatile-ok', [
        {'g': 1}, {}, {'g': 1, 'a': 'x'}, {'g': 1, 'a': 5}, {'g': 1, 'b': {'c': 1}}, {'g': 1, 'b': {'c': 'x'}},
        {'g': 1, 'd': {'e': {'f': False}}}, {'g': 1, 'd': {'e': {'f': 'no'}}}, {'g': 'x'}, {'g': None}, None, [], 'x', {'g': 1, 'zz': 1},
    ])
    # a volatile field inside another volatile field (or under array / dict / union / tuple) is refused whatever the value
    def shared_first(n):
        shared = n.number(volatile=True)
        return n.object({'a': shared, 'b': n.array(shared)})

    def shared_last(n):
        shared = n.number(volatile=True)
        return n.object({'b': n.array(shared), 'a': shared})

    refusals = {
        'nested': lambda n: n.object({'a': n.object({'b': n.number(volatile=True)}, volatile=True)}),
        'inArray': lambda n: n.object({'list': n.array(n.number(volatile=True))}),
        'inDict': lambda n: n.object({'map': n.dict(n.string(volatile=True))}),
        'dictKey': lambda n: n.object({'map': n.dict(n.string(), n.string(volatile=True))}),
        'inUnion': lambda n: n.object({'u': n.union([n.string(volatile=True), n.number()])}),
        'inTuple': lambda n: n.object({'t': n.tuple([n.number(volatile=True)])}),
        'inIntersect': lambda n: n.object({'i': n.intersect([n.object({'a': n.number(volatile=True)})])}),
        'rootAndField': lambda n: n.object({'a': n.number(volatile=True)}, volatile=True),
        'sharedFirstFixed': shared_first,
        'sharedLastFixed': shared_last,
        'deepInVolatile': lambda n: n.object(
            {'v': n.object({'x': n.object({'y': n.object({'z': n.string(volatile=True)})})}, volatile=True)}),
    }
    for name, build in refusals.items():
        n = Env()
        s.schema('hand/volatile-' + name, n.envelope(build(n)))
        s.values('hand/volatile-' + name,
                 [{}, None, {'a': {'b': 1}}, {'list': [1]}, {'map': {'k': 'v'}}, {'u': 'x'}, {'t': [1]}, {'a': 1, 'b': [2]}, 5])
    # a root volatile object is fine on its own
    r = Env()
    s.schema('hand/volatile-root', r.envelope(r.object({'a': r.string()}, volatile=True)))
    s.values('hand/volatile-root', [{}, {'a': 'x'}, {'a': 1}, None, 'x', []])
    # a volatile root with a default and a required volatile root
    q = Env()
    s.schema('hand/volatile-required-root', q.envelope(q.string(volatile=True, required=True)))
    s.values('hand/volatile-required-root', [None, 'x', 5, ''])
    # cyclic schema graph: the node refers to itself through a field
    c = Env()
    node_uid = c.next
    c.refs[str(node_uid)] = {'type': 'object', 'meta': {}, 'dict': {}}
    c.next += 1
    number = c.number(min=0)
    c.refs[str(node_uid)]['dict'] = {'n': number, 'child': node_uid}
    s.schema('hand/cyclic', c.envelope(node_uid))
    s.values('hand/cyclic', [{}, {'n': 1}, {'n': -1}, {'child': {'n': 1, 'child': {'n': -1}}}, {'child': {'child': {'child': {}}}},
                              {'child': 5}, {'child': {'n': 'x'}}, None])
    # cycle through a volatile field and through an array (blocked)
    v = Env()
    vid = v.next
    v.refs[str(vid)] = {'type': 'object', 'meta': {'default': {}}, 'dict': {}}
    v.next += 1
    v.refs[str(vid)]['dict'] = {'again': v.array(vid)}
    s.schema('hand/cyclic-array', v.envelope(vid))
    s.values('hand/cyclic-array', [{}, {'again': []}, {'again': [{}]}, {'again': [{'again': [{}]}]}, {'again': [5]}, None])


def misc_type_cases(s):
    e = Env()
    fields = {
        'any': e.any(),
        'anyRequired': e.any(required=True),
        'anyDefault': e.any(default=3),
        'never': e.node('never'),
        'function': e.node('function'),
        'isString': e.node('is', constructor='String'),
        'isNumber': e.node('is', constructor='Number'),
        'isBoolean': e.node('is', constructor='Boolean'),
        'isArray': e.node('is', constructor='Array'),
        'isObject': e.node('is', constructor='Object'),
        'isDate': e.node('is', constructor='Date'),
        'isFunction': e.node('is', constructor='Function'),
        'isRequired': e.node('is', {'required': True}, constructor='String'),
        'unknown': e.node('frobnicate'),
        'untyped': e.add({'meta': {}}),
        'noMeta': e.add({'type': 'string'}),
        'metaNull': e.add({'type': 'string', 'meta': None}),
        'metaString': e.add({'type': 'string', 'meta': 'x'}),
        'transformKeep': e.node('transform', inner=e.number(min=0), callback='(value) => value', preserve=True),
        'transformAdapt': e.node('transform', inner=e.number(min=0), callback='(value) => value', preserve=False),
        'transformString': e.node('transform', inner=e.string(min=2), callback='(value) => value'),
        'transformInUnion': e.union([e.const('none'), e.node('transform', inner=e.number(), callback='(value) => value', preserve=True)]),
        'unionWithIs': e.union([e.node('is', constructor='Date'), e.string(min=3)]),
    }
    s.schema('hand/misc', e.envelope(e.object(fields)))
    values = [1, 0, -1, 1.5, 'x', 'ab', 'abc', '', True, False, [], [1], {}, {'a': 1}, None, 'none']
    exact_fields = ['any', 'anyRequired', 'anyDefault', 'never', 'function', 'isString', 'isNumber', 'isBoolean', 'isArray', 'isObject',
                    'isDate', 'isFunction', 'isRequired', 'unknown', 'transformKeep', 'transformAdapt', 'transformString',
                    'transformInUnion', 'unionWithIs']
    for field in exact_fields:
        for v in values:
            s.case('hand/misc', {'anyRequired': 1, 'isRequired': 'x', field: v}, '%s=%s' % (field, compact(v)))
    for field in ('untyped', 'noMeta', 'metaNull', 'metaString'):
        for v in (None, 'x', 1):
            s.case('hand/misc', {'anyRequired': 1, 'isRequired': 'x', field: v}, '%s=%s' % (field, compact(v)))
    # whole-value shapes against non-object roots
    for kind, root in (
        ('string', lambda r: r.string(min=1)),
        ('number', lambda r: r.number(step=1)),
        ('array', lambda r: r.array(r.number())),
        ('union', lambda r: r.union([r.const('a'), r.number()])),
        ('const', lambda r: r.const('a')),
        ('boolean', lambda r: r.boolean(default=True)),
    ):
        r = Env()
        s.schema('hand/root-' + kind, r.envelope(root(r)))
        s.values('hand/root-' + kind, [None, 'a', '', 1, 1.5, True, [], [1], {}, {'a': 1}])
    # defaults are themselves validated
    d = Env()
    dflt = {
        'minVsDefault': d.number(min=5, default=1),
        'typeVsDefault': d.string(default=5),
        'arrayMinVsDefault': d.array(d.string(), min=1),
        'objectDefault': d.object({'n': d.number(min=5)}, default={'n': 1}),
        'goodDefault': d.object({'n': d.number(min=5)}, default={'n': 9}),
        'unionDefault': d.union([d.const('a'), d.const('b')], default='c'),
        'dictDefault': d.dict(d.number(min=1), default={'k': 0}),
        'tupleDefault': d.tuple([d.string()], default=[5]),
        'requiredDefault': d.object({'k': d.string(required=True)}, default={}),
    }
    s.schema('hand/defaults', d.envelope(d.object(dflt)))
    s.case('hand/defaults', {}, 'every default checked')
    for field in dflt:
        s.case('hand/defaults', {field: None}, '%s=null' % field)
    for field in ('goodDefault',):
        s.case('hand/defaults', {field: {'n': 9}}, '%s given' % field)
    # field names that exist on every JavaScript object: absent keys read the inherited member
    inherited = Env()
    s.schema('hand/inherited-names', inherited.envelope(inherited.object({
        'constructor': inherited.string(),
        'toString': inherited.number(),
        'valueOf': inherited.any(),
        'hasOwnProperty': inherited.node('function'),
    })))
    s.values('hand/inherited-names', [{}, {'constructor': 'x'}, {'constructor': 'x', 'toString': 1}, None,
                                      {'constructor': 'x', 'toString': 1, 'hasOwnProperty': None}], exact=False)


def malformed_cases(s):
    good = Env()
    uid = good.object({'a': good.number(min=0)})
    good_env = good.envelope(uid)
    values = [None, {}, {'a': 1}, {'a': -1}, 'x', 5, []]

    def bad(label, envelope):
        for v in values:
            s.case(envelope, v, '%s %s' % (label, compact(v)), exact=False, inline=True)

    bad('null envelope', None)
    bad('number envelope', 5)
    bad('string envelope', 'x')
    bad('array envelope', [])
    bad('empty envelope', {})
    bad('uid only', {'uid': 1})
    bad('empty refs', {'uid': 1, 'refs': {}})
    bad('refs number', {'uid': 1, 'refs': 5})
    bad('refs null', {'uid': 1, 'refs': None})
    bad('refs array', {'uid': 1, 'refs': []})
    bad('uid absent from refs', {'uid': 99, 'refs': {'1': {'type': 'string', 'meta': {}}}})
    bad('uid null', {'uid': None, 'refs': {'1': {'type': 'string', 'meta': {}}}})
    bad('null node', {'uid': 1, 'refs': {'1': None}})
    bad('unused null node', {'uid': good_env['uid'], 'refs': dict(good_env['refs'], **{'999': None})})
    bad('number node', {'uid': 1, 'refs': {'1': 5}})
    bad('string node', {'uid': 1, 'refs': {'1': 'abc'}})
    bad('array node', {'uid': 1, 'refs': {'1': []}})
    bad('node without type', {'uid': 1, 'refs': {'1': {'meta': {}}}})
    bad('unknown type', {'uid': 1, 'refs': {'1': {'type': 'frobnicate', 'meta': {}}}})
    bad('lazy without inner', {'uid': 1, 'refs': {'1': {'type': 'lazy', 'meta': {}}}})
    bad('dangling dict field', {'uid': 2, 'refs': {'2': {'type': 'object', 'meta': {'default': {}}, 'dict': {'a': 77}}}})
    bad('dangling dict value', {'uid': 2, 'refs': {'2': {'type': 'dict', 'meta': {'default': {}}, 'inner': 77}}})
    bad('dict without inner', {'uid': 2, 'refs': {'2': {'type': 'dict', 'meta': {'default': {}}}}})
    bad('dangling dict key', {'uid': 3, 'refs': {'2': {'type': 'number', 'meta': {}}, '3': {'type': 'dict', 'meta': {'default': {}}, 'inner': 2, 'sKey': 77}}})
    bad('array without inner', {'uid': 2, 'refs': {'2': {'type': 'array', 'meta': {'default': []}}}})
    bad('dangling array inner', {'uid': 2, 'refs': {'2': {'type': 'array', 'meta': {'default': []}, 'inner': 77}}})
    bad('dangling union member', {'uid': 3, 'refs': {'2': {'type': 'string', 'meta': {}}, '3': {'type': 'union', 'meta': {}, 'list': [77, 2]}}})
    bad('dangling union only member', {'uid': 3, 'refs': {'3': {'type': 'union', 'meta': {}, 'list': [77]}}})
    bad('union without list', {'uid': 2, 'refs': {'2': {'type': 'union', 'meta': {}}}})
    bad('union list not array', {'uid': 2, 'refs': {'2': {'type': 'union', 'meta': {}, 'list': 5}}})
    bad('intersect without list', {'uid': 2, 'refs': {'2': {'type': 'intersect', 'meta': {}}}})
    bad('tuple without list', {'uid': 2, 'refs': {'2': {'type': 'tuple', 'meta': {'default': []}}}})
    bad('dangling tuple member', {'uid': 3, 'refs': {'3': {'type': 'tuple', 'meta': {'default': []}, 'list': [77, 77]}}})
    bad('object without dict', {'uid': 2, 'refs': {'2': {'type': 'object', 'meta': {'default': {}}}}})
    bad('bitset without bits', {'uid': 2, 'refs': {'2': {'type': 'bitset', 'meta': {'default': 0}}}})
    bad('const without value', {'uid': 2, 'refs': {'2': {'type': 'const', 'meta': {'required': True}}}})
    bad('transform without inner', {'uid': 2, 'refs': {'2': {'type': 'transform', 'meta': {}, 'callback': '(v) => v'}}})
    bad('is without constructor', {'uid': 2, 'refs': {'2': {'type': 'is', 'meta': {}}}})
    bad('uid as string key', {'uid': 'root', 'refs': {'root': {'type': 'string', 'meta': {}}}})
    bad('uid as string number', {'uid': '1', 'refs': {'1': {'type': 'string', 'meta': {}}}})
    # a well formed envelope with unrelated extras is still fine
    ok = json.loads(json.dumps(good_env))
    ok['extra'] = {'x': 1}
    ok['refs']['500'] = {'type': 'frobnicate', 'meta': {}}
    for v in values:
        s.case(ok, v, 'extras ignored %s' % compact(v), inline=True)


def schema_fixture():
    s = Schemas()
    describe_cases(s)
    number_cases(s)
    string_cases(s)
    union_cases(s)
    const_cases(s)
    dict_cases(s)
    array_cases(s)
    tuple_cases(s)
    intersect_cases(s)
    bitset_cases(s)
    loose_cases(s)
    required_cases(s)
    volatile_cases(s)
    misc_type_cases(s)
    malformed_cases(s)
    return {
        'format': 'dsh-settings-vector/1',
        'kind': 'schema',
        'description': 'Serialized settings schemas (the namespaces of a real settings.describe answer plus hand-built '
                       'schemas covering every schemastery resolver) against many values. `expect` is null when dsh\'s '
                       'own SettingsSchemaService accepts the value, else its failure text; `messageExact: false` '
                       'compares the verdict only (the text depends on the JavaScript engine). Inputs: '
                       'tool/vectors/synth_settings_trace.py.',
        'hostVersion': '0.2.1-rc.2',
        'schemas': s.schemas,
        'cases': s.cases,
    }


# ===================================================================== form / form-model


class Trace:
    """Builds the flat step list of a form vector; every `start` begins a fresh world."""

    def __init__(self):
        self.steps = []
        with open(DESCRIBE, encoding='utf-8') as handle:
            self.rows = {row['ns']: row for row in json.load(handle)['namespaces']}

    def add(self, op, **fields):
        step = {'op': op}
        step.update(fields)
        self.steps.append(step)

    def view(self, ns, revision=0, value=None, user=None, base=None, drop=()):
        row = json.loads(json.dumps(self.rows[ns]))
        row['revision'] = revision
        if value is not None:
            row['value'] = value
        if user is not None:
            row['user'] = user
        if base is not None:
            row['base'] = base
        for key in drop:
            row.pop(key, None)
        return row

    @staticmethod
    def described(*views, writable=True, has_document=True):
        return {'ok': True, 'value': {'writable': writable, 'hasDocument': has_document, 'namespaces': list(views)}}

    def start(self, name):
        self.add('start', name=name)

    def answer(self, method, result, comment=None):
        step = {'method': method, 'result': result}
        if comment:
            step['comment'] = comment
        self.add('answer', **step)

    def describe_ok(self, *views, **kw):
        self.answer('describe', self.described(*views, **kw))

    def describe_refused(self, message, code='settings/internal'):
        self.answer('describe', {'ok': False, 'error': {'code': code, 'message': message}})

    def mutate_ok(self, view):
        self.answer('mutate', {'ok': True, 'value': view})

    def mutate_refused(self, message, code='settings/conflict'):
        self.answer('mutate', {'ok': False, 'error': {'code': code, 'message': message}})

    def transport_failure(self, method, message):
        self.answer(method, {'throw': message})

    def watch(self, *namespaces):
        for ns in namespaces:
            self.add('watch', ns=ns)

    def emit_updated(self, ns='ui-theme', revision=1):
        self.add('emit', event='settings/document-updated', args=[ns, revision])

    def reset(self):
        self.add('reset')

    def set(self, id_, ns, field, value):
        self.add('set', id=id_, ns=ns, field=field, value=value)

    def unset(self, id_, ns, field):
        self.add('unset', id=id_, ns=ns, field=field)

    def mutate(self, id_, ns, ops, expected_revision=None):
        step = {'id': id_, 'ns': ns, 'ops': ops}
        if expected_revision is not None:
            step['expectedRevision'] = expected_revision
        self.add('mutate', **step)


THEME = {'preference': 'system', 'fontSize': 14, 'codeFontSize': 11, 'terminalFontSize': 13,
         'textFontFamily': '', 'codeFontFamily': '', 'terminalFontFamily': ''}


def theme(**changes):
    return dict(THEME, **changes)


def form_fixture():
    tr = Trace()
    v = tr.view

    # 1. first read: eager read at startup, forms for served and unserved namespaces, document and reset invalidations
    tr.start('first read')
    tr.describe_ok(v('ui-theme'), v('agent-loop'))
    tr.watch('ui-theme', 'agent-loop', 'not-served')
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=16), user={'fontSize': 16}), v('agent-loop'))
    tr.emit_updated('ui-theme', 1)
    tr.describe_ok(v('ui-theme', 2, theme(fontSize=18), user={'fontSize': 18}), v('agent-loop', 1, {'maxParallelToolCalls': 4}, user={'maxParallelToolCalls': 4}))
    tr.reset()
    tr.add('ensure')
    tr.describe_ok(v('ui-theme', 2), v('agent-loop', 1), writable=False)
    tr.emit_updated('agent-loop', 1)

    # 2. read failure then retry; a later failure keeps serving the held view
    tr.start('read failure then retry')
    tr.describe_refused('read failed')
    tr.watch('ui-theme')
    tr.describe_ok(v('ui-theme'))
    tr.add('ensure')
    tr.add('ensure')
    tr.transport_failure('describe', 'socket closed')
    tr.emit_updated()
    tr.describe_refused('host busy', 'settings/busy')
    tr.reset()
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.emit_updated()
    tr.add('ensure')

    # 3. a first read that throws before anything is held falls back to idle and ensure reads again
    tr.start('transport failure of the first read')
    tr.transport_failure('describe', 'dial failed')
    tr.watch('ui-theme')
    tr.add('ensure')
    tr.describe_ok(v('ui-theme'))
    tr.add('ensure')

    # 4. invalid sections stay out; the revision, base and user still follow the Host
    tr.start('invalid section kept out')
    tr.describe_ok(v('ui-theme', 0, theme(fontSize=99)), v('agent-loop', 0, {'maxParallelToolCalls': 0}))
    tr.watch('ui-theme', 'agent-loop')
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=12), user={'fontSize': 12}), v('agent-loop', 1, {'maxParallelToolCalls': 3}, user={'maxParallelToolCalls': 3}))
    tr.emit_updated()
    tr.describe_ok(v('ui-theme', 2, theme(fontSize=14.5), user={'fontSize': 14.5}), v('agent-loop', 2, [], user={'x': 1}))
    tr.emit_updated()
    tr.describe_ok(v('ui-theme', 3, theme(preference='sepia'), user={'preference': 'sepia'}), v('agent-loop', 3, None))
    tr.emit_updated()
    tr.describe_ok(v('ui-theme', 4, 'text'), v('agent-loop', 4, {'maxParallelToolCalls': 5}, user={'maxParallelToolCalls': 5}))
    tr.emit_updated()
    tr.describe_ok(v('ui-theme', 5, {}, user={}), v('agent-loop', 5, {'extra': True, 'maxParallelToolCalls': 5}))
    tr.emit_updated()

    # 5. a namespace the Host does not serve, then serves, then stops serving; whileServed follows it
    tr.start('namespace unserved then served')
    tr.describe_ok(v('ui-theme'))
    tr.watch('agent-loop')
    tr.add('whileServed', id='page', namespaces=['agent-loop', 'permission'])
    tr.add('whileServed', id='other', namespaces=['ui-theme'])
    tr.describe_ok(v('ui-theme', 1), v('agent-loop', 0))
    tr.emit_updated()
    tr.describe_ok(v('ui-theme', 2), v('agent-loop', 1, {'maxParallelToolCalls': 2}, user={'maxParallelToolCalls': 2}), v('permission'))
    tr.emit_updated()
    tr.describe_ok(v('ui-theme', 3), v('permission', 1))
    tr.emit_updated()
    tr.describe_ok(v('ui-theme', 4), v('agent-loop', 2))
    tr.emit_updated()
    tr.add('stopWhileServed', id='other')
    tr.describe_ok(v('ui-theme', 5))
    tr.emit_updated()
    tr.add('stopWhileServed', id='page')

    # 6. rapid ordered writes: one wire call at a time, revisions chained through superseded answers
    tr.start('rapid ordered writes')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.set('w1', 'ui-theme', 'fontSize', 15)
    tr.set('w2', 'ui-theme', 'fontSize', 16)
    tr.unset('w3', 'ui-theme', 'codeFontSize')
    tr.set('w4', 'ui-theme', 'preference', 'dark')
    tr.mutate_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.mutate_ok(v('ui-theme', 2, theme(fontSize=16), user={'fontSize': 16}))
    tr.mutate_ok(v('ui-theme', 5, theme(fontSize=16), user={'fontSize': 16}))
    tr.mutate_ok(v('ui-theme', 6, theme(fontSize=16, preference='dark'), user={'fontSize': 16, 'preference': 'dark'}))
    tr.set('w5', 'ui-theme', 'fontSize', 17)
    tr.mutate_ok(v('ui-theme', 7, theme(fontSize=17, preference='dark'), user={'fontSize': 17, 'preference': 'dark'}))

    # 7. an explicit fence, multi-op mutations and the values copied when queued
    tr.start('explicit revision and multi-op mutate')
    tr.describe_ok(v('ui-theme', 3))
    tr.watch('ui-theme')
    tr.mutate('m1', 'ui-theme', [{'op': 'set', 'path': ['fontSize'], 'value': 20}, {'op': 'unset', 'path': ['codeFontSize']},
                                  {'op': 'set', 'path': ['nested', 'deep'], 'value': {'k': [1, 2]}}], expected_revision=1)
    tr.mutate('m2', 'ui-theme', [{'op': 'unset', 'path': ['fontSize']}])
    tr.mutate_ok(v('ui-theme', 4, theme(fontSize=20), user={'fontSize': 20}))
    tr.mutate_ok(v('ui-theme', 5, theme(), user={}))
    tr.mutate('m3', 'ui-theme', [], expected_revision=0)
    tr.mutate_ok(v('ui-theme', 6))

    # 8. a refused latest write reloads Host state; the write resolves false after the recovery read
    tr.start('refused write then recovery read')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.set('w1', 'ui-theme', 'fontSize', 30)
    tr.mutate_refused('fontSize out of range')
    tr.describe_ok(v('ui-theme', 0))
    tr.set('w2', 'ui-theme', 'fontSize', 17)
    tr.mutate_refused('stale revision')
    tr.describe_ok(v('ui-theme', 4, theme(fontSize=19), user={'fontSize': 19}))
    tr.set('w3', 'ui-theme', 'fontSize', 18)
    tr.mutate_ok(v('ui-theme', 5, theme(fontSize=18), user={'fontSize': 18}))

    # 9. a refused write that was superseded leaves recovery to its successor
    tr.start('refused superseded write')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.set('w1', 'ui-theme', 'fontSize', 30)
    tr.set('w2', 'ui-theme', 'fontSize', 12)
    tr.mutate_refused('first refused')
    tr.mutate_ok(v('ui-theme', 1, theme(fontSize=12), user={'fontSize': 12}))
    tr.set('w3', 'ui-theme', 'fontSize', 31)
    tr.set('w4', 'ui-theme', 'fontSize', 32)
    tr.mutate_ok(v('ui-theme', 2, theme(fontSize=31), user={'fontSize': 31}))
    tr.mutate_refused('latest refused')
    tr.describe_ok(v('ui-theme', 2, theme(fontSize=31), user={'fontSize': 31}))

    # 10. transport failures reject the write, the queue continues, no recovery read
    tr.start('transport failure of a write')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.set('w1', 'ui-theme', 'fontSize', 15)
    tr.transport_failure('mutate', 'connection lost')
    tr.set('w2', 'ui-theme', 'fontSize', 16)
    tr.set('w3', 'ui-theme', 'fontSize', 17)
    tr.transport_failure('mutate', 'timeout')
    tr.mutate_ok(v('ui-theme', 1, theme(fontSize=17), user={'fontSize': 17}))
    tr.set('w4', 'ui-theme', 'fontSize', 18)
    tr.mutate_ok(v('ui-theme', 2, theme(fontSize=18), user={'fontSize': 18}))

    # 11. a write before the first read carries no revision; its answer is not published as a partial document
    tr.start('write before the first read')
    tr.watch('ui-theme')
    tr.set('w1', 'ui-theme', 'fontSize', 15)
    tr.mutate_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.set('w2', 'ui-theme', 'fontSize', 16)
    tr.mutate_ok(v('ui-theme', 2, theme(fontSize=16), user={'fontSize': 16}))

    # 12. a write answer overtakes a read in flight: the stale read is dropped and read again
    tr.start('write answer versus read in flight')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.emit_updated('ui-theme', 1)
    tr.set('w1', 'ui-theme', 'fontSize', 15)
    tr.mutate_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.describe_ok(v('ui-theme', 0))
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.emit_updated('ui-theme', 2)
    tr.emit_updated('ui-theme', 2)
    tr.reset()
    tr.describe_ok(v('ui-theme', 1))
    tr.describe_ok(v('ui-theme', 2, theme(fontSize=13), user={'fontSize': 13}))
    tr.set('w2', 'ui-theme', 'fontSize', 14)
    tr.emit_updated('ui-theme', 3)
    tr.describe_ok(v('ui-theme', 3, theme(fontSize=14), user={'fontSize': 14}))
    tr.mutate_ok(v('ui-theme', 3, theme(fontSize=14), user={'fontSize': 14}))

    # 13. a refused write whose recovery read is already folded into a running read
    tr.start('refused write while a read is in flight')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.emit_updated()
    tr.set('w1', 'ui-theme', 'fontSize', 30)
    tr.mutate_refused('too large')
    tr.describe_ok(v('ui-theme', 0))
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=11), user={'fontSize': 11}))

    # 14. acceptView folds a namespace answer into the held view (and appends an unknown one)
    tr.start('accept view')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme', 'agent-loop')
    tr.add('acceptView', view=v('ui-theme', 3, theme(fontSize=21), user={'fontSize': 21}))
    tr.add('acceptView', view=v('agent-loop', 1, {'maxParallelToolCalls': 6}, user={'maxParallelToolCalls': 6}))
    tr.emit_updated()
    tr.add('acceptView', view=v('ui-theme', 4, theme(fontSize=22), user={'fontSize': 22}))
    tr.describe_ok(v('ui-theme', 3))
    tr.describe_ok(v('ui-theme', 4, theme(fontSize=22), user={'fontSize': 22}))

    # 15. a document that does not accept writes and a missing document
    tr.start('read-only document')
    tr.describe_ok(v('ui-theme', 0), writable=False, has_document=False)
    tr.watch('ui-theme')
    tr.set('w1', 'ui-theme', 'fontSize', 15)
    tr.mutate_refused('settings document is read-only', 'settings/read-only')
    tr.describe_ok(v('ui-theme', 0), writable=False, has_document=False)

    # 16. a namespace row without base or user layers
    tr.start('layers absent')
    tr.describe_ok(v('ui-theme', 0, drop=('base', 'user')), v('agent-loop', 0, drop=('user',)))
    tr.watch('ui-theme', 'agent-loop')
    tr.describe_ok(v('ui-theme', 1, drop=('base',), user={'fontSize': 12}), v('agent-loop', 1, drop=('base',)))
    tr.emit_updated()

    # 17. dispose: the write already on the wire settles unpublished, later events and writes do nothing
    tr.start('dispose')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.set('w1', 'ui-theme', 'fontSize', 15)
    tr.set('w2', 'ui-theme', 'fontSize', 16)
    tr.add('dispose')
    tr.mutate_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.emit_updated('ui-theme', 2)
    tr.reset()
    tr.set('w3', 'ui-theme', 'fontSize', 17)
    tr.add('ensure')

    # 18. dispose while a read is in flight and while a refused write would recover
    tr.start('dispose with a read and a refused write pending')
    tr.describe_ok(v('ui-theme', 0))
    tr.watch('ui-theme')
    tr.emit_updated()
    tr.set('w1', 'ui-theme', 'fontSize', 15)
    tr.add('dispose')
    tr.mutate_refused('refused after dispose')
    tr.describe_ok(v('ui-theme', 1, theme(fontSize=15), user={'fontSize': 15}))
    tr.emit_updated('ui-theme', 2)

    return {
        'format': 'dsh-settings-vector/1',
        'kind': 'form',
        'description': 'Scripted traces through dsh\'s settings describe mirror and configuration forms (the real ui-settings '
                       'plugin over a scripted settings remote). Every `start` begins a fresh world; `answer` steps answer '
                       'the oldest pending settings.describe / settings.mutate call (or queue for the next one). '
                       '`expected` is the state after each step. Inputs: tool/vectors/synth_settings_trace.py.',
        'hostVersion': '0.2.1-rc.2',
        'steps': tr.steps,
    }


def model_fixture():
    steps = []

    def add(op, **fields):
        step = {'op': op}
        step.update(fields)
        steps.append(step)

    def snap(status='ready', value=None, base=None, user=None, writable=True, revision=3):
        out = {'status': status, 'writable': writable}
        if value is not None:
            out['value'] = value
        if base is not None:
            out['base'] = base
        if user is not None:
            out['user'] = user
        if revision is not None:
            out['revision'] = revision
        return out

    specs = [{'field': 'fontSize', 'kind': 'number'}, {'field': 'textFontFamily', 'kind': 'text'}]
    section = {'fontSize': 14, 'textFontFamily': ''}
    ready = snap(value=section, base={'fontSize': 14, 'textFontFamily': ''}, user={})

    def start(name, snapshot=None, **extra):
        add('start', name=name, specs=specs, snapshot=snapshot or ready, **extra)

    def edit(field, text):
        add('edit', field=field, text=text)

    def answer(method, result, scope=None):
        step = {'method': method, 'result': result}
        if scope is not None:
            step['scope'] = scope
        add('answer', **step)

    # 1. staging: edits preview the save, an edit equal to the stored text is not dirty, an invalid draft blocks
    start('staging')
    edit('fontSize', '16')
    edit('fontSize', '14')
    edit('fontSize', '')
    edit('fontSize', 'abc')
    add('save')
    edit('fontSize', '15')
    edit('textFontFamily', '  Inter  ')
    edit('textFontFamily', '')
    edit('textFontFamily', 'Inter')
    add('discard')
    add('discard')

    # 2. every spelling of a number the field either accepts or refuses
    start('number drafts')
    for text in ['16', ' 12 ', '1e2', '0x10', '0b11', '0o7', '-0x1', '+5', '-5', '.5', '5.', '1_000', '1e999', 'Infinity', '-Infinity',
                 'NaN', '-0', '0', '1.5e-7', '123456789012345680000', '1e21', '12px', '', '   ', '\u00a07', '\u00857', '\ufeff9',
                 '\u20287', '१२', '１２', '1 2', '1,5', '٣', '0.1', '2e', 'e2', '++1', '1e+2', '1E2', '0X1f', '00012', '1.', '.', '-.5e1']:
        edit('fontSize', text)
    add('discard')

    # 3. a save writes the staged ops fenced with the revision the first edit started from
    start('save lands')
    edit('fontSize', '18')
    add('scope', snapshot=snap(value={'fontSize': 14, 'textFontFamily': 'x'}, base={'fontSize': 14, 'textFontFamily': ''}, user={'textFontFamily': 'x'}, revision=4))
    edit('textFontFamily', 'Inter')
    add('save')
    add('save')
    edit('fontSize', '19')
    answer('mutate', True, snap(value={'fontSize': 18, 'textFontFamily': 'Inter'}, base={'fontSize': 14, 'textFontFamily': ''}, user={'fontSize': 18, 'textFontFamily': 'Inter'}, revision=5))
    add('discard')
    edit('fontSize', '20')
    add('save')
    answer('mutate', True, snap(value={'fontSize': 20, 'textFontFamily': 'Inter'}, base={'fontSize': 14, 'textFontFamily': ''}, user={'fontSize': 20, 'textFontFamily': 'Inter'}, revision=6))

    # 4. a refused or failed save keeps the drafts and flags the form; the next edit or save clears the flag
    start('save refused or failed')
    edit('fontSize', '30')
    add('save')
    answer('mutate', False)
    edit('fontSize', '31')
    add('save')
    answer('mutate', {'throw': 'connection lost'})
    add('save')
    answer('mutate', False)
    add('discard')
    add('discard')

    # 5. reset stages a clear back to the composition value; it writes only when the user layer holds the field
    clear_base = {'fontSize': 14, 'textFontFamily': 'Default'}
    start('reset field', snap(value={'fontSize': 18, 'textFontFamily': 'Default'}, base=clear_base, user={'fontSize': 18}))
    add('reset', field='fontSize')
    add('reset', field='textFontFamily')
    add('save')
    answer('mutate', True, snap(value={'fontSize': 14, 'textFontFamily': 'Default'}, base=clear_base, user={}, revision=4))
    add('reset', field='nope')
    edit('textFontFamily', 'Mono')
    add('reset', field='textFontFamily')
    edit('fontSize', '')
    add('save')

    # 6. the badge answers for the user layer's presence, not for a value comparison
    start('overridden is presence', snap(value={'fontSize': 14, 'textFontFamily': ''}, base={'fontSize': 14, 'textFontFamily': ''}, user={'fontSize': 14}))
    edit('textFontFamily', 'x')
    edit('fontSize', '14')
    edit('fontSize', '15')
    add('discard')
    add('scope', snapshot=snap(value={'fontSize': 14, 'textFontFamily': ''}, base={'fontSize': 14, 'textFontFamily': ''}, user={}))
    add('scope', snapshot=snap(value={'fontSize': 14, 'textFontFamily': ''}, base={'fontSize': 14, 'textFontFamily': ''}, user={'textFontFamily': ''}))
    add('scope', snapshot=snap(value={'fontSize': 14, 'textFontFamily': ''}, base={'fontSize': 14, 'textFontFamily': ''}))

    # 7. the scope not serving the entry, or the document read-only
    start('unavailable and read-only', snap(status='loading', revision=None, writable=False))
    edit('fontSize', '16')
    add('save')
    add('scope', snapshot=snap(value=section, base=section, user={}, writable=False))
    add('save')
    add('scope', snapshot=snap(status='unavailable', value=section, base=section, user={}))
    add('scope', snapshot=snap(value={'fontSize': 'big', 'textFontFamily': 5}, base=section, user={}))
    edit('fontSize', '14')
    add('scope', snapshot=snap(value={}, base=section, user={}))
    add('scope', snapshot=snap(value=None, base=None, user=None))
    add('scope', snapshot=snap(value={'fontSize': 1e21, 'textFontFamily': 'ok'}, base=section, user={}))
    add('scope', snapshot=snap(value={'fontSize': 1.5e-7, 'textFontFamily': 'ok'}, base=section, user={}))
    add('scope', snapshot=snap(value={'fontSize': -0.0, 'textFontFamily': 'ok'}, base=section, user={}))
    add('scope', snapshot=snap(value={'fontSize': 123456789.125, 'textFontFamily': 'ok'}, base=section, user={}))

    # 8. secrets: write-only controls written outside the section, blank drafts write nothing
    secret_specs = {'secrets': ['apiKey', 'otherKey']}
    start('secrets', **secret_specs)
    edit('apiKey', '   ')
    edit('apiKey', ' sk-test ')
    edit('otherKey', 'second')
    add('save')
    answer('secret:apiKey', True)
    answer('secret:otherKey', False)
    edit('fontSize', '17')
    add('save')
    answer('mutate', True, snap(value={'fontSize': 17, 'textFontFamily': ''}, base=section, user={'fontSize': 17}, revision=4))
    answer('secret:apiKey', {'throw': 'keychain locked'})
    add('save')
    answer('secret:apiKey', True)
    answer('secret:otherKey', True)
    edit('otherKey', 'only')
    add('save')
    answer('secret:otherKey', False)
    add('discard')
    edit('apiKey', 'late')
    add('save')
    answer('secret:apiKey', True)

    # 9. scope changes under drafts; a pending save blocks a second one; dispose releases the subscription
    start('scope changes under drafts')
    edit('fontSize', '16')
    add('scope', snapshot=snap(value={'fontSize': 15, 'textFontFamily': 'x'}, base=section, user={'fontSize': 15, 'textFontFamily': 'x'}, revision=9))
    edit('textFontFamily', 'y')
    add('save')
    add('scope', snapshot=snap(value={'fontSize': 12, 'textFontFamily': 'x'}, base=section, user={'fontSize': 12}, revision=10))
    edit('fontSize', '13')
    answer('mutate', True, snap(value={'fontSize': 16, 'textFontFamily': 'y'}, base=section, user={'fontSize': 16, 'textFontFamily': 'y'}, revision=11))
    edit('fontSize', '17')
    add('dispose')
    add('scope', snapshot=snap(value={'fontSize': 20, 'textFontFamily': 'z'}, base=section, user={}, revision=12))
    edit('fontSize', '18')

    # 10. an answer that arrives before its call waits for it
    start('early answer')
    answer('mutate', True, snap(value={'fontSize': 22, 'textFontFamily': ''}, base=section, user={'fontSize': 22}, revision=4))
    edit('fontSize', '22')
    add('save')

    return {
        'format': 'dsh-settings-vector/1',
        'kind': 'form-model',
        'description': 'Scripted scope snapshots, edits and write outcomes through dsh\'s staged settings form model '
                       '(ui-primitives SettingsFormModel with the number and text field specs). `expected` is the model state '
                       'after each step; every `start` begins a fresh model. Inputs: tool/vectors/synth_settings_trace.py.',
        'hostVersion': '0.2.1-rc.2',
        'steps': steps,
    }


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('schema', 'form', 'form-model'):
        print(__doc__)
        return 2
    out = {'schema': schema_fixture, 'form': form_fixture, 'form-model': model_fixture}[sys.argv[1]]()
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_settings_expected import dump
    with open(sys.argv[2], 'w', encoding='utf-8') as handle:
        handle.write(dump(out))
    count = len(out['cases']) if out['kind'] == 'schema' else len(out['steps'])
    print('synth_settings_trace: %s, %d %s' % (out['kind'], count, 'cases' if out['kind'] == 'schema' else 'steps'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
