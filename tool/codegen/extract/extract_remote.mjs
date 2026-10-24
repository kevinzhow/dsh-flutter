// Extract one Remote namespace of the pinned dsh checkout into a small JSON IR.
// Usage: node extract_remote.mjs --dsh <dsh-src> --node-dir <dir with node_modules/typescript> --out <ir.json>
//          --namespace <wire namespace> --entry <source file of the host class, relative to dsh> --class <host class name>
// Reads only the dsh sources; builds nothing. Resolves @deepseek-ai/* through dsh's own tsconfig.base.json paths.
// A parameter typed as a class is a Typert lookup parameter: its wire name is `<parameter>Id` and it carries a string.
import { createRequire } from 'node:module'
import { readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'

const args = new Map()
for (let i = 2; i < process.argv.length; i += 2) args.set(process.argv[i], process.argv[i + 1])
const dsh = path.resolve(args.get('--dsh'))
const nodeDir = path.resolve(args.get('--node-dir'))
const outFile = args.get('--out')
const ts = createRequire(path.join(nodeDir, 'package.json'))('typescript')

const NAMESPACE = args.get('--namespace')
const CLASS_NAME = args.get('--class')
const ENTRY = args.get('--entry')
if (!NAMESPACE || !CLASS_NAME || !ENTRY) throw new Error('--namespace, --class and --entry are required')
const entry = path.join(dsh, ENTRY)
const PKG = path.relative(dsh, path.dirname(path.dirname(entry)))

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

const trail = [] // the named types being converted, outermost first: names the path to a collision
function register(name, symbol, build) {
  const key = declKey(symbol)
  const existing = symbolOwner.get(name)
  if (existing !== undefined && existing !== key) {
    throw new Error(`type name collision: ${name} declared at ${existing} and ${key} (reached through ${trail.join(' > ')})`)
  }
  trackInput(symbol)
  if (existing === undefined) {
    symbolOwner.set(name, key)
    decls.set(name, null)
    trail.push(name)
    const ir = build()
    trail.pop()
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

// A duplex stream's uplink item type: the second argument of `RemoteStream<Out, In>` (`In` defaults to `never`).
function uplinkOf(type) {
  if (type.aliasSymbol?.name !== 'RemoteStream') return undefined
  const args = type.aliasTypeArguments ?? []
  return args.length >= 2 && !(args[1].flags & F.Never) ? args[1] : undefined
}

function unwrapResult(type, mode) {
  // Promise<T> / AsyncIterable<T> / Iterable<T> / RemoteStream<T, In>
  const sym = type.aliasSymbol?.name === 'RemoteStream' ? type.aliasSymbol : (type.getSymbol() ?? type.aliasSymbol)
  const args = type.aliasTypeArguments ?? checker.getTypeArguments(type)
  if (sym && ['Promise', 'AsyncIterable', 'Iterable', 'PromiseLike', 'RemoteStream'].includes(sym.name) && args.length >= 1) return args[0]
  if (mode === 'stream') throw new Error('stream method must return AsyncIterable<T> or RemoteStream<T, In>')
  return type
}

// ---- Typert lookups: `interface TypertLookupMap { agent: TypertLookup<Agent, SessionId> }` -------------------
const lookups = []
for (const file of program.getSourceFiles()) {
  if (file.isDeclarationFile) continue
  for (const statement of file.statements) {
    if (!ts.isModuleDeclaration(statement) || !ts.isStringLiteral(statement.name)
      || statement.name.text !== '@deepseek-ai/dsh-typert-protocol' || !statement.body || !ts.isModuleBlock(statement.body)) continue
    for (const nested of statement.body.statements) {
      if (!ts.isInterfaceDeclaration(nested) || nested.name.text !== 'TypertLookupMap') continue
      for (const member of nested.members) {
        if (!ts.isPropertySignature(member) || !member.type || !ts.isTypeReferenceNode(member.type)
          || member.type.typeArguments?.length !== 2) throw new Error('TypertLookupMap values must be TypertLookup<Host, Wire>')
        const host = checker.getTypeFromTypeNode(member.type.typeArguments[0]).getSymbol()
        lookups.push({ key: member.name.text, host, wire: checker.getTypeFromTypeNode(member.type.typeArguments[1]) })
      }
    }
  }
}
function lookupOf(typeNode) {
  const symbol = checker.getTypeFromTypeNode(typeNode).getSymbol()
  return symbol === undefined ? undefined : lookups.find(l => l.host === symbol)
}

const methods = []
const skipped = []
function visit(node) {
  if (ts.isClassDeclaration(node) && node.name?.text === CLASS_NAME) {
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
        let pname = p.name.text // wire name is the identifier verbatim, including a leading underscore
        if (pname === 'signal') {
          if (i !== m.parameters.length - 1) throw new Error('signal must be last in ' + hostName)
          cancellable = true
          continue
        }
        const ptype = checker.getTypeFromTypeNode(p.type)
        const lookup = lookupOf(p.type)
        if (lookup !== undefined) {
          // Typert lookup parameter (an Agent, a Session, ...): the wire carries its identity under `<key>Id`.
          if (p.questionToken !== undefined) throw new Error(`lookup parameter ${pname} in ${hostName} cannot be optional`)
          if (pname !== lookup.key) throw new Error(`lookup parameter for ${lookup.key} must also be named ${lookup.key} (in ${hostName})`)
          params.push({ name: `${lookup.key}Id`, optional: false, type: convert(lookup.wire, `${pascal(NAMESPACE)}${pascal(wireName)}${pascal(lookup.key)}Id`), lookup: lookup.key })
          continue
        }
        const hint = pascal(NAMESPACE) + pascal(wireName) + pascal(pname.replace(/^_+/, ''))
        // `x: T | undefined` is as absent-able on the wire as `x?: T`: JSON omits an undefined argument.
        const absent = p.questionToken !== undefined || (ptype.isUnion() && ptype.types.some(t => t.flags & F.Undefined))
        params.push({ name: pname, optional: absent, type: convert(ptype, hint) })
      }
      const sig = checker.getSignatureFromDeclaration(m)
      const declared = m.type ? checker.getTypeFromTypeNode(m.type) : checker.getReturnTypeOfSignature(sig)
      const result = unwrapResult(declared, mode)
      const uplinkType = mode === 'stream' ? uplinkOf(declared) : undefined
      const doc = docOf(checker.getSymbolAtLocation(m.name))
      // A result that may be undefined arrives as an absent value; the client sees it as null.
      const maybeUndefined = result.isUnion() && result.types.some(t => t.flags & F.Undefined)
      const converted = convert(result, pascal(NAMESPACE) + pascal(wireName) + 'Value')
      methods.push({
        name: wireName, hostName, mode, cancellable,
        params, result: maybeUndefined && converted.k !== 'nullable' ? { k: 'nullable', of: converted } : converted,
        ...(uplinkType ? { uplink: convert(uplinkType, pascal(NAMESPACE) + pascal(wireName) + 'Uplink') } : {}),
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
