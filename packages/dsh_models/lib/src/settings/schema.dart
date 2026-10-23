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
  SettingsSchema._(this.type, this.meta);

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
    if (serialized is! Map || serialized['refs'] is! Map) {
      return SettingsSchema._(null, <String, Object?>{});
    }
    final refs = (serialized['refs'] as Map).cast<Object?, Object?>();
    final built = <String, SettingsSchema>{};
    for (final entry in refs.entries) {
      final node = entry.value;
      final map = node is Map ? node.cast<String, Object?>() : const {};
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
          for (final uid in list)
            ref(uid) ?? SettingsSchema._('never', <String, Object?>{}),
        ];
      }
      final dict = node['dict'];
      if (dict is Map) {
        schema.dict = {
          for (final f in dict.entries)
            '${f.key}': ref(f.value) ?? SettingsSchema._(null, {}),
        };
      }
    }
    return built['${serialized['uid']}'] ??
        SettingsSchema._(null, <String, Object?>{});
  }

  /// Whether `preserve` was set on a transform.
  bool preserve = false;

  /// The failure text of [data] against this schema, or null when it passes
  /// (`SettingsSchemaService.validate`). Never throws.
  String? validate(Object? data) {
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
  // JS template interpolation of a JSON value (`${data}`).
  if (v == null) return 'null';
  if (v is num) return _jsNumber(v);
  if (v is List) return v.map(_display).join(',');
  if (v is Map) return '[object Object]';
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

/// JS `Number#toString` for the finite values JSON carries.
String _jsNumber(num n) {
  if (n is int) return '$n';
  final d = n.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-Infinity' : 'Infinity';
  if (d == d.truncateToDouble() && d.abs() < 1e21) return d.toStringAsFixed(0);
  return '$d';
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
      final first = current.list?.firstOrNull;
      if (first == null) {
        fallback = null;
        break;
      }
      current = first;
      fallback = current.meta['default'];
    }
    if (_isNullable(fallback)) return data;
    data = _clone(fallback);
  }
  try {
    return _resolveType(data, schema, path, strict, volatileChecked);
  } on SettingsSchemaException {
    if (schema.meta['loose'] != true) rethrow;
    return schema.meta['default'];
  }
}

void _validateVolatile(
  SettingsSchema schema,
  List<Object> path,
  bool blocked,
  Map<SettingsSchema, Set<bool>> seen,
) {
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

Object? _property(
  Object? container,
  Object key,
  SettingsSchema schema,
  List<Object> path,
  List<bool> volatileChecked,
) {
  final Object? value = container is List
      ? ((key as int) < container.length ? container[key] : null)
      : (container as Map)[key];
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
    return (data - min).toDouble().remainder(step.toDouble()) == 0;
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
        final source = '${pattern['source']}';
        final flags = '${pattern['flags'] ?? ''}';
        final regexp = RegExp(
          source,
          caseSensitive: !flags.contains('i'),
          multiLine: flags.contains('m'),
          dotAll: flags.contains('s'),
          unicode: flags.contains('u'),
        );
        if (!regexp.hasMatch(data)) {
          throw _fail('expect string to match regexp /$source/$flags', path);
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
      final bits = schema.bits ?? const {};
      var value = 0;
      if (data is num) {
        return data;
      } else if (data is List) {
        for (final key in data) {
          if (key is! String) {
            throw _fail('expected string but got ${_display(key)}', path);
          }
          if (bits.containsKey(key)) value |= bits[key]!.toInt();
        }
        return value;
      }
      throw _fail('expected number or array but got ${_display(data)}', path);
    case 'function':
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
        _ => const ['Object'],
      };
      if (chain.contains(name)) return data;
      throw _fail('expected $name but got ${_display(data)}', path);
    case 'array':
      if (data is! List) {
        throw _fail('expected array but got ${_display(data)}', path);
      }
      final inner = schema.inner;
      _within(
        data.length,
        meta,
        'array length',
        path,
        skipMin: !_isNullable(inner?.meta['default']),
      );
      return [
        for (var i = 0; i < data.length; i++)
          _property(data, i, inner!, path, checked),
      ];
    case 'dict':
      if (!_isPlainObject(data)) {
        throw _fail('expected object but got ${_display(data)}', path);
      }
      final result = <String, Object?>{};
      for (final key in (data as Map).keys.toList()) {
        String rKey;
        try {
          rKey = '${_resolve(key, schema.sKey, path, false, checked)}';
        } on SettingsSchemaException {
          if (strict) continue;
          rethrow;
        }
        result[rKey] = _property(
          data,
          key as Object,
          schema.inner!,
          path,
          checked,
        );
      }
      return result;
    case 'tuple':
      if (data is! List) {
        throw _fail('expected array but got ${_display(data)}', path);
      }
      final members = schema.list ?? const <SettingsSchema>[];
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
      for (final e
          in (schema.dict ?? const <String, SettingsSchema>{}).entries) {
        final value = _property(map, e.key, e.value, path, checked);
        if (!_isNullable(value) || map.containsKey(e.key)) {
          result[e.key] = value;
        }
      }
      if (!strict) _merge(result, map);
      return result;
    case 'union':
      for (final inner in schema.list ?? const <SettingsSchema>[]) {
        try {
          return _resolve(data, inner, path, strict, checked);
        } on SettingsSchemaException {
          continue;
        }
      }
      throw _fail('expected ${_describe(schema)} but got ${_json(data)}', path);
    case 'intersect':
      final members = schema.list ?? const <SettingsSchema>[];
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
  throw _fail('unsupported type "${schema.type}"', path);
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

String _json(Object? v) {
  if (v == null) return 'null';
  if (v is String) return '"$v"';
  if (v is num) return _jsNumber(v);
  if (v is bool) return '$v';
  if (v is List) return '[${v.map(_json).join(',')}]';
  if (v is Map) {
    return '{${v.entries.map((e) => '"${e.key}":${_json(e.value)}').join(',')}}';
  }
  return '$v';
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
  return 'Schema<${schema.type}>';
}
