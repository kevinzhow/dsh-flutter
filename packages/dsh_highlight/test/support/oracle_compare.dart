import 'dart:convert';
import 'dart:io';

import 'package:dsh_highlight/dsh_highlight.dart';
import 'package:dsh_highlight/dsh_highlight_io.dart';

/// A character class + font style, as shiki reports it.
class CharStyle {
  const CharStyle(this.token, this.fontStyle);
  final HighlightToken? token;
  final int fontStyle; // 1 italic, 2 bold, 4 underline

  @override
  bool operator ==(Object other) =>
      other is CharStyle &&
      other.token == token &&
      other.fontStyle == fontStyle;
  @override
  int get hashCode => Object.hash(token, fontStyle);
  @override
  String toString() =>
      '${token?.name ?? 'fg'}${fontStyle == 0 ? '' : '/$fontStyle'}';
}

int fontBits(HighlightSpan s) =>
    (s.italic ? 1 : 0) | (s.bold ? 2 : 0) | (s.underline ? 4 : 0);

class Mismatch {
  Mismatch(this.file, this.line, this.column, this.char, this.shiki, this.ours);
  final String file;
  final int line;
  final int column;
  final String char;
  final CharStyle shiki;
  final CharStyle ours;
  @override
  String toString() =>
      '$file:${line + 1}:${column + 1} ${jsonEncode(char)} shiki=$shiki ours=$ours';
}

class LanguageReport {
  LanguageReport(this.grammar);
  final String grammar;
  int total = 0;
  int matched = 0;
  int lines = 0;
  final List<Mismatch> mismatches = [];
  final List<String> structural = [];

  double get percent => total == 0 ? 100 : 100 * matched / total;
}

final RegExp _space = RegExp(r'\s');

/// Loads the boot grammars (as dsh does) plus [grammar] into a fresh engine.
Future<HighlightEngine> engineFor(String grammar, {String? assets}) async {
  final engine = HighlightEngine(
    FileGrammarSource(assets ?? 'assets/grammars'),
    lineTimeLimit: Duration.zero, // the oracle runs without a limit too
  );
  for (final id in const ['typescript', 'shellscript', 'json']) {
    await engine.load(id);
  }
  await engine.load(grammar);
  return engine;
}

HighlightToken? _tokenByName(String? name) {
  if (name == null) return null;
  return HighlightToken.values.firstWhere((t) => t.name == name);
}

LanguageReport compareLanguage(
  HighlightEngine engine,
  String grammar, {
  String fixtures = 'test/fixtures',
}) {
  final oracle = jsonDecode(
    File('$fixtures/oracle/$grammar.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final report = LanguageReport(grammar);
  for (final f
      in (oracle['files'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final name = f['name'] as String;
    final source = File('$fixtures/samples/$grammar/$name').readAsStringSync();
    final ours = engine.highlightLines(source, grammar);
    if (ours == null) {
      report.structural.add('$name: highlightLines returned null');
      continue;
    }
    final want = (f['lines'] as List<dynamic>).cast<List<dynamic>>();
    if (ours.length != want.length) {
      report.structural.add(
        '$name: ${ours.length} lines, shiki ${want.length}',
      );
      continue;
    }
    for (var i = 0; i < want.length; i++) {
      report.lines++;
      final shikiChars = <CharStyle>[];
      final shikiText = StringBuffer();
      for (final t in want[i].cast<Map<String, dynamic>>()) {
        final text = t['text'] as String;
        final style = CharStyle(
          _tokenByName(t['token'] as String?),
          t['fontStyle'] as int,
        );
        for (var k = 0; k < text.length; k++) {
          shikiChars.add(style);
        }
        shikiText.write(text);
      }
      final ourChars = <CharStyle>[];
      final ourText = StringBuffer();
      for (final s in ours[i]) {
        final style = CharStyle(s.token, fontBits(s));
        for (var k = 0; k < s.text.length; k++) {
          ourChars.add(style);
        }
        ourText.write(s.text);
      }
      if (shikiText.toString() != ourText.toString()) {
        report.structural.add('$name:${i + 1}: text differs');
        continue;
      }
      final text = shikiText.toString();
      for (var c = 0; c < text.length; c++) {
        if (_space.hasMatch(text[c])) continue;
        report.total++;
        if (shikiChars[c] == ourChars[c]) {
          report.matched++;
        } else {
          report.mismatches.add(
            Mismatch(name, i, c, text[c], shikiChars[c], ourChars[c]),
          );
        }
      }
    }
  }
  return report;
}
