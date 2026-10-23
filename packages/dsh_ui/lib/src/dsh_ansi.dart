/// ANSI SGR parsing for terminal output (dsh `ansi.ts`): colour runs per
/// line, theme tokens for the basic palette, literal rgb for the rest. Cursor
/// movement is reduced to what output cards need: `\r` redraws, backspace and
/// erase-in-line are replayed on a column buffer; every other control byte is
/// dropped so it cannot reach the screen as a literal character.
class AnsiColor {
  const AnsiColor.token(String this.token) : rgb = null;
  const AnsiColor.rgb(int this.rgb) : token = null;

  /// A `--dsw-*` colour token (the basic palette adapts to light and dark).
  final String? token;

  /// Literal 0xRRGGBB.
  final int? rgb;
}

class AnsiSpan {
  const AnsiSpan(
    this.text, {
    this.fg,
    this.bg,
    this.bold = false,
    this.dim = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.hidden = false,
  });

  final String text;
  final AnsiColor? fg;
  final AnsiColor? bg;
  final bool bold, dim, italic, underline, strike, hidden;

  bool get plain =>
      fg == null &&
      bg == null &&
      !bold &&
      !dim &&
      !italic &&
      !underline &&
      !strike &&
      !hidden;
}

typedef AnsiLine = List<AnsiSpan>;

// anser's palette -> the theme token dsh's TOKEN_BY_BASIC_RGB maps it to.
const _basic = <int, int>{
  30: 0x000000,
  31: 0xbb0000,
  32: 0x00bb00,
  33: 0xbbbb00,
  34: 0x0000bb,
  35: 0xbb00bb,
  36: 0x00bbbb,
  37: 0xffffff,
  90: 0x555555,
  91: 0xff5555,
  92: 0x00ff00,
  93: 0xffff55,
  94: 0x5555ff,
  95: 0xff55ff,
  96: 0x55ffff,
  97: 0xffffff,
};

const _token = <int, String>{
  0x000000: '--dsw-alias-label-primary',
  0xffffff: '--dsw-alias-label-primary',
  0x555555: '--dsw-alias-label-tertiary',
  0xbb0000: '--dsw-alias-state-error-primary',
  0xff5555: '--dsw-alias-state-error-secondary',
  0x00bb00: '--dsw-alias-state-success-primary',
  0x00ff00: '--dsw-alias-state-success-secondary',
  0xbbbb00: '--dsw-alias-state-warn-primary',
  0xffff55: '--dsw-alias-state-warn-secondary',
  0x0000bb: '--dsw-alias-state-business-primary',
  0x5555ff: '--dsw-static-blue-400',
  0x00bbbb: '--dsw-static-blue-600',
  0x55ffff: '--dsw-static-blue-500',
};

int _xterm256(int n) {
  if (n < 16) {
    const base = [
      30, 31, 32, 33, 34, 35, 36, 37, //
      90, 91, 92, 93, 94, 95, 96, 97,
    ];
    return _basic[base[n]]!;
  }
  if (n < 232) {
    final i = n - 16;
    int level(int v) => v == 0 ? 0 : 55 + v * 40;
    return (level(i ~/ 36) << 16) | (level((i ~/ 6) % 6) << 8) | level(i % 6);
  }
  final g = 8 + (n - 232) * 10;
  return (g << 16) | (g << 8) | g;
}

class _Sgr {
  _Sgr();
  String fg = '';
  String bg = '';
  final Set<String> attrs = {};

  _Sgr copy() => _Sgr()
    ..fg = fg
    ..bg = bg
    ..attrs.addAll(attrs);
}

void _fold(_Sgr s, String params) {
  final codes = params.isEmpty ? ['0'] : params.split(';');
  for (var i = 0; i < codes.length; i++) {
    final code = codes[i];
    if (code.isEmpty || code == '0') {
      s
        ..fg = ''
        ..bg = ''
        ..attrs.clear();
      continue;
    }
    if (code == '38' || code == '48') {
      final kind = i + 1 < codes.length ? codes[i + 1] : '';
      final span = kind == '2' ? 4 : (kind == '5' ? 2 : 0);
      final value = codes
          .sublist(i, (i + span + 1).clamp(0, codes.length))
          .join(';');
      if (code == '38') {
        s.fg = value;
      } else {
        s.bg = value;
      }
      i += span;
      continue;
    }
    const closers = {
      '22': ['1', '2'],
      '23': ['3'],
      '24': ['4'],
      '25': ['5', '6'],
      '27': ['7'],
      '28': ['8'],
      '29': ['9'],
    };
    final closes = closers[code];
    if (closes != null) {
      s.attrs.removeAll(closes);
      continue;
    }
    final n = int.tryParse(code);
    if (code == '39') {
      s.fg = '';
    } else if (code == '49') {
      s.bg = '';
    } else if (n != null && ((n >= 30 && n <= 37) || (n >= 90 && n <= 97))) {
      s.fg = code;
    } else if (n != null && ((n >= 40 && n <= 47) || (n >= 100 && n <= 107))) {
      s.bg = code;
    } else {
      s.attrs.add(code);
    }
  }
}

AnsiColor? _color(String spec, {required bool background}) {
  if (spec.isEmpty) return null;
  final parts = spec.split(';');
  int? rgb;
  if (parts[0] == '38' || parts[0] == '48') {
    if (parts.length >= 3 && parts[1] == '5') {
      final n = int.tryParse(parts[2]);
      if (n != null && n >= 0 && n <= 255) rgb = _xterm256(n);
    } else if (parts.length >= 5 && parts[1] == '2') {
      final r = int.tryParse(parts[2]);
      final g = int.tryParse(parts[3]);
      final b = int.tryParse(parts[4]);
      if (r != null && g != null && b != null) {
        rgb = ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
      }
    }
  } else {
    final n = int.tryParse(parts[0]);
    if (n != null) rgb = _basic[background ? (n >= 100 ? n - 10 : n - 10) : n];
  }
  if (rgb == null) return null;
  // A foreground-only run maps the basic palette onto a theme token; a run
  // that paints its own background keeps the literal pair.
  return AnsiColor.rgb(rgb);
}

final _osc = RegExp('\u001b\\][^\u0007\u001b]*(?:\u0007|\u001b\\\\)?');
final _nonCsi = RegExp('\u001b(?!\\[)[ -/]*[0-~]?');
final _inert = RegExp('[\u0000-\u0007\u000b-\u001a\u001c-\u001f\u007f]');
final _csi = RegExp('\u001b\\[([0-?]*)[ -/]*([@-~])');
final _needsReplay = RegExp('\r|\u0008');

class _Cell {
  _Cell(this.char, this.sgr);
  final String char;
  final _Sgr sgr;
}

/// Replays `\r` / backspace / erase-in-line on one line, re-emitting SGR.
String _replay(String line, _Sgr entry) {
  final cols = <_Cell?>[];
  var cursor = 0;
  final sgr = entry.copy();
  var at = 0;
  void consume(String chunk) {
    for (final rune in chunk.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '\r') {
        cursor = 0;
        continue;
      }
      if (ch == '\u0008') {
        cursor = cursor > 0 ? cursor - 1 : 0;
        continue;
      }
      if (ch == '\t') {
        final stop = cursor + 8 - (cursor % 8);
        for (; cursor < stop; cursor++) {
          while (cols.length <= cursor) {
            cols.add(null);
          }
          cols[cursor] ??= _Cell(' ', sgr.copy());
        }
        continue;
      }
      while (cols.length <= cursor) {
        cols.add(null);
      }
      cols[cursor] = _Cell(ch, sgr.copy());
      cursor++;
    }
  }

  for (final m in _csi.allMatches(line)) {
    consume(line.substring(at, m.start));
    at = m.end;
    final params = m.group(1)!;
    final fin = m.group(2)!;
    if (fin == 'K') {
      final mode = params.split(';').first;
      if (mode == '1') {
        for (var i = 0; i <= cursor && i < cols.length; i++) {
          cols[i] = _Cell(' ', sgr.copy());
        }
      } else if (mode == '2') {
        cols.clear();
      } else if (cols.length > cursor) {
        cols.removeRange(cursor, cols.length);
      }
      continue;
    }
    if (fin == 'm') _fold(sgr, params);
  }
  consume(line.substring(at));
  final out = StringBuffer();
  _Sgr active = entry.copy();
  String open(_Sgr s) {
    final codes = [
      ...s.attrs,
      if (s.fg.isNotEmpty) s.fg,
      if (s.bg.isNotEmpty) s.bg,
    ];
    return codes.isEmpty ? '' : '\u001b[${codes.join(';')}m';
  }

  bool same(_Sgr a, _Sgr b) =>
      a.fg == b.fg &&
      a.bg == b.bg &&
      a.attrs.length == b.attrs.length &&
      a.attrs.containsAll(b.attrs);

  for (final cell in cols) {
    final c = cell ?? _Cell(' ', _Sgr());
    if (!same(c.sgr, active)) {
      out.write('\u001b[0m');
      out.write(open(c.sgr));
      active = c.sgr;
    }
    out.write(c.char);
  }
  if (!same(active, sgr)) {
    out.write('\u001b[0m');
    out.write(open(sgr));
  }
  entry
    ..fg = sgr.fg
    ..bg = sgr.bg
    ..attrs.clear()
    ..attrs.addAll(sgr.attrs);
  return out.toString();
}

String _sanitize(String text) {
  final escaped = text.replaceAll(_osc, '').replaceAll(_nonCsi, '');
  final state = _Sgr();
  final lines = <String>[];
  for (final raw in escaped.split('\n')) {
    final line = raw.replaceFirst(RegExp(r'\r+$'), '');
    if (_needsReplay.hasMatch(line)) {
      lines.add(_replay(line, state));
    } else {
      lines.add(line);
      for (final m in _csi.allMatches(line)) {
        if (m.group(2) == 'm') _fold(state, m.group(1)!);
      }
    }
  }
  return lines.join('\n').replaceAll(_inert, '');
}

/// Parse [text] into styled lines; uncoloured output is one plain span per line.
List<AnsiLine> parseAnsiLines(String text) {
  final clean = _sanitize(text);
  var current = <AnsiSpan>[];
  final lines = <AnsiLine>[current];
  final sgr = _Sgr();
  var at = 0;
  void emit(String chunk) {
    if (chunk.isEmpty) return;
    final fg = _color(sgr.fg, background: false);
    final bg = _color(sgr.bg, background: true);
    final parts = chunk.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        current = <AnsiSpan>[];
        lines.add(current);
      }
      if (parts[i].isEmpty) continue;
      current.add(
        AnsiSpan(
          parts[i],
          fg: fg,
          bg: bg,
          bold: sgr.attrs.contains('1'),
          dim: sgr.attrs.contains('2'),
          italic: sgr.attrs.contains('3'),
          underline: sgr.attrs.contains('4'),
          strike: sgr.attrs.contains('9'),
          hidden: sgr.attrs.contains('8'),
        ),
      );
    }
  }

  for (final m in _csi.allMatches(clean)) {
    emit(clean.substring(at, m.start));
    at = m.end;
    if (m.group(2) == 'm') _fold(sgr, m.group(1)!);
  }
  emit(clean.substring(at));
  return lines;
}

/// The theme token for a literal basic-palette colour, when the run has no
/// background of its own (dsh's TOKEN_BY_BASIC_RGB).
String? ansiTokenFor(int rgb) => _token[rgb];
