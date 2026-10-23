#!/usr/bin/env python3
"""Generate the official dsh theme pack from dsh's own stylesheets.

Reads the pinned dsh checkout (argument --src, env DSH_SRC, default
<repo>/.local/dsh-src), parses the `--dsw-*` token sheets of
packages/client/ui-theme, and writes three generated files into
packages/dsh_theme:

  assets/themes/official.theme.json   the pack (format "dsh-theme/1")
  lib/src/official_pack.g.dart        the same pack as a Dart const map
  lib/src/contract_names.g.dart       every contract token name and its kind

Usage:
  build_official_pack.py [--src DIR] [--write]   write (default)
  build_official_pack.py [--src DIR] --check     exit 1 if committed output differs

Python 3 standard library only. Output is deterministic: sorted keys and fixed
formatting, no timestamps.

Naming decision (documented once): pack keys are the EXACT CSS custom property
names as dsh writes them, with their leading `--` (`--dsw-alias-bg-base`,
`--dsh-scrollbar-width`, `--shiki-token-string`). Nothing is renamed.

What is a contract token: every custom property the token sheets declare on
`:root`, `body` or `body[data-ds-dark-theme]`, except
  * runtime inputs and values derived from them (`--dsh-content-font-size`,
    `--dsh-content-font-delta`, ...): these come from ThemeSettings in Dart;
  * font-family composites (`--dsw-font-family`, `--ds-font-family-code`,
    `--dsh-font-family-*-default`, `--dsw-font-family-brand`): these become the
    pack's `fonts` stacks (text, code, brand; terminal comes from the terminal
    package source).
The typography ladder is keyed by the shorthand name (`--dsw-font-s-14`); its
`-font-family/-font-weight/-line-height/-font-size/-font-style` longhands are
folded into it and cross-checked against the shorthand.

Token kinds: color, number (px; durations in ms), shadow, gradient,
typography, string (raw CSS kept verbatim).
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
THEME_PKG = REPO / 'packages' / 'dsh_theme'
OUT_JSON = THEME_PKG / 'assets' / 'themes' / 'official.theme.json'
OUT_PACK_DART = THEME_PKG / 'lib' / 'src' / 'official_pack.g.dart'
OUT_NAMES_DART = THEME_PKG / 'lib' / 'src' / 'contract_names.g.dart'

DEFAULT_SRC = str(REPO / '.local' / 'dsh-src')
THEME_REL = 'packages/client/ui-theme/src/styles'
# Import order of ui-theme's client entry; later sheets win within one scope.
SHEETS = [
    'base.css', 'corner-shape.css', 'design-platform.css', 'focus.css',
    'onboarding.css', 'scrollbar.css', 'gradient-shadow-text.css', 'shiki.css',
]
TERMINAL_REL = 'packages/client/ui-sidebar-terminal/src/client/terminal.tsx'

PACK_FORMAT = 'dsh-theme/1'
KINDS = ('color', 'number', 'shadow', 'gradient', 'typography', 'string')
TABLE_FOR_KIND = {
    'color': 'colors', 'number': 'numbers', 'shadow': 'shadows',
    'gradient': 'gradients', 'typography': 'typography', 'string': 'strings',
}

# Runtime inputs written on body by the boot script / presenter, and values
# computed from them. They are not theme data; ThemeSettings reproduces them.
RUNTIME = {
    '--dsh-content-font-size', '--dsh-code-font-size', '--dsh-terminal-font-size',
    '--dsh-font-family-text', '--dsh-font-family-code', '--dsh-font-family-terminal',
    '--dsh-content-font-delta', '--dsh-content-font-size-secondary',
    '--dsh-content-font-delta-secondary', '--dsh-code-font-delta',
}
# Font composites that become `fonts` stacks instead of tokens.
FONT_VARS = {
    '--dsw-font-family', '--ds-font-family-code', '--dsw-font-family-brand',
    '--dsh-font-family-text-default', '--dsh-font-family-code-default',
}
LONGHAND = re.compile(r'^(--dsw-font-.+)-(font-family|font-weight|line-height|font-size|font-style)$')
GENERIC_FAMILIES = {
    'serif', 'sans-serif', 'monospace', 'cursive', 'fantasy', 'system-ui', 'ui-serif',
    'ui-sans-serif', 'ui-monospace', 'ui-rounded', 'emoji', 'math', 'fangsong',
    '-apple-system', 'blinkmacsystemfont',
}


class Report:
    def __init__(self) -> None:
        self.unresolved: list[str] = []
        self.excluded: list[str] = []
        self.skipped_scopes: list[str] = []
        self.notes: list[str] = []
        self.declared = 0
        self.distinct = 0
        self.folded = 0


# ---------------------------------------------------------------- CSS parsing

def strip_comments(text: str) -> str:
    return re.sub(r'/\*.*?\*/', '', text, flags=re.S)


def split_top(text: str, sep: str) -> list[str]:
    """Split on `sep` outside parentheses and quotes."""
    out, depth, quote, cur = [], 0, None, []
    for ch in text:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in '\'"':
            quote = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif ch == sep and depth == 0:
            out.append(''.join(cur))
            cur = []
            continue
        cur.append(ch)
    out.append(''.join(cur))
    return out


def parse_rules(text: str) -> list[tuple[str, list[tuple[str, str]]]]:
    """Flatten a stylesheet into (selector, [(custom-property, value)]) rules.

    At-rules with nested rules (@supports, @media) are flattened; @font-face and
    other declaration-only at-rules contribute nothing. Only custom properties
    are kept.
    """
    text = strip_comments(text)
    rules: list[tuple[str, list[tuple[str, str]]]] = []

    def block(pos: int) -> tuple[str, int]:
        depth = 1
        i = pos
        while i < len(text) and depth:
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
            i += 1
        return text[pos:i - 1], i

    def walk(src_start: int, src_end: int, body: str) -> None:
        i = 0
        while i < len(body):
            brace = body.find('{', i)
            if brace < 0:
                break
            prelude = body[i:brace].strip()
            depth, j = 1, brace + 1
            while j < len(body) and depth:
                if body[j] == '{':
                    depth += 1
                elif body[j] == '}':
                    depth -= 1
                j += 1
            inner = body[brace + 1:j - 1]
            i = j
            if prelude.startswith('@'):
                if prelude.startswith(('@supports', '@media', '@layer')):
                    walk(0, 0, inner)
                continue
            decls = []
            for decl in split_top(inner, ';'):
                if ':' not in decl:
                    continue
                name, value = decl.split(':', 1)
                name, value = name.strip(), re.sub(r'\s+', ' ', value.strip())
                if name.startswith('--'):
                    decls.append((name, value))
            if decls:
                rules.append((re.sub(r'\s+', ' ', prelude), decls))

    walk(0, len(text), text)
    return rules


# -------------------------------------------------------------- var() resolve

def find_var(text: str, start: int = 0):
    """Find the first var(...) at or after start: (begin, end, name, fallback)."""
    i = text.find('var(', start)
    if i < 0:
        return None
    depth, j = 1, i + 4
    while j < len(text) and depth:
        if text[j] == '(':
            depth += 1
        elif text[j] == ')':
            depth -= 1
        j += 1
    inner = text[i + 4:j - 1]
    parts = split_top(inner, ',')
    name = parts[0].strip()
    fallback = ','.join(parts[1:]).strip() if len(parts) > 1 else None
    return i, j, name, fallback


class Unresolvable(Exception):
    pass


def substitute(value: str, env: dict[str, str], stack: tuple[str, ...] = ()) -> str:
    """Replace every var() by its value; runtime inputs use their fallback."""
    while True:
        hit = find_var(value)
        if hit is None:
            return value.strip()
        begin, end, name, fallback = hit
        if name in stack:
            raise Unresolvable(f'cycle through {name}')
        if name in env and name not in RUNTIME:
            repl = substitute(env[name], env, stack + (name,))
        elif fallback is not None:
            repl = substitute(fallback, env, stack)
        else:
            raise Unresolvable(f'var({name}) is not defined')
        value = value[:begin] + repl + value[end:]


# ---------------------------------------------------------------------- color

NAMED = {'transparent': (0.0, 0.0, 0.0, 0.0), 'white': (255.0, 255.0, 255.0, 1.0),
         'black': (0.0, 0.0, 0.0, 1.0)}


def num(text: str) -> float:
    return float(text)


def alpha_of(text: str) -> float:
    text = text.strip()
    return num(text[:-1]) / 100 if text.endswith('%') else num(text)


def parse_color(text: str) -> tuple[float, float, float, float]:
    t = text.strip().lower()
    if t in NAMED:
        return NAMED[t]
    if t.startswith('#'):
        d = t[1:]
        if len(d) in (3, 4):
            d = ''.join(c * 2 for c in d)
        if len(d) == 6:
            d += 'ff'
        if len(d) != 8 or not re.fullmatch(r'[0-9a-f]{8}', d):
            raise Unresolvable(f'bad hex color {text!r}')
        return (int(d[0:2], 16), int(d[2:4], 16), int(d[4:6], 16), int(d[6:8], 16) / 255)
    m = re.fullmatch(r'(rgba?)\((.*)\)', t)
    if m:
        body = m.group(2)
        if '/' in body:
            left, a = body.split('/', 1)
            alpha = alpha_of(a)
            chans = [c for c in re.split(r'[\s,]+', left.strip()) if c]
        else:
            chans = [c for c in re.split(r'[\s,]+', body.strip()) if c]
            alpha = alpha_of(chans.pop()) if len(chans) == 4 else 1.0
        if len(chans) != 3:
            raise Unresolvable(f'bad rgb() {text!r}')
        return (num(chans[0]), num(chans[1]), num(chans[2]), alpha)
    m = re.fullmatch(r'color-mix\((.*)\)', t)
    if m:
        args = [a.strip() for a in split_top(m.group(1), ',')]
        if len(args) != 3 or args[0] != 'in srgb':
            raise Unresolvable(f'unsupported color-mix {text!r}')

        def operand(arg: str):
            mm = re.fullmatch(r'(.*?)(?:\s+([\d.]+)%)?', arg.strip())
            return parse_color(mm.group(1)), (num(mm.group(2)) / 100 if mm.group(2) else None)
        (c1, p1), (c2, p2) = operand(args[1]), operand(args[2])
        if p1 is None and p2 is None:
            p1 = p2 = 0.5
        elif p1 is None:
            p1 = 1 - p2
        elif p2 is None:
            p2 = 1 - p1
        total = p1 + p2
        w1, w2 = p1 / total, p2 / total
        alpha = c1[3] * w1 + c2[3] * w2
        if alpha == 0:
            return (0.0, 0.0, 0.0, 0.0)
        chans = [(c1[i] * c1[3] * w1 + c2[i] * c2[3] * w2) / alpha for i in range(3)]
        return (chans[0], chans[1], chans[2], alpha * min(total, 1))
    raise Unresolvable(f'not a color: {text!r}')


def fmt_pct(a: float) -> str:
    s = f'{round(a * 100, 3):.3f}'.rstrip('0').rstrip('.')
    return s + '%'


def canon_color(c: tuple[float, float, float, float]) -> str:
    r, g, b = (max(0, min(255, int(round(v)))) for v in c[:3])
    a = round(c[3], 5)
    if a >= 1:
        return f'#{r:02x}{g:02x}{b:02x}'
    return f'rgb({r} {g} {b} / {fmt_pct(a)})'


COLOR_RE = re.compile(r'^(#[0-9a-fA-F]{3,8}|rgba?\(.*\)|color-mix\(.*\)|transparent|white|black)$')


def is_color(text: str) -> bool:
    return bool(COLOR_RE.match(text.strip()))


# ------------------------------------------------------------- shadow/gradient

def fnum(v: float) -> str:
    s = f'{v:.4f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def split_color_tail(layer: str) -> tuple[str, str]:
    m = re.search(r'(#[0-9a-fA-F]{3,8}\b|rgba?\(|color-mix\(|\btransparent\b|\bwhite\b|\bblack\b)', layer)
    if not m:
        raise Unresolvable(f'no color in {layer!r}')
    return layer[:m.start()].strip(), layer[m.start():].strip()


def canon_shadow(value: str) -> str:
    if value.strip() == 'none':
        return 'none'
    out = []
    for layer in split_top(value, ','):
        layer = layer.strip()
        inset = layer.startswith('inset ')
        if inset:
            layer = layer[6:].strip()
        lengths, color = split_color_tail(layer)
        nums = [float(x) for x in re.findall(r'-?\d*\.?\d+', lengths)]
        if len(nums) < 2:
            raise Unresolvable(f'shadow needs offsets: {layer!r}')
        nums += [0.0] * (4 - len(nums))
        out.append(('inset ' if inset else '') + ' '.join(f'{fnum(n)}px' for n in nums[:4])
                   + ' ' + canon_color(parse_color(color)))
    return ', '.join(out)


def canon_stop(stop: str) -> str:
    stop = stop.strip()
    m = re.fullmatch(r'(.*?)(?:\s+([\d.]+%))?', stop)
    color, pos = m.group(1), m.group(2)
    return canon_color(parse_color(color)) + (f' {pos}' if pos else '')


def canon_gradient(value: str) -> str:
    m = re.fullmatch(r'linear-gradient\((.*)\)', value.strip())
    if m:
        args = [a.strip() for a in split_top(m.group(1), ',')]
        head = ''
        if re.fullmatch(r'-?[\d.]+deg', args[0]):
            head, args = args[0] + ', ', args[1:]
        return 'linear-gradient(' + head + ', '.join(canon_stop(a) for a in args) + ')'
    return ', '.join(canon_stop(a) for a in split_top(value, ','))


# ---------------------------------------------------------------- typography

DELTA_SCALE = {
    '--dsh-content-font-delta': 'content',
    '--dsh-content-font-delta-secondary': 'secondary',
    '--dsh-code-font-delta': 'code',
}
SIZE_SCALE = {
    '--dsh-content-font-size': 'content',
    '--dsh-content-font-size-secondary': 'secondary',
    '--dsh-code-font-size': 'code',
}


def parse_length_expr(text: str):
    """`12px`, `calc(21px + var(--dsh-content-font-delta))`, `var(--dsh-x-font-size, 14px)`.

    Returns a JSON value: a number (px, fixed) or {"base": n, "scale": s}.
    The size is `base + delta(scale)` where delta(content) = text size - 14,
    delta(secondary) = secondary size - 13, delta(code) = code size - 11.
    """
    t = text.strip()
    m = re.fullmatch(r'(-?[\d.]+)px', t)
    if m:
        return jnum(num(m.group(1)))
    m = re.fullmatch(r'calc\(\s*([\d.]+)px\s*\+\s*var\((--[a-z-]+)(?:,\s*0px)?\)\s*\)', t)
    if m and m.group(2) in DELTA_SCALE:
        return {'base': jnum(num(m.group(1))), 'scale': DELTA_SCALE[m.group(2)]}
    m = re.fullmatch(r'var\((--[a-z-]+),\s*([\d.]+)px\)', t)
    if m and m.group(1) in SIZE_SCALE:
        return {'base': jnum(num(m.group(2))), 'scale': SIZE_SCALE[m.group(1)]}
    raise Unresolvable(f'unsupported length expression {text!r}')


def parse_family_ref(text: str) -> str:
    m = re.fullmatch(r'var\((--[a-z-]+)\)', text.strip())
    if m and m.group(1) == '--dsw-font-family':
        return 'text'
    if m and m.group(1) == '--ds-font-family-code':
        return 'code'
    raise Unresolvable(f'unsupported font family reference {text!r}')


def parse_font_shorthand(text: str) -> dict:
    # `size/line family` or `size / line family`; the family is the last
    # top-level word, so split it off first.
    words = [w for w in split_top(text.strip(), ' ') if w]
    family = words.pop()
    rest = ' '.join(words)
    head, _, line = rest.partition('/') if '/' in rest else (rest, '', '')
    head_words = [w for w in split_top(head.strip(), ' ') if w]
    size = head_words.pop()
    style, weight = 'normal', 400
    for w in head_words:
        if w == 'italic':
            style = 'italic'
        elif w.isdigit():
            weight = int(w)
        else:
            raise Unresolvable(f'unknown shorthand word {w!r}')
    out = {'family': parse_family_ref(family), 'size': parse_length_expr(size),
           'style': style, 'weight': weight}
    if line.strip():
        out['line'] = parse_length_expr(line)
    return out


def build_typography(base: str, raw: dict[str, str]) -> dict:
    fam = parse_family_ref(raw[f'{base}-font-family'])
    weight = int(raw[f'{base}-font-weight'])
    style = raw[f'{base}-font-style'].strip()
    if style not in ('normal', 'italic'):
        raise Unresolvable(f'font-style {style!r}')
    out = {
        'family': fam,
        'line': parse_length_expr(raw[f'{base}-line-height']),
        'size': parse_length_expr(raw[f'{base}-font-size']),
        'style': style,
        'weight': weight,
    }
    short = parse_font_shorthand(raw[base])
    if short != out:
        raise Unresolvable(f'shorthand disagrees with longhands: {short} vs {out}')
    return out


def jnum(v: float):
    return int(v) if float(v).is_integer() else round(v, 4)


# ---------------------------------------------------------------------- fonts

def parse_family_list(text: str) -> list[str]:
    names = []
    for part in split_top(text, ','):
        name = part.strip().strip('\'"').strip()
        if name:
            names.append(name)
    return names


def dedupe(names: list[str]) -> list[str]:
    seen, out = set(), []
    for n in names:
        if n not in seen:
            seen.add(n)
            out.append(n)
    return out


# ------------------------------------------------------------------ the build

def read_sheets(src: Path, rep: Report):
    layers = {'root': {}, 'body': {}, 'dark': {}}
    scoped_seen: dict[str, set[str]] = {}
    for sheet in SHEETS:
        path = src / THEME_REL / sheet
        for selector, decls in parse_rules(path.read_text(encoding='utf-8')):
            parts = [p.strip() for p in selector.split(',')]
            modeled = False
            for part in parts:
                layer = {':root': 'root', 'body': 'body', 'body[data-ds-dark-theme]': 'dark'}.get(part)
                if layer:
                    modeled = True
                    for name, value in decls:
                        layers[layer][name] = value
                        rep.declared += 1
            if not modeled:
                names = sorted(n for n, _ in decls)
                rep.skipped_scopes.append(f'{sheet}: `{selector}` sets {", ".join(names)}')
                scoped_seen.setdefault(selector, set()).update(names)
    return layers


def classify_and_resolve(name: str, env: dict[str, str], rep: Report):
    """Resolve one non-typography, non-font token to (kind, canonical value)."""
    value = substitute(env[name], env)
    if is_color(value):
        return 'color', canon_color(parse_color(value))
    if name.endswith('-stops') or value.startswith('linear-gradient('):
        return 'gradient', canon_gradient(value)
    if 'shadow' in name or 'elevation' in name:
        return 'shadow', canon_shadow(value)
    m = re.fullmatch(r'(-?[\d.]+)px', value)
    if m:
        return 'number', jnum(num(m.group(1)))
    m = re.fullmatch(r'([\d.]+)s', value)
    if m:
        return 'number', jnum(round(num(m.group(1)) * 1000, 3))
    m = re.fullmatch(r'([\d.]+)ms', value)
    if m:
        return 'number', jnum(num(m.group(1)))
    if re.fullmatch(r'-?[\d.]+', value):
        return 'number', jnum(num(value))
    return 'string', value


def build(src: Path):
    rep = Report()
    layers = read_sheets(src, rep)
    light_raw = {**layers['root'], **layers['body']}
    dark_raw = {**light_raw, **layers['dark']}
    envs = {'light': light_raw, 'dark': dark_raw}

    # Fonts (same in both modes; checked).
    fonts = {}
    for mode, env in envs.items():
        text = dedupe(parse_family_list(substitute(env['--dsw-font-family'], env)))
        code = dedupe(parse_family_list(substitute(env['--ds-font-family-code'], env)))
        brand = dedupe(parse_family_list(substitute(env['--dsw-font-family-brand'], env)))
        if text != parse_family_list(env['--dsh-font-family-text-default']):
            rep.unresolved.append('--dsw-font-family: differs from --dsh-font-family-text-default')
        got = {'text': text, 'code': code, 'brand': brand}
        if fonts and fonts != got:
            rep.unresolved.append('font stacks differ between light and dark')
        fonts = got
    terminal_src = (src / TERMINAL_REL).read_text(encoding='utf-8')
    m = re.search(r"TERMINAL_FONT_STACK\s*=\s*'([^']*)'", terminal_src)
    if m:
        fonts['terminal'] = dedupe(parse_family_list(m.group(1)))
    else:
        rep.unresolved.append(f'terminal font stack: TERMINAL_FONT_STACK not found in {TERMINAL_REL}')

    names = sorted(set(light_raw) | set(dark_raw))
    rep.distinct = len(names)
    values: dict[str, dict[str, object]] = {}  # name -> {mode: (kind, value)}
    kinds: dict[str, str] = {}
    typo_bases = set()
    for name in names:
        m = LONGHAND.match(name)
        if m and m.group(1) in light_raw:
            typo_bases.add(m.group(1))

    for name in names:
        if name in RUNTIME:
            rep.excluded.append(name)
            continue
        if name in FONT_VARS:
            rep.excluded.append(name + '  (-> fonts)')
            continue
        m = LONGHAND.match(name)
        if m and m.group(1) in typo_bases:
            rep.folded += 1
            continue  # folded into the shorthand's typography entry
        for mode, env in envs.items():
            if name not in env:
                rep.unresolved.append(f'{name}: not declared in {mode}')
                continue
            try:
                if name in typo_bases:
                    kind, val = 'typography', build_typography(name, env)
                else:
                    kind, val = classify_and_resolve(name, env, rep)
            except (Unresolvable, KeyError, ValueError) as err:
                rep.unresolved.append(f'{name} [{mode}]: {err}')
                continue
            if kinds.setdefault(name, kind) != kind:
                rep.unresolved.append(f'{name}: kind differs between modes')
                continue
            values.setdefault(name, {})[mode] = val

    # Only tokens present and resolved in both modes enter the contract.
    for name in sorted(values):
        if set(values[name]) != {'light', 'dark'}:
            if not any(u.startswith(name) for u in rep.unresolved):
                rep.unresolved.append(f'{name}: not resolved in both modes')
            del values[name]
            del kinds[name]

    common = {t: {} for t in TABLE_FOR_KIND.values()}
    modes = {'light': {t: {} for t in common}, 'dark': {t: {} for t in common}}
    for name in sorted(values):
        table = TABLE_FOR_KIND[kinds[name]]
        light, dark = values[name]['light'], values[name]['dark']
        if light == dark:
            common[table][name] = light
        else:
            modes['light'][table][name] = light
            modes['dark'][table][name] = dark

    def prune(tables):
        return {k: v for k, v in tables.items() if v}

    pack = {
        'format': PACK_FORMAT,
        'id': 'official',
        'name': 'DSH Official',
        'version': '1',
        'fonts': fonts,
        'common': prune(common),
        'modes': {'light': prune(modes['light']), 'dark': prune(modes['dark'])},
    }
    pack['source'] = source_metadata(src)
    return pack, kinds, rep


def source_metadata(src: Path) -> dict:
    try:
        commit = subprocess.run(['git', '-C', str(src), 'rev-parse', 'HEAD'], check=True,
                                capture_output=True, text=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        commit = 'unknown'
    files = [f'{THEME_REL}/{s}' for s in SHEETS] + [TERMINAL_REL]
    digests = {}
    for rel in files:
        digests[rel] = hashlib.sha256((src / rel).read_bytes()).hexdigest()
    return {
        'upstream': 'DSH (DeepSeek Harness), MIT',
        'commit': commit,
        'files': files,
        'sha256': digests,
        'generator': 'tool/theme-adapters/build_official_pack.py',
    }


# ------------------------------------------------------------------- emitters

GENERATED = 'GENERATED by tool/theme-adapters/build_official_pack.py from dsh {commit}. Do not edit; run the script.'


def dart_str(s: str) -> str:
    s = s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    return "'" + s + "'"


def dart_literal(v, indent: int) -> str:
    pad = '  ' * indent
    inner = '  ' * (indent + 1)
    if isinstance(v, dict):
        if not v:
            return '{}'
        lines = [f'{inner}{dart_str(k)}: {dart_literal(v[k], indent + 1)},' for k in sorted(v)]
        return '{\n' + '\n'.join(lines) + f'\n{pad}}}'
    if isinstance(v, list):
        if not v:
            return '[]'
        lines = [f'{inner}{dart_literal(x, indent + 1)},' for x in v]
        return '[\n' + '\n'.join(lines) + f'\n{pad}]'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    return dart_str(v)


def emit_json(pack: dict) -> str:
    return json.dumps(pack, indent=2, sort_keys=True, ensure_ascii=False) + '\n'


def emit_pack_dart(pack: dict) -> str:
    header = GENERATED.format(commit=pack['source']['commit'][:12])
    return (
        f'// {header}\n'
        '// dart format off\n\n'
        '/// The official dsh theme pack as decoded JSON (`dsh-theme/1`).\n'
        '///\n'
        '/// Identical in content to `assets/themes/official.theme.json`; kept as a\n'
        '/// const so the engine and its tests need no asset loading. Parse it with\n'
        '/// `ThemePack.fromJson`, the same path a user pack takes.\n'
        'const Map<String, Object?> officialPackData = '
        + dart_literal(pack, 0) + ';\n'
    )


def emit_names_dart(pack: dict, kinds: dict[str, str]) -> str:
    header = GENERATED.format(commit=pack['source']['commit'][:12])
    kind_lines = ''.join(f'  {dart_str(n)}: {dart_str(kinds[n])},\n' for n in sorted(kinds))
    role_lines = ''.join(f'  {dart_str(r)},\n' for r in sorted(pack['fonts']))
    return (
        f'// {header}\n'
        '// dart format off\n\n'
        '/// Kind of every contract token, keyed by its exact dsh CSS custom property name\n'
        '/// (leading `--` kept). Kinds: color, number, shadow, gradient, typography, string.\n'
        'const Map<String, String> dshContractKinds = {\n'
        + kind_lines +
        '};\n\n'
        '/// Every contract token name, sorted.\n'
        'const List<String> dshContractNames = [\n'
        + ''.join(f'  {dart_str(n)},\n' for n in sorted(kinds)) +
        '];\n\n'
        '/// Font stack roles a pack carries.\n'
        'const List<String> dshPackFontRoles = [\n'
        + role_lines +
        '];\n'
    )


def outputs(src: Path):
    pack, kinds, rep = build(src)
    files = {
        OUT_JSON: emit_json(pack),
        OUT_PACK_DART: emit_pack_dart(pack),
        OUT_NAMES_DART: emit_names_dart(pack, kinds),
    }
    return files, pack, kinds, rep


def print_report(pack, kinds, rep: Report) -> None:
    per_kind = {k: sum(1 for v in kinds.values() if v == k) for k in KINDS}
    print(f'source commit : {pack["source"]["commit"]}')
    print(f'css custom property declarations read : {rep.declared}')
    print(f'distinct custom properties          : {rep.distinct} (folded typography longhands {rep.folded}, excluded {len(rep.excluded)})')
    print(f'contract names (resolved tokens)      : {len(kinds)}  {per_kind}')
    print(f'font stacks   : {", ".join(f"{r}={len(s)}" for r, s in sorted(pack["fonts"].items()))}')
    print(f'excluded (runtime inputs / font composites): {len(rep.excluded)}')
    for e in rep.excluded:
        print(f'  excluded {e}')
    print(f'scoped rules not modelled: {len(rep.skipped_scopes)}')
    for s in rep.skipped_scopes:
        print(f'  skipped {s}')
    print(f'UNRESOLVED: {len(rep.unresolved)}')
    for u in rep.unresolved:
        print(f'  unresolved {u}')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--src', default=os.environ.get('DSH_SRC', DEFAULT_SRC),
                    help='dsh checkout root (default: $DSH_SRC or %s)' % DEFAULT_SRC)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument('--write', action='store_true', help='write generated files (default)')
    mode.add_argument('--check', action='store_true', help='exit 1 if committed files are stale')
    ap.add_argument('--quiet', action='store_true', help='skip the token report')
    args = ap.parse_args()
    src = Path(args.src)
    if not (src / THEME_REL).is_dir():
        print(f'error: {src / THEME_REL} not found; set --src or DSH_SRC', file=sys.stderr)
        return 2
    files, pack, kinds, rep = outputs(src)
    if not args.quiet:
        print_report(pack, kinds, rep)
    if args.check:
        stale = 0
        for path, text in files.items():
            rel = path.relative_to(REPO)
            old = path.read_text(encoding='utf-8') if path.exists() else None
            if old == text:
                continue
            stale += 1
            diff = list(difflib.unified_diff((old or '').splitlines(), text.splitlines(),
                                             f'committed/{rel}', f'generated/{rel}', lineterm='', n=0))
            added = sum(1 for d in diff if d.startswith('+') and not d.startswith('+++'))
            removed = sum(1 for d in diff if d.startswith('-') and not d.startswith('---'))
            print(f'STALE {rel}: +{added} -{removed} lines' + (' (missing)' if old is None else ''))
            for line in diff[:20]:
                print('   ' + line)
        if stale:
            print(f'{stale} file(s) stale; run: python3 tool/theme-adapters/build_official_pack.py --write')
            return 1
        print('official theme pack is up to date')
        return 0
    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        print(f'wrote {path.relative_to(REPO)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
