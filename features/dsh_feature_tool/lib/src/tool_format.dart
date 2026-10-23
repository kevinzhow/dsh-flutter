import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';

/// `web_fetch` / `web-fetch` / `webFetch` -> `webFetch`, the form of dsh's
/// `conversation` dictionary keys (`tool.title.webFetch`).
String toolKeyOf(String wireName) {
  final parts = wireName.split(RegExp(r'[_\-.\s]+')).where((p) => p.isNotEmpty);
  var first = true;
  return parts.map((p) {
    if (first) {
      first = false;
      return p[0].toLowerCase() + p.substring(1);
    }
    return p[0].toUpperCase() + p.substring(1);
  }).join();
}

/// Localized title of a tool: dsh's `tool.title.<name>` when it has one,
/// else the generic title followed by the wire name.
String toolTitle(DshI18n i18n, String wireName) {
  final key = 'tool.title.${toolKeyOf(wireName)}';
  if (i18n.has('conversation', key)) return i18n.t('conversation', key);
  final generic = i18n.t('conversation', 'tool.title.generic');
  return wireName.isEmpty ? generic : '$generic · $wireName';
}

/// Argument fields that best summarise a call, in order of preference.
const _summaryFields = [
  'command',
  'description',
  'path',
  'file_path',
  'filePath',
  'pattern',
  'query',
  'url',
  'prompt',
];

/// A one-line summary of the call's arguments (what it runs or touches),
/// empty when nothing readable has arrived.
String argsSummary(PartialArguments args, {int maxLength = 120}) {
  String? pick() {
    for (final f in _summaryFields) {
      final v = args.text(f);
      if (v != null && v.trim().isNotEmpty) return v;
    }
    for (final k in args.keys()) {
      final v = args.text(k);
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  final line = (pick() ?? '').trim().split('\n').first.trim();
  return line.length <= maxLength ? line : '${line.substring(0, maxLength)}…';
}

/// The arguments as readable text: indented JSON once it parses, the raw text
/// while it streams.
String argsPretty(String raw) {
  if (raw.trim().isEmpty) return '';
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } on FormatException {
    return raw;
  }
}

/// The text of a tool result: text blocks joined, other blocks as a marker.
String resultText(List<Object?> content) {
  final buffer = StringBuffer();
  for (final block in content) {
    if (block is Map && block['type'] == 'text') {
      buffer.write(block['text']);
    } else if (block is Map) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('[${block['type']}]');
    }
  }
  return buffer.toString();
}

/// The first [lines] lines of [text] and whether anything was cut.
({String text, bool cut}) previewLines(String text, {int lines = 3}) {
  final all = text.trimRight().split('\n');
  if (all.length <= lines) return (text: all.join('\n'), cut: false);
  return (text: all.take(lines).join('\n'), cut: true);
}
