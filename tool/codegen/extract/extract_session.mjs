// Extract the `session` Remote namespace of the pinned dsh checkout into a small JSON IR.
// Usage: node extract_session.mjs --dsh <dsh-src> --node-dir <dir with node_modules/typescript> --out <ir.json>
// Reads only the dsh sources; builds nothing. Resolves @deepseek-ai/* through dsh's own tsconfig.base.json paths.
import { createRequire } from 'node:module'
import { readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'

const args = new Map()
for (let i = 2; i < process.argv.length; i += 2) args.set(process.argv[i], process.argv[i + 1])
const dsh = path.resolve(args.get('--dsh'))
const nodeDir = path.resolve(args.get('--node-dir'))
const outFile = args.get('--out')
const ts = createRequire(path.join(nodeDir, 'package.json'))('typescript')

const NAMESPACE = 'session'
const PKG = 'packages/api/session-controller'
const entry = path.join(dsh, PKG, 'src/index.ts')

// ---- program -------------------------------------------------------------
const baseCfg = ts.readConfigFile(path.join(dsh, 'tsconfig.base.json'), ts.sys.readFile)
if (baseCfg.error) throw new Error(ts.flattenDiagnosticMessageText(baseCfg.error.messageText, '\n'))
const conv = ts.convertCompilerOptionsFromJson(baseCfg.config.compilerOptions, dsh)
if (conv.errors.length) throw new Error(conv.errors.map(e => ts.flattenDiagnosticMessageText(e.messageText, '\n')).join('\n'))
const options = {
  ...conv.options,
  noEmit: true, composite: false, incremental: false, declaration: false, declarationMap: false,
  sourceMap: false, types: [], skipLibCheck: true, pathsBasePath: dsh,
}
const program = ts.createProgram({ rootNames: [entry], options })
const checker = program.getTypeChecker()
const sf = program.getSourceFile(entry)
if (!sf) throw new Error('entry not in program: ' + entry)

const inputs = new Set([path.relative(dsh, entry)])
const notes = []
const note = (s) => { if (!notes.includes(s)) notes.push(s) }
const rel = (f) => path.relative(dsh, f)

// ---- helpers ---------------------------------------------------------------
const pascal = (s) => s.replace(/(^|[^A-Za-z0-9]+)([A-Za-z0-9])/g, (_, __, c) => c.toUpperCase())
function docOf(symbol) {
  if (!symbol) return undefined
  const text = ts.displayPartsToString(symbol.getDocumentationComment(checker)).replace(/\s+/g, ' ').trim()
  return text === '' ? undefined : text
}

const decls = new Map() // name -> {symbolId, ir}
const symbolOwner = new Map() // name -> declaration file:line key

function isLibSymbol(sym) {
  const d = sym.declarations?.[0]
  return d !== undefined && program.isSourceFileDefaultLibrary(d.getSourceFile())
}

function nameOfType(type) {
  const alias = type.aliasSymbol
  if (alias && !isLibSymbol(alias)) return { name: alias.name, symbol: alias }
  const sym = type.getSymbol()
  if (sym && !['__type', '__object', 'Array', 'ReadonlyArray'].includes(sym.name) && sym.flags & (ts.SymbolFlags.Interface | ts.SymbolFlags.Class)) {
    return { name: sym.name, symbol: sym }
  }
  return undefined
}

function trackInput(symbol) {
  for (const d of symbol.declarations ?? []) {
    const sfile = d.getSourceFile()
    if (program.isSourceFileDefaultLibrary(sfile) || sfile.fileName.includes('node_modules')) continue
    inputs.add(rel(sfile.fileName))
  }
}

function declKey(symbol) {
  const d = symbol.declarations?.[0]
  return d ? `${rel(d.getSourceFile().fileName)}:${d.pos}` : symbol.name
}

function register(name, symbol, build) {
  const key = declKey(symbol)
  const existing = symbolOwner.get(name)
  if (existing !== undefined && existing !== key) {
    throw new Error(`type name collision: ${name} declared at ${existing} and ${key}`)
  }
  trackInput(symbol)
  if (existing === undefined) {
    symbolOwner.set(name, key)
    decls.set(name, null)
    const ir = build()
    ir.source = key.split(':')[0]
    const doc = docOf(symbol)
    if (doc) ir.doc = doc
    decls.set(name, ir)
  }
  return { k: 'ref', name }
}

const F = ts.TypeFlags
function isJsonValueAlias(type) {
  return type.aliasSymbol?.name === 'JsonValue' || type.aliasSymbol?.name === 'SessionProjectionValue'
}

function convert(type, hint) {
  // primitives
  if (type.flags & F.Any || type.flags & F.Unknown) {
    if (type.flags & F.Any && type.intrinsicName === 'error') note(`unresolved type in ${hint} degraded to Object?`)
    return { k: 'json' }
  }
  if (isJsonValueAlias(type)) return { k: 'json' }
  if (type.flags & F.Void) return { k: 'void' }
  if (type.flags & F.Never) return { k: 'never' }
  if (type.flags & F.Null) return { k: 'null' }
  if (type.flags & F.Undefined) return { k: 'undefined' }
  if (type.flags & F.String) return { k: 'str' }
  if (type.flags & F.Number) return { k: 'num' }
  if (type.flags & F.Boolean) return { k: 'bool' }
  if (type.flags & F.StringLiteral) return { k: 'lit', v: type.value }
  if (type.flags & F.NumberLiteral) return { k: 'lit', v: type.value }
  if (type.flags & F.BooleanLiteral) return { k: 'lit', v: type.intrinsicName === 'true' }
  if (type.flags & F.TemplateLiteral) return { k: 'str' }

  if (type.isIntersection()) {
    const parts = type.types
    const prim = parts.find(p => p.flags & (F.String | F.Number))
    if (prim && parts.every(p => p === prim || p.flags & F.Object)) {
      // Branded<...> string/number
      return prim.flags & F.String ? { k: 'str', brand: true } : { k: 'num', brand: true }
    }
    return convertObject(type, hint)
  }
  if (type.isUnion()) return convertUnion(type, hint)
  if (checker.isArrayType(type) || checker.isTupleType(type)) {
    if (checker.isTupleType(type)) {
      const args = checker.getTypeArguments(type)
      note(`tuple in ${hint} degraded to Object?`)
      void args
      return { k: 'json' }
    }
    const [el] = checker.getTypeArguments(type)
    return { k: 'arr', of: convert(el, hint + 'Item') }
  }
  if (type.flags & F.Object) return convertObject(type, hint)
  note(`type flags ${type.flags} in ${hint} degraded to Object?`)
  return { k: 'json' }
}

function convertUnion(type, hint) {
  const named = nameOfType(type)
  const build = () => {
    let members = type.types
    let nullable = false
    members = members.filter(m => {
      if (m.flags & F.Null) { nullable = true; return false }
      if (m.flags & F.Undefined) return false
      return true
    })
    const hasTrue = members.some(m => m.flags & F.BooleanLiteral && m.intrinsicName === 'true')
    const hasFalse = members.some(m => m.flags & F.BooleanLiteral && m.intrinsicName === 'false')
    if (hasTrue && hasFalse) members = [...members.filter(m => !(m.flags & F.BooleanLiteral)), checker.getBooleanType()]
    let ir
    const primOf = m => (m.flags & F.Number ? 'num' : m.flags & F.String ? 'str'
      : m.isIntersection() && m.types.some(t => t.flags & F.Number) ? 'num'
        : m.isIntersection() && m.types.some(t => t.flags & F.String) ? 'str' : undefined)
    const prim = members.map(primOf).find(Boolean)
    if (prim) {
      // `number | -1` style unions collapse to the primitive
      const flag = prim === 'num' ? F.NumberLiteral : F.StringLiteral
      members = members.filter(m => !(m.flags & flag))
    }
    if (members.length === 1) ir = convert(members[0], hint)
    else if (members.every(m => m.flags & F.StringLiteral)) {
      ir = { k: 'enum', values: members.map(m => m.value).sort() }
    } else {
      ir = { k: 'union', members: members.map(m => convert(m, hint)) }
    }
    return { ir, nullable }
  }
  const { ir, nullable } = build()
  let out = ir
  if (named && (ir.k === 'enum' || ir.k === 'union')) {
    const symbol = named.symbol
    const ref = register(named.name, symbol, () => ir.k === 'enum' ? { ...ir } : { ...ir })
    out = ref
  }
  return nullable ? { k: 'nullable', of: out } : out
}

function convertObject(type, hint) {
  const named = nameOfType(type)
  const build = (h) => {
    const props = checker.getPropertiesOfType(type)
    const indexInfos = checker.getIndexInfosOfType(type)
    const stringIndex = indexInfos.find(i => !(i.keyType.flags & F.NumberLike))
    if (props.length === 0 && stringIndex) return { k: 'rec', of: convert(stringIndex.type, h + 'Value') }
    const out = { k: 'obj', props: [] }
    for (const p of props) {
      trackInput(p)
      const decl = p.valueDeclaration ?? p.declarations?.[0]
      const t = checker.getTypeOfSymbolAtLocation(p, decl ?? sf)
      const optional = (p.flags & ts.SymbolFlags.Optional) !== 0
      let pt = t
      if (optional) pt = checker.getNonNullableType(t) === t ? t : t // keep null if declared
      const irp = { name: p.name, optional, type: convert(stripUndefined(pt), h + pascal(p.name)) }
      const d = docOf(p)
      if (d) irp.doc = d
      out.props.push(irp)
    }
    if (stringIndex) out.extras = convert(stringIndex.type, h + 'Extra')
    return out
  }
  if (named) {
    return register(named.name, named.symbol, () => build(named.name))
  }
  return build(hint)
}

function stripUndefined(t) {
  if (t.isUnion() && t.types.some(m => m.flags & F.Undefined)) {
    const rest = t.types.filter(m => !(m.flags & F.Undefined))
    if (rest.length === 1) return rest[0]
    return checker.getUnionType ? t : t
  }
  return t
}

// ---- decorators -------------------------------------------------------------
function decoratorsOf(node) {
  return ts.canHaveDecorators(node) ? (ts.getDecorators(node) ?? []) : []
}
function remoteInfo(dec) {
  const e = dec.expression
  let call = ts.isCallExpression(e) ? e : undefined
  const id = call ? call.expression : e
  if (!ts.isIdentifier(id) || id.text !== 'Remote') return undefined
  const info = {}
  const arg = call?.arguments[0]
  if (arg && ts.isStringLiteral(arg)) info.name = arg.text
  else if (arg && ts.isObjectLiteralExpression(arg)) {
    for (const p of arg.properties) {
      if (ts.isPropertyAssignment(p) && ts.isIdentifier(p.name)) {
        if (p.name.text === 'name' && ts.isStringLiteral(p.initializer)) info.name = p.initializer.text
        if (p.name.text === 'mode' && ts.isStringLiteral(p.initializer)) info.mode = p.initializer.text
      }
    }
  }
  return info
}

function unwrapResult(type, mode) {
  // Promise<T> / AsyncIterable<T> / Iterable<T>
  const sym = type.getSymbol() ?? type.aliasSymbol
  const args = type.aliasTypeArguments ?? checker.getTypeArguments(type)
  if (sym && ['Promise', 'AsyncIterable', 'Iterable', 'PromiseLike'].includes(sym.name) && args.length >= 1) return args[0]
  if (mode === 'stream') throw new Error('stream method must return AsyncIterable<T>')
  return type
}

const methods = []
const skipped = []
function visit(node) {
  if (ts.isClassDeclaration(node) && node.name?.text === 'SessionController') {
    for (const m of node.members) {
      if (!ts.isMethodDeclaration(m)) continue
      const rd = decoratorsOf(m).map(remoteInfo).find(Boolean)
      if (!rd) continue
      const hostName = m.name.text
      const wireName = rd.name ?? hostName
      const mode = rd.mode ?? 'unary'
      const params = []
      let cancellable = false
      for (const [i, p] of m.parameters.entries()) {
        const pname = p.name.text // wire name is the identifier verbatim, including a leading underscore
        if (pname === 'signal') {
          if (i !== m.parameters.length - 1) throw new Error('signal must be last in ' + hostName)
          cancellable = true
          continue
        }
        const ptype = checker.getTypeFromTypeNode(p.type)
        const sym = ptype.getSymbol()
        if (sym && (sym.flags & ts.SymbolFlags.Class)) throw new Error(`lookup parameter ${pname} in ${hostName}: needs agentId/sessionId rename rule`)
        const hint = pascal(NAMESPACE) + pascal(wireName) + pascal(pname.replace(/^_+/, ''))
        params.push({ name: pname, optional: p.questionToken !== undefined, type: convert(ptype, hint) })
      }
      const sig = checker.getSignatureFromDeclaration(m)
      const declared = m.type ? checker.getTypeFromTypeNode(m.type) : checker.getReturnTypeOfSignature(sig)
      const result = unwrapResult(declared, mode)
      const doc = docOf(checker.getSymbolAtLocation(m.name))
      methods.push({
        name: wireName, hostName, mode, cancellable,
        params, result: convert(result, pascal(NAMESPACE) + pascal(wireName) + 'Value'),
        ...(doc ? { doc } : {}),
      })
    }
  }
  ts.forEachChild(node, visit)
}
visit(sf)

// Skipped Remote methods: none are skipped by the extractor; policy is decided by gen.py (SKIP list).
const sorted = [...decls.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
const ir = {
  irVersion: 1,
  kind: 'remote-namespace',
  namespace: NAMESPACE,
  package: PKG,
  typescript: ts.version,
  inputs: [...inputs].sort(),
  methods,
  decls: Object.fromEntries(sorted),
  notes: notes.sort(),
  skipped,
}
writeFileSync(outFile, JSON.stringify(ir, null, 2) + '\n')
console.log(`extracted ${methods.length} methods, ${decls.size} named types, ${notes.length} notes`)
