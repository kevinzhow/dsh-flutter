import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_ui/dsh_ui.dart';

import 'raw_call.dart';
import 'workspace_path.dart';

/// Content lines a chat read body shows before folding (dsh `CHAT_READ_MAX_LINES`).
const int chatReadMaxLines = 8;

/// Result rows a chat search card keeps before folding.
const int chatSearchMaxLines = 8;

bool _positiveInteger(Object? v) => v is int && v >= 1;

bool _validReadCall(ToolCall call) {
  final p = parsedCall(call);
  if (p == null || p.name != 'read') return false;
  final path = p.args['file_path'];
  if (path is! String || path.trim().isEmpty) return false;
  for (final key in ['offset', 'limit']) {
    if (p.args.containsKey(key) && !_positiveInteger(p.args[key])) return false;
  }
  return true;
}

/// The line one `read` call was about (its 1-based `offset`), if it named one.
int? readCallLine(ToolCall call) {
  if (!_validReadCall(call)) return null;
  final offset = parsedCall(call)!.args['offset'];
  return _positiveInteger(offset) ? offset as int : null;
}

class ReadCardModel {
  const ReadCardModel({
    required this.label,
    required this.lines,
    required this.totalLines,
    this.lang,
  });
  final String label;
  final List<DshReadLine> lines;
  final int totalLines;
  final String? lang;
}

/// Derive a settled root read card after validating its persisted metadata and
/// the model-facing envelope (dsh `readCardModel`).
ReadCardModel? readCardModel(ToolCall call, {String? cwd, String? home}) {
  if (call is! ToolResult || call.parentCallId != null || call.isError) {
    return null;
  }
  if (!_validReadCall(call)) return null;
  final meta = call.meta;
  if (meta is! Map) return null;
  final path = meta['path'];
  final offset = meta['offset'];
  final lines = meta['lines'];
  final total = meta['totalLines'];
  final lang = meta['lang'];
  if (path is! String || offset is! int || offset < 1) return null;
  if (total is! int || total < 0 || lines is! List) return null;
  if (meta.containsKey('lang') && lang != null && lang is! String) return null;
  final narrowed = <DshReadLine>[];
  var previous = offset - 1;
  for (final line in lines) {
    if (line is! Map) return null;
    final number = line['number'];
    final text = line['text'];
    if (number is! int || number < 1 || number <= previous) return null;
    if (number > total || text is! String) return null;
    previous = number;
    narrowed.add(DshReadLine(number, text));
  }
  final text = singleResultText(call);
  if (text == null) return null;
  final body = RegExp(
    r'^<path>[^\n]*</path>\n<type>file</type>\n<content>\n([\s\S]*)\n</content>$',
  ).firstMatch(text);
  if (body == null) return null;
  return ReadCardModel(
    label: abbreviateHomePath(relativizeToCwd(path, cwd), home),
    lines: narrowed,
    totalLines: total,
    lang: lang as String?,
  );
}

/// Search card data plus the locator text of a capped result.
class SearchCardModel {
  const SearchCardModel.matches({
    required List<DshSearchFile> this.files,
    required this.truncated,
    required this.total,
    this.recovery,
  }) : paths = null;
  const SearchCardModel.paths({
    required List<String> this.paths,
    required this.truncated,
    required this.total,
    this.recovery,
  }) : files = null;

  final List<DshSearchFile>? files;
  final List<String>? paths;
  final bool truncated;
  final int total;
  final String? recovery;
}

String? _validSearchCall(ToolCall call) {
  final p = parsedCall(call);
  if (p == null) return null;
  final pattern = p.args['pattern'];
  if (pattern is! String) return null;
  if (p.name == 'grep' && pattern.isEmpty) return null;
  if (p.name == 'glob' && pattern.trim().isEmpty) return null;
  if (p.name != 'grep' && p.name != 'glob') return null;
  if (p.args.containsKey('path')) {
    final path = p.args['path'];
    if (path is! String || path.trim().isEmpty) return null;
  }
  if (p.name == 'grep' && p.args.containsKey('include')) {
    final include = p.args['include'];
    if (include is! String || !_validInclude(include)) return null;
  }
  return p.name;
}

bool _validInclude(String include) {
  if (include.trim().isEmpty || include.startsWith('!')) return false;
  var depth = 0;
  for (final c in include.split('')) {
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth = depth > 0 ? depth - 1 : 0;
    } else if (c == ',' && depth == 0) {
      return false;
    }
  }
  return true;
}

List<DshSearchFile>? _searchFiles(Object? value) {
  if (value is! List) return null;
  final files = <DshSearchFile>[];
  for (final file in value) {
    if (file is! Map) return null;
    final path = file['path'];
    final matches = file['matches'];
    if (path is! String || matches is! List) return null;
    final narrowed = <DshSearchMatch>[];
    for (final m in matches) {
      if (m is! Map) return null;
      final n = m['lineNumber'];
      final line = m['line'];
      if (n is! int || n < 1 || line is! String) return null;
      narrowed.add(DshSearchMatch(n, line));
    }
    files.add(DshSearchFile(path, narrowed));
  }
  return files;
}

String? _flattenContent(List<Object?> content) {
  final text = [
    for (final b in content)
      if (b is Map && b['type'] == 'text' && b['text'] is String)
        b['text'] as String,
  ].join('\n');
  return text.isEmpty ? null : text;
}

/// Derive a settled root grep/glob card from persisted metadata.
SearchCardModel? searchCardModel(ToolCall call) {
  if (call is! ToolResult || call.parentCallId != null || call.isError) {
    return null;
  }
  final tool = _validSearchCall(call);
  if (tool == null) return null;
  final meta = call.meta;
  if (meta is! Map) return null;
  final truncated = meta['truncated'];
  final total = meta['total'];
  if (truncated is! bool) return null;
  if (total is! int || total < 0) return null;
  final recovery = truncated ? _flattenContent(call.content) : null;
  if (tool == 'grep') {
    if (meta['shape'] != 'matches') return null;
    final files = _searchFiles(meta['files']);
    return files == null
        ? null
        : SearchCardModel.matches(
            files: files,
            truncated: truncated,
            total: total,
            recovery: recovery,
          );
  }
  if (meta['shape'] != 'paths' || meta['paths'] is! List) return null;
  final paths = meta['paths'] as List;
  if (!paths.every((p) => p is String)) return null;
  return SearchCardModel.paths(
    paths: [for (final p in paths) p as String],
    truncated: truncated,
    total: total,
    recovery: recovery,
  );
}

/// Web card data (dsh `WebCardModelProps`).
class WebCardModel {
  const WebCardModel.search({
    required List<DshWebSource> this.sources,
    required this.truncated,
    this.answer,
  }) : url = null,
       statusCode = null;
  const WebCardModel.fetch({
    required String this.url,
    required int this.statusCode,
    required this.truncated,
  }) : sources = null,
       answer = null;

  final List<DshWebSource>? sources;
  final String? answer;
  final String? url;
  final int? statusCode;
  final bool truncated;
}

String? _validWebCall(ToolCall call) {
  final p = parsedCall(call);
  if (p == null) return null;
  if (p.name == 'web_search') {
    final queries = p.args['queries'];
    if (queries is! List || queries.isEmpty) return null;
    return queries.every((q) => q is String && q.trim().isNotEmpty)
        ? p.name
        : null;
  }
  if (p.name == 'web_fetch') {
    final url = p.args['url'];
    return url is String && url.trim().isNotEmpty ? p.name : null;
  }
  return null;
}

List<DshWebSource>? _webSources(Object? value) {
  if (value is! List) return null;
  final out = <DshWebSource>[];
  for (final s in value) {
    if (s is! Map) return null;
    final url = s['url'];
    if (url is! String) return null;
    for (final k in ['title', 'snippet', 'publishedAt']) {
      if (s.containsKey(k) && s[k] != null && s[k] is! String) return null;
    }
    out.add(
      DshWebSource(
        url: url,
        title: s['title'] as String?,
        snippet: s['snippet'] as String?,
        publishedAt: s['publishedAt'] as String?,
      ),
    );
  }
  return out;
}

/// Derive a settled root web-search or web-fetch card from metadata.
WebCardModel? webCardModel(ToolCall call) {
  if (call is! ToolResult || call.parentCallId != null || call.isError) {
    return null;
  }
  final tool = _validWebCall(call);
  final meta = call.meta;
  if (tool == null || meta is! Map) return null;
  final truncated = meta['truncated'];
  if (truncated is! bool) return null;
  if (tool == 'web_search') {
    final sources = _webSources(meta['sources']);
    final answer = meta['answer'];
    if (sources == null || (answer != null && answer is! String)) return null;
    return WebCardModel.search(
      sources: sources,
      answer: answer as String?,
      truncated: truncated,
    );
  }
  final url = meta['url'];
  final status = meta['statusCode'];
  if (url is! String || status is! int) return null;
  return WebCardModel.fetch(url: url, statusCode: status, truncated: truncated);
}

/// The openable http(s) URL of a `web_fetch` call, from its arguments.
Uri? webFetchHref(ToolCall call) {
  final p = parsedCall(call);
  if (p == null || p.name != 'web_fetch' || p.args['url'] is! String) {
    return null;
  }
  return safeWebUri(p.args['url']! as String);
}
