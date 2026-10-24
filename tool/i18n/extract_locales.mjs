// Extract zh/en dictionaries from dsh client locale TypeScript files, without executing them.
// Usage: node extract_locales.mjs --dsh <src> --node-dir <dir> --config packages.json --out locales.ir.json
// Values are folded from string literals, no-substitution templates, `+` concatenation and
// same-file const identifiers; anything else fails loudly.
import { createRequire } from 'node:module'
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import path from 'node:path'

const args = new Map()
for (let i = 2; i < process.argv.length; i += 2) args.set(process.argv[i], process.argv[i + 1])
const dsh = path.resolve(args.get('--dsh'))
const ts = createRequire(path.join(path.resolve(args.get('--node-dir')), 'package.json'))('typescript')
const config = JSON.parse(readFileSync(args.get('--config'), 'utf8'))

const parsed = new Map()
function source(rel) {
  if (!parsed.has(rel)) {
    const text = readFileSync(path.join(dsh, rel), 'utf8')
    parsed.set(rel, { text, sf: ts.createSourceFile(rel, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS) })
  }
  return parsed.get(rel).sf
}

function topLevelConst(sf, name) {
  for (const st of sf.statements) {
    if (!ts.isVariableStatement(st)) continue
    for (const d of st.declarationList.declarations) {
      if (ts.isIdentifier(d.name) && d.name.text === name && d.initializer) return d.initializer
    }
  }
  return undefined
}

/** `name` imported by a relative named import of `sf`: its initializer and owning file. */
function importedConst(sf, rel, name) {
  for (const st of sf.statements) {
    if (!ts.isImportDeclaration(st) || !ts.isStringLiteral(st.moduleSpecifier)) continue
    const spec = st.moduleSpecifier.text
    const named = st.importClause?.namedBindings
    if (!spec.startsWith('.') || !named || !ts.isNamedImports(named)) continue
    for (const el of named.elements) {
      if ((el.name.text !== name) || (el.propertyName && el.propertyName.text !== name && el.name.text !== name)) continue
      const exported = el.propertyName?.text ?? el.name.text
      const rel2 = path.posix.normalize(path.posix.join(path.posix.dirname(rel), spec))
      const sf2 = source(rel2)
      const init = topLevelConst(sf2, exported)
      if (init) { extraInputs.add(rel2); return { init, owner: { sf: sf2, rel: rel2 } } }
    }
  }
  return undefined
}

const extraInputs = new Set()

function unwrap(n) {
  while (ts.isAsExpression(n) || ts.isSatisfiesExpression(n) || ts.isParenthesizedExpression(n)) n = n.expression
  return n
}

function evalStr(n, sf, where) {
  n = unwrap(n)
  if (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) return n.text
  if (ts.isIdentifier(n)) {
    const init = topLevelConst(sf, n.text)
    if (!init) throw new Error(`${where}: identifier ${n.text} is not a same-file const`)
    return evalStr(init, sf, where)
  }
  if (ts.isBinaryExpression(n) && n.operatorToken.kind === ts.SyntaxKind.PlusToken) {
    return evalStr(n.left, sf, where) + evalStr(n.right, sf, where)
  }
  if (ts.isTemplateExpression(n)) {
    let s = n.head.text
    for (const span of n.templateSpans) s += evalStr(span.expression, sf, where) + span.literal.text
    return s
  }
  throw new Error(`${where}: non-static value (${ts.SyntaxKind[n.kind]})`)
}

function readObject(obj, sf, rel, label, out) {
  for (const p of obj.properties) {
    if (ts.isSpreadAssignment(p)) {
      let owner = { sf, rel }
      let target = ts.isIdentifier(p.expression) ? topLevelConst(sf, p.expression.text) : undefined
      if (!target && ts.isIdentifier(p.expression)) {
        // A dictionary spread from a sibling module (`import { zoomZh } from '../zoom/locales.ts'`).
        const imported = importedConst(sf, rel, p.expression.text)
        if (imported) { owner = imported.owner; target = imported.init }
      }
      const inner = target && unwrap(target)
      if (!inner || !ts.isObjectLiteralExpression(inner)) throw new Error(`${rel}: ${label} spreads something other than a same-file or imported object const`)
      readObject(inner, owner.sf, owner.rel, label, out)
      continue
    }
    if (!ts.isPropertyAssignment(p)) throw new Error(`${rel}: ${label} has an unsupported member`)
    const key = ts.isIdentifier(p.name) || ts.isStringLiteral(p.name) || ts.isNoSubstitutionTemplateLiteral(p.name)
      ? p.name.text : (() => { throw new Error(`${rel}: computed key in ${label}`) })()
    out[key] = evalStr(p.initializer, sf, `${rel}:${label}.${key}`)
  }
  return out
}

function readDict(rel, exportName) {
  const sf = source(rel)
  const init = topLevelConst(sf, exportName)
  if (!init) throw new Error(`${rel}: export ${exportName} not found`)
  const obj = unwrap(init)
  if (!ts.isObjectLiteralExpression(obj)) throw new Error(`${rel}: ${exportName} is not an object literal`)
  return readObject(obj, sf, rel, exportName, {})
}

/**
 * A dictionary registered inline: `const <name>: ... = [['zh', {...}], ['en', {...}]]` anywhere in the
 * file (ui-directory-picker-browse registers its dialog copy that way). Returns `{zh, en}`.
 */
function readInlinePairs(rel, name) {
  const sf = source(rel)
  let found
  const visit = (n) => {
    if (found) return
    if (ts.isVariableDeclaration(n) && ts.isIdentifier(n.name) && n.name.text === name && n.initializer) {
      found = unwrap(n.initializer)
      return
    }
    ts.forEachChild(n, visit)
  }
  visit(sf)
  if (!found || !ts.isArrayLiteralExpression(found)) throw new Error(`${rel}: inline dictionary array ${name} not found`)
  const out = {}
  for (const el of found.elements) {
    const pair = unwrap(el)
    if (!ts.isArrayLiteralExpression(pair) || pair.elements.length !== 2) throw new Error(`${rel}: ${name} member is not a [locale, dict] pair`)
    const locale = evalStr(pair.elements[0], sf, `${rel}:${name}`)
    const obj = unwrap(pair.elements[1])
    if (!ts.isObjectLiteralExpression(obj)) throw new Error(`${rel}: ${name}[${locale}] is not an object literal`)
    out[locale] = readObject(obj, sf, rel, `${name}[${locale}]`, {})
  }
  return out
}

function walk(dir, acc) {
  for (const e of readdirSync(dir)) {
    const p = path.join(dir, e)
    if (e === 'node_modules' || e === 'tests' || e === 'lib') continue
    if (statSync(p).isDirectory()) walk(p, acc)
    else if (/\.(ts|tsx)$/.test(e)) acc.push(p)
  }
  return acc
}

/** Namespaces declared by `interface LocaleNamespaceMap` members under a package src dir. */
function declaredNamespaces(pkg) {
  const dir = path.join(dsh, 'packages', pkg, 'src')
  const names = new Set()
  for (const f of walk(dir, [])) {
    const text = readFileSync(f, 'utf8')
    if (!text.includes('LocaleNamespaceMap')) continue
    const sf = ts.createSourceFile(f, text, ts.ScriptTarget.Latest, true)
    const visit = (n) => {
      if (ts.isInterfaceDeclaration(n) && n.name.text === 'LocaleNamespaceMap') {
        for (const m of n.members) {
          if (ts.isPropertySignature(m) && (ts.isIdentifier(m.name) || ts.isStringLiteral(m.name))) names.add(m.name.text)
        }
      }
      ts.forEachChild(n, visit)
    }
    visit(sf)
  }
  return names
}

const namespaces = []
const inputs = new Set()
const declaredCache = new Map()
for (const d of config.dictionaries) {
  const zhFile = d.zhFile ?? d.file
  const enFile = d.enFile ?? d.file
  inputs.add(zhFile)
  inputs.add(enFile)
  let zh, en
  if (d.inlinePairs) {
    const pairs = readInlinePairs(zhFile, d.inlinePairs)
    zh = pairs.zh ?? {}
    en = pairs.en ?? {}
  } else {
    zh = readDict(zhFile, d.zhExport ?? 'zh')
    en = readDict(enFile, d.enExport ?? 'en')
    if (!declaredCache.has(d.package)) declaredCache.set(d.package, declaredNamespaces(d.package))
    if (!declaredCache.get(d.package).has(d.namespace)) {
      throw new Error(`namespace ${d.namespace} is not declared in LocaleNamespaceMap of packages/${d.package}`)
    }
  }
  const keys = [...new Set([...Object.keys(en), ...Object.keys(zh)])].sort()
  const entries = {}
  for (const k of keys) entries[k] = { en: en[k] ?? null, zh: zh[k] ?? null }
  namespaces.push({ namespace: d.namespace, package: d.package, file: zhFile, entries })
}
namespaces.sort((a, b) => (a.namespace < b.namespace ? -1 : a.namespace > b.namespace ? 1 : 0))

for (const n of config.noDictionary) {
  const dir = path.join(dsh, 'packages', n.package, 'src')
  for (const f of walk(dir, [])) {
    const text = readFileSync(f, 'utf8')
    if (/locale\.register\(|export const zh\b|LocaleNamespaceMap/.test(text)) {
      throw new Error(`${n.package} is listed as having no dictionary but ${path.relative(dsh, f)} registers locale text`)
    }
  }
}

writeFileSync(args.get('--out'), JSON.stringify({
  irVersion: 1,
  kind: 'locale-catalog',
  noDictionary: config.noDictionary,
  inputs: [...new Set([...inputs, ...extraInputs])].sort(),
  namespaces,
}, null, 2) + '\n')
console.log(`extracted ${namespaces.length} namespaces, ${namespaces.reduce((a, n) => a + Object.keys(n.entries).length, 0)} keys`)
