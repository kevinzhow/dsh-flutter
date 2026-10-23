import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';

import 'workspace_path.dart';

/// A parsed, in-window tool call whose arguments are a JSON object (dsh
/// `ParsedToolCall`).
class ParsedCall {
  const ParsedCall(this.name, this.args);
  final String name;
  final Map<String, Object?> args;
}

/// Parse the call head paired with one tool block: null during preparation or
/// when valid object arguments are unavailable (dsh `parsedToolCall`).
ParsedCall? parsedCall(ToolCall call) {
  final String? raw = switch (call) {
    PreparingToolCall() => null,
    StartedToolCall(:final argsRaw) => argsRaw,
    ToolResult(:final callArgsRaw) => callArgsRaw,
  };
  if (raw == null) return null;
  try {
    final value = jsonDecode(raw);
    if (value is Map<String, Object?>) return ParsedCall(call.name, value);
  } on FormatException {
    // Malformed model JSON keeps the generic path.
  }
  return null;
}

/// The exact single text block card models read (dsh `singleResultText`).
String? singleResultText(ToolResult call) {
  if (call.content.length != 1) return null;
  final only = call.content.first;
  if (only is Map && only['type'] == 'text' && only['text'] is String) {
    return only['text'] as String;
  }
  return null;
}

/// One absolute location from opaque result metadata (dsh
/// `recordedAbsolutePath`): the file `path` or command `cwd`.
String? recordedAbsolutePath(Object? meta, String field) {
  if (meta is! Map) return null;
  final value = meta[field];
  return value is String && isAbsoluteWorkspacePath(value) ? value : null;
}

bool isRecord(Object? value) => value is Map<String, Object?>;

String firstLine(String text) {
  final nl = text.indexOf('\n');
  return nl == -1 ? text : text.substring(0, nl);
}

/// Parse a raw argument text into an object, or null.
Map<String, Object?>? parsedFromRaw(String raw) {
  try {
    final value = jsonDecode(raw);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}
