#!/usr/bin/env node
// Generates packages/dsh_highlight/test/fixtures/translator_cases.json: for each
// (Oniguruma pattern, subject, start) the match shiki's JavaScript regex engine
// (oniguruma-to-es, as dsh configures it) produces, as capture index ranges, or
// "unsupported" when it rejects the pattern. The Dart translator test replays
// the same cases.
//
//   node tool/highlight/gen-translator-cases.mjs --shiki <node_modules dir>
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name)
  return i >= 0 ? process.argv[i + 1] : fallback
}
const here = path.dirname(new URL(import.meta.url).pathname)
const nm = arg('shiki')
if (!nm) {
  console.error('usage: gen-translator-cases.mjs --shiki <node_modules dir>')
  process.exit(2)
}
const out = arg('out', path.resolve(here, '../../packages/dsh_highlight/test/fixtures/translator_cases.json'))
const { defaultJavaScriptRegexConstructor } = await import(
  pathToFileURL(path.join(nm, '@shikijs/engine-javascript/dist/index.mjs')).href)

// [pattern, subject, start?]
const cases = [
  [String.raw`\w+`, 'héllo_wörld 42'],
  [String.raw`\d+`, 'ab 123 x'],
  [String.raw`\s+`, 'a \t b'],
  [String.raw`\h+`, 'xyz DEADbeef09 q'],
  [String.raw`\bfoo\b`, 'a foo b'],
  [String.raw`\Bfoo`, 'afoo'],
  [String.raw`^abc`, 'abcabc'],
  [String.raw`abc$`, 'abcabc\n'],
  [String.raw`abc\Z`, 'xabc\n'],
  [String.raw`abc\z`, 'xabc'],
  [String.raw`^\s*#`, '   # x\n'],
  [String.raw`a.c`, 'a\nc abc'],
  [String.raw`(?m)a.c`, 'a\nc'],
  [String.raw`(?i)abc`, 'xABc'],
  [String.raw`(?i)a(?-i)b`, 'AB aB'],
  [String.raw`a(?i)b|c`, 'aB C'],
  [String.raw`(?i:a)b`, 'Ab AB'],
  [String.raw`(?x) a b # comment`, 'ab'],
  [String.raw`(?x)
    (foo) # first
    \s+
    (bar)`, 'foo   bar'],
  [String.raw`(a)(b)?(c)`, 'ac'],
  [String.raw`(?<n>a)\k<n>`, 'aa'],
  [String.raw`(?<n>a)\k<n>`, 'ab'],
  [String.raw`(a)\1`, 'aa'],
  [String.raw`(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)\10`, 'abcdefghijj'],
  [String.raw`(?>a+)b`, 'aaab'],
  [String.raw`(?>a+)a`, 'aaa'],
  [String.raw`a++a`, 'aaa'],
  [String.raw`a*+b`, 'aab'],
  [String.raw`a?+a`, 'a'],
  [String.raw`(?:ab)++c`, 'ababc'],
  [String.raw`a{2,3}`, 'aaaa'],
  [String.raw`a{,2}`, 'aaa'],
  [String.raw`a{2}`, 'aaa'],
  [String.raw`a{2,}?`, 'aaaa'],
  [String.raw`a{x}`, 'a{x}'],
  [String.raw`a+?`, 'aaa'],
  [String.raw`[a-c]+`, 'xabcd'],
  [String.raw`[^a-c]+`, 'abxyzc'],
  [String.raw`[\d-]+`, 'a1-2b'],
  [String.raw`[\w.-]+`, 'a.b-c d'],
  [String.raw`[[:alpha:]]+`, 'ab1'],
  [String.raw`[[:^alpha:]]+`, 'ab12c'],
  [String.raw`[[:alnum:]_]+`, '12_ab-'],
  [String.raw`[[:upper:]][[:lower:]]+`, 'xHello'],
  [String.raw`[[:space:]]+`, 'a \t\nb'],
  [String.raw`[[:punct:]]+`, 'a.,;b'],
  [String.raw`[[:xdigit:]]+`, 'zz1aFg'],
  [String.raw`[[:word:]]+`, '-ab_1-'],
  [String.raw`[[:graph:]]+`, ' ab '],
  [String.raw`[[:print:]]+`, "\u0001ab c\u0002"],
  [String.raw`[a-z&&[^aeiou]]+`, 'aebcdi'],
  [String.raw`[a[bc]d]+`, 'xabcdx'],
  [String.raw`[^a[bc]]+`, 'abcxyzabc'],
  [String.raw`[a-c[^b]]+`, 'bbaxb'],
  [String.raw`[\]]+`, 'a]]'],
  [String.raw`[]a]+`, 'x]a]'],
  [String.raw`[a\-z]+`, 'a-z'],
  [String.raw`[\x41-\x43]+`, 'ABCD'],
  [String.raw`[A-C]+`, 'ABCD'],
  [String.raw`\x{41}\x41A`, 'AAA'],
  [String.raw`\t\n\r\e\a`, '\t\n\r\u001b\u0007'],
  [String.raw`\p{L}+`, 'ab12'],
  [String.raw`\p{Lu}\p{Ll}+`, 'xHello'],
  [String.raw`\P{L}+`, 'ab12c'],
  [String.raw`\p{^L}+`, 'ab12c'],
  [String.raw`\p{Han}+`, 'ab中文c'],
  [String.raw`\p{Alpha}+`, '12ab3'],
  [String.raw`\p{Alnum}+`, '--a1--'],
  [String.raw`\p{Upper}+`, 'abCDe'],
  [String.raw`\p{Digit}+`, 'a12'],
  [String.raw`\p{Greek}+`, 'abαβγ'],
  [String.raw`\R`, 'a\r\nb'],
  [String.raw`\N+`, 'ab\ncd'],
  [String.raw`\O+`, 'ab\ncd'],
  [String.raw`(?<=a)b`, 'ab cb'],
  [String.raw`(?<!a)b`, 'ab cb'],
  [String.raw`(?<=a|bc)d`, 'bcd'],
  [String.raw`a(?=b)`, 'ac ab'],
  [String.raw`a(?!b)`, 'ab ac'],
  [String.raw`(?:a|b)+c`, 'abac'],
  [String.raw`(a|b)*`, 'abab'],
  [String.raw`(?#comment)a`, 'a'],
  [String.raw`a\Kb`, 'ab'],
  [String.raw`(?~abc)`, 'xxabcx'],
  [String.raw`(?<x>a|b\g<x>c)`, 'bbacc'],
  [String.raw`\g<0>?a`, 'aa'],
  [String.raw`\G\s*x`, '  x', 0],
  [String.raw`\G\s*x`, 'a  x', 1],
  [String.raw`\Gx|y`, 'ax y', 1],
  [String.raw`(\G|,)x`, ',x x', 0],
  [String.raw`a\Gb`, 'ab', 0],
  [String.raw`(?:a)\Gb`, 'ab', 0],
  [String.raw`￿|\\uFFFF`, 'x\\￿y'],
  [String.raw`\-\_\#\"\/\ `, '-_#"/ '],
  [String.raw`\(\)\[\]\{\}\.\*\+\?\^\$\|`, '()[]{}.*+?^$|'],
  [String.raw`foo|bar|baz`, 'xbarz'],
  [String.raw`(foo|bar)|baz`, 'baz'],
  [String.raw`(?i)[a-z]+\d`, 'ABc1'],
  [String.raw`(?i)straße`, 'STRASSE straße'],
  [String.raw`(?i)\b(count|group)\b\s*\(`, 'x COUNT(*)'],
  [String.raw`(?i)\b(avg|count|group)\b\s*\(`, 'x GROUP ('],
  [String.raw`\b(?i)(count|group)\b`, 'x Group'],
  [String.raw`(?i:abc)def|(?i)xyz`, 'ABCdef XYZ'],
  [String.raw`(?i)[k-n]+(?-i)[a-c]+`, 'LMnABc abC'],
  [String.raw`(?i)[^a-c]+`, 'ABCdef'],
  [String.raw`(?i)é+(?-i)x`, 'ÉéX Éex'],
  [String.raw`\p{word}+`, 'héllo_wörld!'],
  [String.raw`[_[:alpha:]]\p{word}*\s*\(`, '  my_func9 ('],
  [String.raw`\p{Alpha}\p{M}+`, 'e\u0301x'],
  [String.raw`\$\{`, 'a${b'],
  [String.raw`}{`, '}{'],
  [String.raw`a{`, 'a{'],
  [String.raw`[{}]+`, 'a{}b'],
  [String.raw`\cA`, '\u0001'],
  [String.raw`\0`, '\u0000'],
  [String.raw`\012`, '\n'],
  [String.raw`(?<year>\d{4})-(?<month>\d{2})`, 'on 2024-05-01'],
  [String.raw`(?:(a)|b)+`, 'ab'],
  [String.raw`(a)?b`, 'b'],
  [String.raw`[^\n]*`, 'ab\ncd'],
  [String.raw`.*`, 'ab\r\ncd'],
  [String.raw`\s*$`, 'ab  \n'],
  [String.raw`^$`, '\n'],
  [String.raw`^`, 'ab\n'],
  [String.raw`$`, 'ab\n'],
  [String.raw`\A\s*x`, '  x'],
  [String.raw`[\w&&[^\d]]+`, '12ab3'],
  [String.raw`[\W]+`, 'ab--c'],
  [String.raw`[^\W\d]+`, '12ab3'],
  [String.raw`[\s\S]+`, 'a\nb'],
  [String.raw`\y`, 'a'],
  [String.raw`(?(1)a|b)`, 'a'],
  [String.raw`[\d-z]`, '1'],
  [String.raw`a**`, 'aaa'],
  [String.raw`(?<a>x)(?<a>y)\k<a>`, 'xyy'],
  [String.raw`*a`, 'a'],
  [String.raw`(unclosed`, 'a'],
  [String.raw`)`, 'a'],
  [String.raw`[a`, 'a'],
  [String.raw`\k<missing>`, 'a'],
]

const rows = []
for (const [pattern, subject, start = 0] of cases) {
  const row = { pattern, subject, start }
  try {
    const re = defaultJavaScriptRegexConstructor(pattern, { lazyCompileLength: Number.POSITIVE_INFINITY })
    re.lastIndex = start
    const m = re.exec(subject)
    row.expect = m ? m.indices.map(i => i ? [i[0], i[1]] : null) : null
    // exec on a sticky regex fails at positions other than lastIndex, as in
    // the scanner; for others the first match at or after start is reported.
  } catch (e) {
    row.expect = 'unsupported'
  }
  rows.push(row)
}
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, JSON.stringify(rows, null, 1) + '\n')
console.log(`wrote ${rows.length} cases -> ${out}`)
