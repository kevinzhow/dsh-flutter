"""Strict CSS rule reader; every conditional scope remains attached to its rules."""
import re

def split_outside(text, delimiter):
    parts, start, quote, escaped, parens, brackets = [], 0, None, False, 0, 0
    for i, char in enumerate(text):
        if quote is not None:
            if escaped: escaped = False
            elif char == '\\': escaped = True
            elif char == quote: quote = None
            continue
        if char in ['"', "'"]: quote = char
        elif char == '(': parens += 1
        elif char == ')': parens -= 1
        elif char == '[': brackets += 1
        elif char == ']': brackets -= 1
        elif char == delimiter and parens == brackets == 0:
            parts.append(text[start:i]); start = i + 1
        if parens < 0 or brackets < 0: raise ValueError('unbalanced CSS expression')
    if quote is not None or parens or brackets: raise ValueError('unclosed CSS expression')
    return [*parts, text[start:]]


def css_rules(text, context=(), *, allow_keyframes=False, allow_supports=False):
    text = re.sub(r'''/\*.*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''',
                  lambda m: '' if m[0].startswith('/*') else m[0], text, flags=re.S | re.X)
    rules = []
    while text.strip():
        start = text.find('{')
        if start < 0: raise ValueError('CSS trailing syntax is not a rule')
        selector = ', '.join(part.strip() for part in split_outside(text[:start].strip(), ','))
        depth, end, quote, escaped = 1, start + 1, None, False
        while end < len(text) and depth:
            char = text[end]
            if quote is not None:
                if escaped: escaped = False
                elif char == '\\': escaped = True
                elif char == quote: quote = None
            elif char in ['"', "'"]: quote = char
            else: depth += (char == '{') - (char == '}')
            end += 1
        if depth: raise ValueError('unclosed CSS rule')
        body, text = text[start + 1:end - 1], text[end:]
        if selector.startswith('@'):
            if re.match(r'^@media(?:\s|\()', selector):
                selector = '@media ' + re.sub(r':\s*', ': ', selector[len('@media'):].strip())
            elif allow_supports and re.match(r'^@supports(?:\s|\()', selector):
                selector = '@supports ' + selector[len('@supports'):].strip()
            elif not (allow_keyframes and selector.startswith('@keyframes ')):
                raise ValueError('unsupported CSS condition: ' + selector)
            rules.extend(css_rules(body, (*context, selector), allow_keyframes=allow_keyframes, allow_supports=allow_supports))
            continue
        if not selector or len(split_outside(body, '{')) != 1 or len(split_outside(body, '}')) != 1:
            raise ValueError('unsupported nested CSS: ' + selector)
        declarations = {}
        for declaration in split_outside(body, ';'):
            if not declaration.strip(): continue
            if ':' not in declaration: raise ValueError('invalid CSS declaration')
            key, value = map(str.strip, declaration.split(':', 1))
            if key in declarations: raise ValueError('duplicate declaration: ' + key)
            declarations[key] = value
        rules.append({'selector': selector, 'conditions': list(context), 'declarations': declarations})
    return rules

