import 'dart:convert';

/// Tolerant reader over a tool call's argument JSON while it streams (dsh
/// `PartialArguments`, `util/values/partial-json.ts`). Only the surface the chat
/// target and cards need: text so far, sealed state, and top-level field reads
/// that never throw. A field is `complete` once its value text has closed.
class PartialArguments {
  PartialArguments() : _sealed = false;

  /// A finished argument text (dsh `fromText`).
  PartialArguments.fromText(String text) : _text = text, _sealed = true;

  /// An already parsed argument payload, e.g. a PTC dispatch object.
  PartialArguments.fromObject(Object? value)
    : _text = value is Map ? jsonEncode(value) : '{}',
      _sealed = true;

  static final PartialArguments empty = PartialArguments.fromObject(const {});

  String _text = '';
  bool _sealed;

  bool get isSealed => _sealed;

  /// The argument text received so far.
  String get raw => _text;

  void append(String fragment) {
    if (_sealed) {
      throw StateError('PartialArguments: cannot append to a sealed view');
    }
    _text += fragment;
  }

  /// Reconcile a streamed prefix with the authoritative final text; the result
  /// is sealed (dsh `settle`; a matching prefix keeps the view, otherwise a new
  /// sealed view over the final text).
  PartialArguments settle(String text) {
    if (text == _text && !_sealed) {
      _sealed = true;
      return this;
    }
    return PartialArguments.fromText(text);
  }

  late final _Scan _scanCache = _Scan();
  int _scannedLength = -1;
  _Scan get _scan {
    if (_scannedLength != _text.length) {
      _scanCache.run(_text);
      _scannedLength = _text.length;
    }
    return _scanCache;
  }

  /// Top-level field names discovered so far, in order of appearance.
  List<String> keys() => [..._scan.fields.keys];

  bool has(String key) => _scan.fields.containsKey(key);

  /// Whether the field's value has been fully received.
  bool complete(String key) => _scan.fields[key]?.complete ?? false;

  /// The decoded text of a string field (what has arrived so far), else null.
  String? text(String key) {
    final f = _scan.fields[key];
    if (f == null || !f.isString) return null;
    return f.decoded;
  }

  /// The parsed JSON value of a completed non-string (or string) field.
  Object? value(String key) {
    final f = _scan.fields[key];
    if (f == null || !f.complete) return null;
    if (f.isString) return f.decoded;
    try {
      return jsonDecode(f.raw);
    } on FormatException {
      return null;
    }
  }
}

class _Field {
  _Field(this.isString);
  final bool isString;
  String raw = '';
  String decoded = '';
  bool complete = false;
}

/// One pass over the top-level object text; restarts on each change (argument
/// texts are small and the scan is linear).
class _Scan {
  final Map<String, _Field> fields = {};

  void run(String s) {
    fields.clear();
    var i = 0;
    while (i < s.length && s[i] != '{') {
      i++;
    }
    if (i >= s.length) return;
    i++;
    while (i < s.length) {
      i = _skipWs(s, i);
      if (i >= s.length || s[i] == '}') return;
      if (s[i] == ',') {
        i++;
        continue;
      }
      if (s[i] != '"') return;
      final key = _readString(s, i);
      if (key == null) return;
      i = key.$2;
      if (!key.$3) return;
      i = _skipWs(s, i);
      if (i >= s.length || s[i] != ':') return;
      i = _skipWs(s, i + 1);
      if (i >= s.length) {
        fields[key.$1] = _Field(false);
        return;
      }
      if (s[i] == '"') {
        final v = _readString(s, i);
        final f = _Field(true)
          ..decoded = v!.$1
          ..complete = v.$3;
        fields[key.$1] = f;
        i = v.$2;
        if (!v.$3) return;
      } else {
        final start = i;
        var depth = 0;
        var inString = false;
        var escape = false;
        var closed = false;
        while (i < s.length) {
          final c = s[i];
          if (inString) {
            if (escape) {
              escape = false;
            } else if (c == r'\') {
              escape = true;
            } else if (c == '"') {
              inString = false;
            }
          } else if (c == '"') {
            inString = true;
          } else if (c == '{' || c == '[') {
            depth++;
          } else if (c == '}' || c == ']') {
            if (depth == 0) {
              closed = true;
              break;
            }
            depth--;
          } else if (c == ',' && depth == 0) {
            closed = true;
            break;
          }
          i++;
        }
        final f = _Field(false)
          ..raw = s.substring(start, i).trim()
          ..complete = closed;
        fields[key.$1] = f;
        if (!closed) return;
      }
    }
  }

  static int _skipWs(String s, int i) {
    while (i < s.length &&
        (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) {
      i++;
    }
    return i;
  }

  /// Decode a JSON string starting at the opening quote: (text, next index,
  /// closed). An unterminated string yields what has arrived.
  static (String, int, bool)? _readString(String s, int start) {
    final out = StringBuffer();
    var i = start + 1;
    while (i < s.length) {
      final c = s[i];
      if (c == '"') return (out.toString(), i + 1, true);
      if (c == r'\') {
        if (i + 1 >= s.length) return (out.toString(), s.length, false);
        final n = s[i + 1];
        switch (n) {
          case 'n':
            out.write('\n');
          case 't':
            out.write('\t');
          case 'r':
            out.write('\r');
          case 'b':
            out.write('\b');
          case 'f':
            out.write('\f');
          case 'u':
            if (i + 6 > s.length) return (out.toString(), s.length, false);
            final hex = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
            if (hex != null) out.writeCharCode(hex);
            i += 4;
          default:
            out.write(n);
        }
        i += 2;
        continue;
      }
      out.write(c);
      i++;
    }
    return (out.toString(), s.length, false);
  }
}
