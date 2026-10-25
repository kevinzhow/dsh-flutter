import 'document.dart';

// Published credential formats of the pinned ui-secret-mask. Literal scanning
// and memoized class runs avoid unbounded lookahead/backtracking expressions.
const _key = 1, _alnum = 2, _word = 4, _dash = 8, _upper = 16;
const _run = 0, _bounded = 1, _sk = 2, _google = 3, _jwt = 4;
const _block = 0, _address = 1, _prefixed = 2;
typedef _Format = (String, int, int, int, int);
const _formats = <_Format>[
  ('sk-', _sk, _key, 20, 0),
  ('AIza', _google, _key, 35, 0),
  ('ghp_', _run, _alnum, 36, 0),
  ('gho_', _run, _alnum, 36, 0),
  ('ghu_', _run, _alnum, 36, 0),
  ('ghs_', _run, _alnum, 36, 0),
  ('ghr_', _run, _alnum, 36, 0),
  ('github_pat_', _run, _word, 22, 0),
  ('glpat-', _run, _key, 20, 0),
  ('npm_', _run, _alnum, 36, 0),
  ('hf_', _run, _alnum, 30, 0),
  ('AKIA', _bounded, _upper, 16, 16),
  ('ASIA', _bounded, _upper, 16, 16),
  ('LTAI', _bounded, _alnum, 12, 20),
  ('AKID', _bounded, _alnum, 28, 36),
  ('xoxa-', _run, _dash, 10, 0),
  ('xoxb-', _run, _dash, 10, 0),
  ('xoxp-', _run, _dash, 10, 0),
  ('xoxr-', _run, _dash, 10, 0),
  ('xoxs-', _run, _dash, 10, 0),
  ('sk_live_', _run, _alnum, 16, 0),
  ('sk_test_', _run, _alnum, 16, 0),
  ('rk_live_', _run, _alnum, 16, 0),
  ('rk_test_', _run, _alnum, 16, 0),
  ('whsec_', _run, _alnum, 24, 0),
  ('eyJ', _jwt, _key, 8, 2048),
];

class _Candidate {
  const _Candidate(this.start, this.end, this.kind);
  final int start, end, kind;
}

class CredentialScanner {
  CredentialScanner()
    : _prefixes = RegExp(
        [
          '-----BEGIN ',
          '://',
          ..._formats.map((f) => f.$1),
        ].map(RegExp.escape).join('|'),
      );
  final RegExp _prefixes;
  String? _text;
  List<_Candidate> _candidates = const [];
  final _runs = <int, List<(int, int)>>{};
  final _digits = <(int, int)>[];
  (int, int, int)? _blockEnd;

  UserTextNode? match(String text, int from) {
    if (_text != text) _prepare(text);
    var low = 0, high = _candidates.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_candidates[middle].start < from) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == _candidates.length) return null;
    final first = _candidates[low];
    var end = first.end;
    for (
      var i = low + 1;
      i < _candidates.length && _candidates[i].start < end;
      i++
    ) {
      if (_candidates[i].end > end) end = _candidates[i].end;
    }
    final raw = text.substring(first.start, end);
    final masked = switch (first.kind) {
      _address => _mask(raw),
      _prefixed => raw.substring(0, 8) + _mask(raw.substring(8)),
      _ => _maskBlock(raw),
    };
    return UserTextNode('secret', first.start, end, {'masked': masked});
  }

  void _prepare(String text) {
    _text = text;
    _runs.clear();
    _digits.clear();
    _blockEnd = null;
    final candidates = <_Candidate>[];
    var cursor = 0;
    while (cursor < text.length) {
      final found = _prefixes.allMatches(text, cursor).firstOrNull;
      if (found == null) break;
      final at = found.start;
      final literal = found.group(0)!;
      // A literal's final character may begin another literal.
      cursor = at + 1;
      if (literal == '://') {
        final password = _password(text, at);
        if (password != null) {
          candidates.add(_Candidate(password.$1, password.$2, _address));
        }
      } else if (literal == '-----BEGIN ') {
        final end = _keyBlock(text, at);
        if (end >= 0) candidates.add(_Candidate(at, end, _block));
      } else {
        final format = _formats.firstWhere((f) => f.$1 == literal);
        final end = _tokenEnd(text, at, format);
        if (end >= 0) candidates.add(_Candidate(at, end, _prefixed));
      }
    }
    candidates.sort((a, b) {
      final start = a.start.compareTo(b.start);
      return start == 0 ? a.kind.compareTo(b.kind) : start;
    });
    _candidates = candidates;
  }

  int _runEnd(String text, int start, int kind) {
    final memo = _runs.putIfAbsent(kind, () => []);
    for (final (from, end) in memo) {
      if (from <= start && start <= end) return end;
    }
    var end = start;
    while (end < text.length && _inClass(text.codeUnitAt(end), kind)) {
      end++;
    }
    // Four runs suffice for a token's header, payload, signature and next run.
    if (memo.length == 4) memo.removeAt(0);
    memo.add((start, end));
    return end;
  }

  int _nextDigit(String text, int start) {
    for (final (from, at) in _digits) {
      if (from <= start && start <= at) return at;
    }
    var at = start;
    while (at < text.length && !_digit(text.codeUnitAt(at))) {
      at++;
    }
    _digits
      ..clear()
      ..add((start, at));
    return at;
  }

  int _tokenEnd(String text, int at, _Format f) {
    if (_wordAt(text, at - 1)) return -1;
    final start = at + f.$1.length, shape = f.$2, min = f.$4;
    if (shape == _sk && _nextDigit(text, start) - start > 255) return -1;
    final end = _runEnd(text, start, f.$3);
    final length = end - start;
    if (length < min) return -1;
    if (shape == _sk) return _nextDigit(text, start) < end ? end : -1;
    if (shape == _run) return end;
    if (shape == _google) return start + min;
    if (shape == _bounded) {
      return length <= f.$5 && !_wordAt(text, end) ? end : -1;
    }
    if (length > f.$5 || !text.startsWith('.eyJ', end)) return -1;
    final payloadStart = end + 4;
    final payloadEnd = _runEnd(text, payloadStart, _key);
    if (payloadEnd - payloadStart < min || _code(text, payloadEnd) != 46) {
      return -1;
    }
    final signatureEnd = _runEnd(text, payloadEnd + 1, _key);
    return signatureEnd - payloadEnd - 1 >= min ? signatureEnd : -1;
  }

  int _labelEnd(String text, int start) {
    var index = start;
    final limit = (start + 52).clamp(0, text.length);
    while (index < limit && _label(_code(text, index))) {
      index++;
    }
    final tail = index - 11;
    return index < start + 52 &&
            tail >= start &&
            text.startsWith('PRIVATE KEY-----', tail)
        ? tail + 16
        : -1;
  }

  int _keyBlock(String text, int at) {
    final header = _labelEnd(text, at + 11);
    if (header < 0) return -1;
    final memo = _blockEnd;
    if (memo != null && memo.$1 <= header && header <= memo.$2) return memo.$3;
    var end = text.length, lineAt = text.length;
    for (
      var line = text.indexOf('-----END ', header);
      line >= 0;
      line = text.indexOf('-----END ', line + 1)
    ) {
      final candidate = _labelEnd(text, line + 9);
      if (candidate < 0) continue;
      end = candidate;
      lineAt = line;
      break;
    }
    _blockEnd = (header, lineAt, end);
    return end;
  }

  bool _schemeBefore(String text, int at) {
    for (var start = at - 1; start >= 0 && start >= at - 16; start--) {
      final code = text.codeUnitAt(start);
      if (!_lower(code) &&
          !_digit(code) &&
          code != 43 &&
          code != 46 &&
          code != 45) {
        return false;
      }
      if (_lower(code) && at - start >= 2 && !_wordAt(text, start - 1)) {
        return true;
      }
    }
    return false;
  }

  (int, int)? _password(String text, int at) {
    if (!_schemeBefore(text, at)) return null;
    final userStart = at + 3;
    final userEnd = _runEnd(text, userStart, 256);
    if (userEnd - userStart > 256 || _code(text, userEnd) != 58) return null;
    final start = userEnd + 1, end = _runEnd(text, userEnd + 1, 512);
    return end > start && _code(text, end) == 64 ? (start, end) : null;
  }
}

UserTextRule createSecretRule() {
  final scanner = CredentialScanner();
  return UserTextRule(
    id: 'secret',
    order: 0,
    match: (text, from, _) => scanner.match(text, from),
  );
}

int _code(String text, int index) =>
    index < 0 || index >= text.length ? -1 : text.codeUnitAt(index);
bool _digit(int c) => c >= 48 && c <= 57;
bool _lower(int c) => c >= 97 && c <= 122;
bool _upperCase(int c) => c >= 65 && c <= 90;
bool _wordAt(String text, int at) => _inClass(_code(text, at), _word);
bool _label(int c) => _upperCase(c) || _digit(c) || c == 32;
bool _space(int c) =>
    (c >= 9 && c <= 13) ||
    c == 32 ||
    c == 0xa0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200a) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202f ||
    c == 0x205f ||
    c == 0x3000 ||
    c == 0xfeff;
bool _inClass(int c, int kind) {
  if (c < 0) return false;
  if (kind == 256 || kind == 512) {
    return !_space(c) &&
        c != 47 &&
        c != 64 &&
        c != 63 &&
        c != 35 &&
        (kind == 512 || c != 58);
  }
  final alnum = _lower(c) || _upperCase(c) || _digit(c);
  return switch (kind) {
    _key => alnum || c == 95 || c == 45,
    _alnum => alnum,
    _word => alnum || c == 95,
    _dash => alnum || c == 45,
    _upper => _upperCase(c) || _digit(c),
    _ => false,
  };
}

String _mask(String value) =>
    String.fromCharCodes(value.runes.map((c) => c == 10 || c == 13 ? c : 42));
String _maskBlock(String value) {
  final start = value.indexOf('\n') + 1;
  final last = value.lastIndexOf('\n-----END');
  final end = last < start ? value.length : last;
  return value.substring(0, start) +
      _mask(value.substring(start, end)) +
      value.substring(end);
}
