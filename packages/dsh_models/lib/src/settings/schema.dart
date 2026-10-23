/// The schema of one settings namespace, as the Host serves it in
/// `settings.describe` (a serialized schemastery node graph), and the check a
/// client runs a section against before it accepts it.
///
/// A port of the part of dsh's `@deepseek-ai/schemastery` (`vendor/schemastery`)
/// that validation exercises: `Schema.resolve` and the resolvers of the types a
/// settings schema is built from, plus `rehydrate`/`validate`/`nodeAtPath`/
/// `getPath`/`hasPath` of the ui-settings `SettingsSchemaService`. Only
/// acceptance is reproduced: a transform's callback travels as source text and
/// is not run, so a transform accepts what its inner schema accepts, and a
/// `function` node never accepts wire data. `tool/vectors` replays real
/// serialized schemas and mutated values through the TypeScript implementation
/// and this one and compares the verdicts.
library;

/// A value failed a schema; [message] reads like schemastery's
/// `ValidationError` (`$.path[0] expected number but got x`).
class SettingsSchemaException implements Exception {
  SettingsSchemaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One node of a schema graph.
final class SettingsSchema {
  SettingsSchema._(this.type, this.meta)
    : rejectsAll = false,
      isMissing = false;

  /// A reference the envelope names but does not define (a dangling uid inside
  /// a `dict` or `list`). schemastery's own validation walk fails on it.
  SettingsSchema._missing()
    : type = null,
      meta = const <String, Object?>{},
      rejectsAll = false,
      isMissing = true;

  /// The schema of an envelope that rehydrates to nothing callable (its root
  /// uid is not among its refs): every value fails, the null one too.
  SettingsSchema._rejecting()
    : type = null,
      meta = const <String, Object?>{},
      rejectsAll = true,
      isMissing = false;

  final bool rejectsAll;
  final bool isMissing;

  /// Schemastery type name: `object`, `dict`, `array`, `tuple`, `union`,
  /// `intersect`, `string`, `number`, `boolean`, `const`, `any`, ...
  /// Null when the serialized node carried none.
  final String? type;

  /// UI and validation metadata (`default`, `required`, `min`, `max`, `step`,
  /// `pattern`, `description`, `role`, `volatile`, `loose`, ...).
  final Map<String, Object?> meta;

  /// Key schema of a `dict`.
  SettingsSchema? sKey;

  /// Element schema of an `array`, value schema of a `dict`, wrapped schema of
  /// a `transform`.
  SettingsSchema? inner;

  /// Members of a `tuple`, `union` or `intersect`.
  List<SettingsSchema>? list;

  /// Fields of an `object`.
  Map<String, SettingsSchema>? dict;

  /// Bit names of a `bitset`.
  Map<String, num>? bits;

  /// The constant of a `const` node.
  Object? value;

  /// The constructor name of an `is` node.
  String? constructorName;

  /// Rebuild the node graph of a serialized schema (`schema.toJSON()`:
  /// `{uid, refs: {uid: node}}`). Never throws on content a schema could not
  /// have produced: a malformed envelope yields a schema that rejects
  /// everything, as the TypeScript client's does.
  factory SettingsSchema.rehydrate(Object? serialized) {
    if (serialized == null) return SettingsSchema._rejecting();
    final envelope = serialized is Map ? serialized : null;
    final rawRefs = envelope?['refs'];
    if (rawRefs is! Map) {
      // Without refs schemastery uses the envelope itself as the node; a truthy
      // refs that is no object has no entry for the uid.
      final truthy =
          rawRefs != null && rawRefs != 0 && rawRefs != '' && rawRefs != false;
      return truthy
          ? SettingsSchema._rejecting()
          : SettingsSchema._(null, <String, Object?>{});
    }
    final refs = rawRefs.cast<Object?, Object?>();
    final built = <String, SettingsSchema>{};
    for (final entry in refs.entries) {
      final node = entry.value;
      // `new Schema(null)` throws, whether or not the entry is ever used.
      if (node == null) return SettingsSchema._rejecting();
      final map = node is Map ? node.cast<String, Object?>() : const {};
      // A list that is not an array throws in `options.list.map`.
      final list = map['list'];
      if (list != null &&
          list is! List &&
          list != 0 &&
          list != '' &&
          list != false) {
        return SettingsSchema._rejecting();
      }
      final meta = map['meta'];
      final schema = SettingsSchema._(
        map['type'] is String ? map['type'] as String : null,
        meta is Map ? meta.cast<String, Object?>() : <String, Object?>{},
      );
      schema.value = map['value'];
      schema.preserve = map['preserve'] == true;
      schema.constructorName = map['constructor'] is String
          ? map['constructor'] as String
          : null;
      final bits = map['bits'];
      if (bits is Map) {
        schema.bits = {
          for (final b in bits.entries)
            if (b.value is num) '${b.key}': b.value as num,
        };
      }
      built['${entry.key}'] = schema;
    }
    SettingsSchema? ref(Object? uid) => uid == null ? null : built['$uid'];
    for (final entry in refs.entries) {
      final node = entry.value;
      if (node is! Map) continue;
      final schema = built['${entry.key}']!;
      schema.sKey = ref(node['sKey']);
      schema.inner = ref(node['inner']);
      final list = node['list'];
      if (list is List) {
        schema.list = [
          for (final uid in list) ref(uid) ?? SettingsSchema._missing(),
        ];
      }
      final dict = node['dict'];
      if (dict is Map) {
        schema.dict = {
          for (final f in dict.entries)
            '${f.key}': ref(f.value) ?? SettingsSchema._missing(),
        };
      }
    }
    return built['${envelope!['uid']}'] ?? SettingsSchema._rejecting();
  }

  /// Whether `preserve` was set on a transform.
  bool preserve = false;

  /// The failure text of [data] against this schema, or null when it passes
  /// (`SettingsSchemaService.validate`). Never throws.
  String? validate(Object? data) {
    if (rejectsAll) return 'schema is not a function';
    try {
      _resolve(data, this, const <Object>[], false, <bool>[false]);
      return null;
    } on SettingsSchemaException catch (e) {
      return e.message;
    } on Object catch (e) {
      return '$e';
    }
  }

  /// The node at an object-key / array-index [path], or null when absent
  /// (`SettingsSchemaService.nodeAtPath`).
  SettingsSchema? nodeAtPath(List<String> path) {
    SettingsSchema? node = this;
    for (final key in path) {
      if (node == null) return null;
      if (node.type == 'object') {
        node = node.dict?[key];
      } else if (node.type == 'dict' || node.type == 'array') {
        node = node.inner;
      } else {
        return null;
      }
    }
    return node;
  }

  /// Declared default of this node, if any.
  Object? get defaultValue => meta['default'];

  /// `min` / `max` / `step` constraints of a number or collection node.
  num? get min => meta['min'] is num ? meta['min'] as num : null;
  num? get max => meta['max'] is num ? meta['max'] as num : null;
  num? get step => meta['step'] is num ? meta['step'] as num : null;

  /// The constants a union of `const` nodes offers (a closed choice), or an
  /// empty list for any other node.
  List<Object?> get choices {
    if (type == 'const') return [value];
    if (type != 'union' || list == null) return const [];
    final out = <Object?>[];
    for (final member in list!) {
      if (member.type != 'const') return const [];
      out.add(member.value);
    }
    return out;
  }

  /// Read a nested value by a string-key or array-index path (the schema
  /// service's `getPath`).
  static Object? getPath(Object? value, List<String> path) {
    Object? current = value;
    for (final key in path) {
      if (current is List) {
        final i = int.tryParse(key);
        current = i == null || i < 0 || i >= current.length ? null : current[i];
        continue;
      }
      if (current is! Map) return null;
      current = current[key];
    }
    return current;
  }

  /// Whether the final path key exists independently of its value (`hasPath`).
  static bool hasPath(Object? value, List<String> path) {
    if (path.isEmpty) return value != null;
    final parent = getPath(value, path.sublist(0, path.length - 1));
    final key = path.last;
    if (parent is List) {
      final i = int.tryParse(key);
      return i != null && i < parent.length;
    }
    if (parent is! Map) return false;
    return parent.containsKey(key);
  }
}

// ---- the resolver (vendor/schemastery/src/index.ts) --------------------------

bool _isNullable(Object? v) => v == null;

bool _isPlainObject(Object? v) => v is Map;

/// `deepEqual(a, b)` of cosmokit for JSON data (non-strict: null equals absent).
bool _deepEqual(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (identical(a, b) || a == b && (a is! Map && a is! List)) return true;
  if (_isNullable(a) && _isNullable(b)) return true;
  if (a == null || b == null) return false;
  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (b is List) return false;
  if (a is Map && b is Map) {
    final keys = <Object?>{...a.keys, ...b.keys};
    return keys.every((k) => _deepEqual(a[k], b[k]));
  }
  return false;
}

Object? _clone(Object? v) {
  if (v is List) return [for (final e in v) _clone(e)];
  if (v is Map) return {for (final e in v.entries) e.key: _clone(e.value)};
  return v;
}

String _display(Object? v) {
  // JS template interpolation of a JSON value (`${data}`): an array joins its
  // elements with commas and renders null as the empty string.
  if (v == null) return 'null';
  if (v is num) return _jsNumber(v);
  if (v is List) return v.map((e) => e == null ? '' : _display(e)).join(',');
  if (v is Map) return '[object Object]';
  if (v is _InheritedMember) {
    return 'function ${v.name == 'constructor' ? 'Object' : v.name}() { [native code] }';
  }
  return '$v';
}

String _path(List<Object> path) {
  var prefix = r'$';
  for (final segment in path) {
    prefix += segment is int ? '[$segment]' : '.$segment';
  }
  return prefix;
}

SettingsSchemaException _fail(String message, List<Object> path) {
  final prefix = _path(path);
  return SettingsSchemaException((prefix == r'$' ? '' : '$prefix ') + message);
}

/// JS `Number#toString`: shortest round-trip digits, positional notation for
/// exponents in [-7, 21), `e+N` otherwise, and `0` for -0. An integer beyond
/// 2^53 prints as the double JavaScript would have parsed.
String _jsNumber(num n) {
  if (n is int && n.abs() < 9007199254740992) return '$n';
  final d = n.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-Infinity' : 'Infinity';
  if (d == 0) return '0';
  final sign = d < 0 ? '-' : '';
  // `1.2345e+5`: Dart prints the digits JavaScript does (shortest round trip).
  final parts = d.abs().toStringAsExponential().split('e');
  final digits = parts[0].replaceAll('.', '');
  final point = int.parse(parts[1]) + 1; // position of the decimal point
  final k = digits.length;
  if (k <= point && point <= 21) return '$sign$digits${'0' * (point - k)}';
  if (0 < point && point <= 21) {
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }
  if (-6 < point && point <= 0) return '${sign}0.${'0' * -point}$digits';
  final exponent = point - 1;
  final mantissa = k == 1 ? digits : '${digits[0]}.${digits.substring(1)}';
  return '$sign${mantissa}e${exponent < 0 ? '-' : '+'}${exponent.abs()}';
}

Object? _resolve(
  Object? data,
  SettingsSchema? schema,
  List<Object> path,
  bool strict,
  List<bool> volatileChecked,
) {
  if (schema == null) return data;
  if (!volatileChecked[0]) {
    _validateVolatile(schema, path, false, {});
    volatileChecked[0] = true;
  }
  if (schema.meta['volatile'] == true) {
    // schemastery resolves the inner value, then wraps it in a reference.
    final unwrapped = SettingsSchema._(schema.type, {
      ...schema.meta,
      'volatile': false,
    });
    unwrapped
      ..sKey = schema.sKey
      ..inner = schema.inner
      ..list = schema.list
      ..dict = schema.dict
      ..bits = schema.bits
      ..value = schema.value
      ..constructorName = schema.constructorName
      ..preserve = schema.preserve;
    return _resolve(data, unwrapped, path, strict, volatileChecked);
  }
  if (_isNullable(data) && schema.type != 'lazy') {
    if (schema.meta['required'] == true) {
      throw _fail('missing required value', path);
    }
    var current = schema;
    var fallback = schema.meta['default'];
    while (current.type == 'intersect' && _isNullable(fallback)) {
      final members = current.list;
      if (members == null) throw _undefinedAccess('0');
      if (members.isEmpty) {
        fallback = null;
        break;
      }
      current = members.first;
      fallback = current.meta['default'];
    }
    if (_isNullable(fallback)) return data;
    data = _clone(fallback);
  }
  try {
    return _resolveType(data, schema, path, strict, volatileChecked);
  } on Object {
    // schemastery's `loose` swallows every error, TypeErrors included.
    if (schema.meta['loose'] != true) rethrow;
    return schema.meta['default'];
  }
}

/// The TypeError JavaScript raises reading [property] of an undefined schema
/// member (a dangling reference, or a node without its `list` / `inner`).
StateError _undefinedAccess(String property) =>
    StateError("Cannot read properties of undefined (reading '$property')");

void _validateVolatile(
  SettingsSchema schema,
  List<Object> path,
  bool blocked,
  Map<SettingsSchema, Set<bool>> seen,
) {
  if (schema.isMissing) throw _undefinedAccess('meta');
  final states = seen.putIfAbsent(schema, () => <bool>{});
  if (!states.add(blocked)) return;
  if (schema.meta['volatile'] == true && blocked) {
    throw _fail(
      'volatile fields require a fixed object path without an enclosing volatile field',
      path,
    );
  }
  final nested = blocked || schema.meta['volatile'] == true;
  final dict = schema.dict;
  if (dict != null) {
    for (final e in dict.entries) {
      _validateVolatile(e.value, [...path, e.key], nested, seen);
    }
  }
  if (schema.sKey != null) {
    _validateVolatile(schema.sKey!, [...path, '<key>'], true, seen);
  }
  if (schema.inner != null) {
    _validateVolatile(schema.inner!, [...path, '*'], true, seen);
  }
  final list = schema.list;
  if (list != null) {
    for (var i = 0; i < list.length; i++) {
      _validateVolatile(list[i], [...path, '$i'], true, seen);
    }
  }
}

/// What `data[key]` reads on a JavaScript object that lacks the own key:
/// the member every object inherits, a function that is not nullable.
final class _InheritedMember {
  const _InheritedMember(this.name);
  final String name;
}

const _objectPrototypeFunctions = {
  'constructor',
  'hasOwnProperty',
  'isPrototypeOf',
  'propertyIsEnumerable',
  'toLocaleString',
  'toString',
  'valueOf',
  '__defineGetter__',
  '__defineSetter__',
  '__lookupGetter__',
  '__lookupSetter__',
};

Object? _property(
  Object? container,
  Object key,
  SettingsSchema? schema,
  List<Object> path,
  List<bool> volatileChecked,
) {
  Object? value;
  if (container is List) {
    value = (key as int) < container.length ? container[key] : null;
  } else {
    final map = container as Map;
    value = map[key];
    if (value == null &&
        !map.containsKey(key) &&
        _objectPrototypeFunctions.contains(key)) {
      value = _InheritedMember('$key');
    }
  }
  return _resolve(value, schema, [...path, key], false, volatileChecked);
}

void _within(
  num data,
  Map<String, Object?> meta,
  String description,
  List<Object> path, {
  bool skipMin = false,
}) {
  final max = meta['max'] is num ? meta['max'] as num : double.infinity;
  final min = meta['min'] is num ? meta['min'] as num : double.negativeInfinity;
  if (data > max) {
    throw _fail(
      'expected $description <= ${_jsNumber(max)} but got ${_jsNumber(data)}',
      path,
    );
  }
  if (data < min && !skipMin) {
    throw _fail(
      'expected $description >= ${_jsNumber(min)} but got ${_jsNumber(data)}',
      path,
    );
  }
}

double _decimalShift(num data, int digits) {
  final str = _jsNumber(data);
  if (str.contains('e')) return data * _pow10(digits);
  final index = str.indexOf('.');
  if (index == -1) return data * _pow10(digits);
  final frac = str.substring(index + 1);
  final integer = str.substring(0, index);
  if (frac.length <= digits) {
    return double.parse(integer + frac.padRight(digits, '0'));
  }
  return double.parse(
    '$integer${frac.substring(0, digits)}.${frac.substring(digits)}',
  );
}

double _pow10(int digits) {
  var v = 1.0;
  for (var i = 0; i < digits; i++) {
    v *= 10;
  }
  return v;
}

bool _isMultipleOf(num data, num min, num step) {
  step = step.abs();
  if (!RegExp(r'^\d+\.\d+$').hasMatch(_jsNumber(step))) {
    return (data.toDouble() - min.toDouble()).remainder(step.toDouble()) == 0;
  }
  final text = _jsNumber(step);
  final digits = text.substring(text.indexOf('.') + 1).length;
  return (_decimalShift(data, digits) - _decimalShift(min, digits))
          .abs()
          .remainder(_decimalShift(step, digits)) ==
      0;
}

Object? _resolveType(
  Object? data,
  SettingsSchema schema,
  List<Object> path,
  bool strict,
  List<bool> checked,
) {
  final meta = schema.meta;
  switch (schema.type) {
    case 'any':
      return data;
    case 'never':
      throw _fail('expected nullable but got ${_display(data)}', path);
    case 'const':
      if (_deepEqual(data, schema.value)) return schema.value;
      throw _fail(
        'expected ${_display(schema.value)} but got ${_display(data)}',
        path,
      );
    case 'string':
      if (data is! String) {
        throw _fail('expected string but got ${_display(data)}', path);
      }
      final pattern = meta['pattern'];
      if (pattern is Map) {
        final compiled = _compilePattern(pattern);
        final matched = compiled.sticky
            ? compiled.regexp.matchAsPrefix(data) != null
            : compiled.regexp.hasMatch(data);
        if (!matched) {
          throw _fail('expect string to match regexp ${compiled.text}', path);
        }
      }
      _within(data.length, meta, 'string length', path);
      return data;
    case 'number':
      if (data is! num) {
        throw _fail('expected number but got ${_display(data)}', path);
      }
      _within(data, meta, 'number', path);
      final step = meta['step'];
      if (step is num &&
          step != 0 &&
          !_isMultipleOf(
            data,
            meta['min'] is num ? meta['min'] as num : 0,
            step,
          )) {
        throw _fail(
          'expected number multiple of ${_jsNumber(step)} but got ${_jsNumber(data)}',
          path,
        );
      }
      return data;
    case 'boolean':
      if (data is bool) return data;
      throw _fail('expected boolean but got ${_display(data)}', path);
    case 'bitset':
      final bits = schema.bits;
      var value = 0;
      if (data is num) {
        return data;
      } else if (data is List) {
        for (final key in data) {
          if (key is! String) {
            throw _fail('expected string but got ${_display(key)}', path);
          }
          // `key in bits` on an envelope that carries no bits.
          if (bits == null) throw StateError("Cannot use 'in' operator");
          if (bits.containsKey(key)) value |= bits[key]!.toInt();
        }
        return value;
      }
      throw _fail('expected number or array but got ${_display(data)}', path);
    case 'function':
      if (data is _InheritedMember) return data;
      throw _fail('expected function but got ${_display(data)}', path);
    case 'is':
      final name = schema.constructorName;
      if (_isNullable(data)) {
        throw _fail('expected $name but got ${_display(data)}', path);
      }
      final chain = switch (data) {
        String() => const ['String', 'Object'],
        num() => const ['Number', 'Object'],
        bool() => const ['Boolean', 'Object'],
        List() => const ['Array', 'Object'],
        _InheritedMember() => const ['Function', 'Object'],
        _ => const ['Object'],
      };
      if (chain.contains(name)) return data;
      throw _fail('expected $name but got ${_display(data)}', path);
    case 'array':
      if (data is! List) {
        throw _fail('expected array but got ${_display(data)}', path);
      }
      final inner = schema.inner;
      if (inner == null) throw _undefinedAccess('meta');
      _within(
        data.length,
        meta,
        'array length',
        path,
        skipMin: !_isNullable(inner.meta['default']),
      );
      return [
        for (var i = 0; i < data.length; i++)
          _property(data, i, inner, path, checked),
      ];
    case 'dict':
      if (!_isPlainObject(data)) {
        throw _fail('expected object but got ${_display(data)}', path);
      }
      final result = <String, Object?>{};
      for (final key in _jsKeyOrder((data as Map).keys)) {
        String rKey;
        try {
          rKey = '${_resolve(key, schema.sKey, path, false, checked)}';
        } on Object {
          if (strict) continue;
          rethrow;
        }
        result[rKey] = _property(data, key, schema.inner, path, checked);
      }
      return result;
    case 'tuple':
      if (data is! List) {
        throw _fail('expected array but got ${_display(data)}', path);
      }
      final members = schema.list;
      if (members == null) throw _undefinedAccess('map');
      final result = [
        for (var i = 0; i < members.length; i++)
          _property(data, i, members[i], path, checked),
      ];
      if (strict) return result;
      if (data.length > members.length) {
        result.addAll(data.sublist(members.length));
      }
      return result;
    case 'object':
      if (!_isPlainObject(data)) {
        throw _fail('expected object but got ${_display(data)}', path);
      }
      final map = data as Map;
      final result = <String, Object?>{};
      final fields = schema.dict ?? const <String, SettingsSchema>{};
      for (final key in _jsKeyOrder(fields.keys)) {
        final value = _property(map, key, fields[key], path, checked);
        if (!_isNullable(value) || map.containsKey(key)) {
          result[key] = value;
        }
      }
      if (!strict) _merge(result, map);
      return result;
    case 'union':
      final members = schema.list;
      if (members == null) throw StateError('list is not iterable');
      for (final inner in members) {
        try {
          return _resolve(data, inner, path, strict, checked);
        } on Object {
          // Every failure of a member, TypeErrors included, tries the next.
          continue;
        }
      }
      throw _fail('expected ${_describe(schema)} but got ${_json(data)}', path);
    case 'intersect':
      final members = schema.list;
      if (members == null) throw _undefinedAccess('length');
      if (members.isEmpty) return data;
      Object? result;
      for (final inner in members) {
        final value = _resolve(data, inner, path, true, checked);
        if (_isNullable(value)) continue;
        if (_isNullable(result)) {
          result = value;
        } else if (_jsType(result) != _jsType(value)) {
          throw _fail(
            'expected ${_describe(schema)} but got ${_json(data)}',
            path,
          );
        } else if (value is Map || value is List) {
          if (result is Map && value is Map) {
            _merge(result, value);
          }
        } else if (result != value) {
          throw _fail(
            'expected ${_describe(schema)} but got ${_json(data)}',
            path,
          );
        }
      }
      if (!strict && _isPlainObject(data) && result is Map) {
        _merge(result, data as Map);
      }
      return result;
    case 'transform':
      // The callback is source text on the wire; accept what the inner accepts.
      return _resolve(data, schema.inner, path, true, checked);
  }
  throw _fail('unsupported type "${schema.type ?? 'undefined'}"', path);
}

/// Own keys in the order a JavaScript `for...in` visits them: integer-like keys
/// ascending, then the others in insertion order.
List<String> _jsKeyOrder(Iterable<Object?> keys) {
  final integers = <int, String>{};
  final others = <String>[];
  for (final key in keys) {
    final text = '$key';
    final index = _arrayIndex(text);
    if (index == null) {
      others.add(text);
    } else {
      integers[index] = text;
    }
  }
  final ordered = integers.keys.toList()..sort();
  return [for (final i in ordered) integers[i]!, ...others];
}

const _flagOrder = 'dgimsuvy';

/// `new RegExp(source, flags)` as the schema's `pattern` meta builds it, with
/// the text JavaScript prints for it (`/source/flags`, flags normalised).
({RegExp regexp, String text, bool sticky}) _compilePattern(
  Map<Object?, Object?> pattern,
) {
  final source = pattern['source'] == null ? '' : '${pattern['source']}';
  final flags = pattern['flags'] == null ? '' : '${pattern['flags']}';
  final seen = <String>{};
  for (final flag in flags.split('')) {
    if (!_flagOrder.contains(flag) || !seen.add(flag)) {
      throw SettingsSchemaException(
        "Invalid flags supplied to RegExp constructor '$flags'",
      );
    }
  }
  if (seen.contains('u') && seen.contains('v')) {
    throw SettingsSchemaException(
      "Invalid flags supplied to RegExp constructor '$flags'",
    );
  }
  final regexp = RegExp(
    source,
    caseSensitive: !seen.contains('i'),
    multiLine: seen.contains('m'),
    dotAll: seen.contains('s'),
    unicode: seen.contains('u') || seen.contains('v'),
  );
  final normalised = [
    for (final flag in _flagOrder.split(''))
      if (seen.contains(flag)) flag,
  ].join();
  return (
    regexp: regexp,
    text: '/${_escapeRegExpSource(source)}/$normalised',
    sticky: seen.contains('y'),
  );
}

/// `RegExp.prototype.source`: an empty pattern prints `(?:)`, a `/` outside a
/// class and line terminators are escaped.
String _escapeRegExpSource(String source) {
  if (source.isEmpty) return '(?:)';
  final out = StringBuffer();
  var inClass = false;
  var escaped = false;
  for (final unit in source.codeUnits) {
    final char = String.fromCharCode(unit);
    if (escaped) {
      escaped = false;
      out.write(char);
      continue;
    }
    switch (char) {
      case r'\':
        escaped = true;
        out.write(char);
      case '[':
        inClass = true;
        out.write(char);
      case ']':
        inClass = false;
        out.write(char);
      case '/':
        out.write(inClass ? char : r'\/');
      case '\n':
        out.write(r'\n');
      case '\r':
        out.write(r'\r');
      case '\u2028':
        out.write(r'\u2028');
      case '\u2029':
        out.write(r'\u2029');
      default:
        out.write(char);
    }
  }
  return out.toString();
}

void _merge(Map<Object?, Object?> result, Map<Object?, Object?> data) {
  for (final key in data.keys) {
    if (result.containsKey(key)) continue;
    result[key] = data[key];
  }
}

String _jsType(Object? v) => switch (v) {
  null => 'object',
  bool() => 'boolean',
  num() => 'number',
  String() => 'string',
  _ => 'object',
};

/// `JSON.stringify` of a JSON value: integer-like keys first in ascending
/// order, then the others in insertion order, as a JavaScript object iterates.
String _json(Object? v) {
  if (v == null) return 'null';
  if (v is String) return _jsonString(v);
  if (v is num) return _jsNumber(v);
  if (v is bool) return '$v';
  if (v is _InheritedMember) return 'undefined';
  if (v is List) return '[${v.map(_json).join(',')}]';
  if (v is Map) {
    final integers = <MapEntry<int, Object?>>[];
    final others = <MapEntry<Object?, Object?>>[];
    for (final e in v.entries) {
      final index = _arrayIndex('${e.key}');
      if (index != null) {
        integers.add(MapEntry(index, e.key));
      } else {
        others.add(e);
      }
    }
    integers.sort((a, b) => a.key.compareTo(b.key));
    final ordered = [
      for (final e in integers) MapEntry<Object?, Object?>(e.value, v[e.value]),
      ...others,
    ];
    return '{${ordered.map((e) => '${_jsonString('${e.key}')}:${_json(e.value)}').join(',')}}';
  }
  return '$v';
}

int? _arrayIndex(String key) {
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(key)) return null;
  final value = int.tryParse(key);
  return value != null && value < 4294967295 ? value : null;
}

String _jsonString(String s) {
  final out = StringBuffer('"');
  final units = s.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        final highSurrogate = c >= 0xd800 && c <= 0xdbff;
        final lowSurrogate = c >= 0xdc00 && c <= 0xdfff;
        if (highSurrogate &&
            i + 1 < units.length &&
            units[i + 1] >= 0xdc00 &&
            units[i + 1] <= 0xdfff) {
          out
            ..writeCharCode(c)
            ..writeCharCode(units[++i]);
        } else if (c < 0x20 || highSurrogate || lowSurrogate) {
          out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(c);
        }
    }
  }
  return (out..write('"')).toString();
}

/// `schema.toString()` (a compact TypeScript-like type string), enough for the
/// union and intersect failure texts.
String _describe(SettingsSchema schema, [bool inline = false]) {
  switch (schema.type) {
    case 'any':
      return 'any';
    case 'never':
      return 'never';
    case 'const':
      return schema.value is String
          ? '"${schema.value}"'
          : _display(schema.value);
    case 'string':
    case 'number':
    case 'boolean':
    case 'bitset':
    case 'function':
      return schema.type!;
    case 'is':
      return schema.constructorName ?? '';
    case 'array':
      return '${_describe(schema.inner!, true)}[]';
    case 'dict':
      return '{ [key: ${_describe(schema.sKey!)}]: ${_describe(schema.inner!)} }';
    case 'tuple':
      return '[${(schema.list ?? []).map(_describe).join(', ')}]';
    case 'object':
      final dict = schema.dict ?? const <String, SettingsSchema>{};
      if (dict.isEmpty) return '{}';
      return '{ ${dict.entries.map((e) => '${e.key}${e.value.meta['required'] == true ? '' : '?'}: ${_describe(e.value)}').join(', ')} }';
    case 'union':
      final out = (schema.list ?? []).map(_describe).join(' | ');
      return inline ? '($out)' : out;
    case 'intersect':
      return (schema.list ?? []).map((s) => _describe(s, true)).join(' & ');
    case 'transform':
      return _describe(schema.inner!, inline);
  }
  return 'Schema<${schema.type ?? 'undefined'}>';
}
