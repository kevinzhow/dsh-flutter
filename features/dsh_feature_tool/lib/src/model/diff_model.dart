import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_ui/dsh_ui.dart';

import 'raw_call.dart';

/// Room for a path, one removed/added pair and three context lines each side
/// (dsh `CHAT_DIFF_MAX_LINES`).
const int chatDiffMaxLines = 9;

List<DshDiffHunk>? _narrowDiffs(Object? diffs) {
  if (diffs is! List || diffs.isEmpty) return null;
  final out = <DshDiffHunk>[];
  for (final hunk in diffs) {
    if (hunk is! Map) return null;
    final path = hunk['path'];
    final oldText = hunk['oldText'];
    final newText = hunk['newText'];
    if (path is! String) return null;
    if (oldText != null && oldText is! String) return null;
    if (newText is! String) return null;
    out.add(
      DshDiffHunk(path: path, oldText: oldText as String?, newText: newText),
    );
  }
  return out;
}

({String tool, DshDiffHunk diff})? _intendedDiff(ToolCall call) {
  final p = parsedCall(call);
  if (p == null) return null;
  final args = p.args;
  if (p.name == 'str_replace_editor') {
    final command = args['command'];
    final path = args['path'];
    if (path is! String || path.trim().isEmpty) return null;
    if (command == 'create') {
      final fileText = args['file_text'];
      if (args.containsKey('file_text') && fileText is! String) return null;
      return (
        tool: 'str_replace_editor',
        diff: DshDiffHunk(
          path: path,
          oldText: null,
          newText: (fileText as String?) ?? '',
        ),
      );
    }
    if (command == 'str_replace') {
      final oldText = args['old_str'];
      final newText = args['new_str'];
      if (args.containsKey('old_str') && oldText is! String) return null;
      if (args.containsKey('new_str') && newText is! String) return null;
      return (
        tool: 'str_replace_editor',
        diff: DshDiffHunk(
          path: path,
          oldText: oldText as String?,
          newText: (newText as String?) ?? '',
        ),
      );
    }
    return null;
  }
  final path = args['file_path'];
  if (path is! String || path.trim().isEmpty) return null;
  if (p.name == 'write') {
    final content = args['content'];
    return content is String
        ? (
            tool: 'write',
            diff: DshDiffHunk(path: path, oldText: null, newText: content),
          )
        : null;
  }
  if (p.name != 'edit') return null;
  final oldText = args['old_string'];
  final newText = args['new_string'];
  if (oldText is! String || newText is! String) return null;
  final replaceAll = args['replace_all'];
  if (args.containsKey('replace_all') && replaceAll is! bool) return null;
  return (
    tool: 'edit',
    diff: DshDiffHunk(
      path: path,
      oldText: oldText.isEmpty ? null : oldText,
      newText: newText,
    ),
  );
}

/// Valid applied hunks, `'empty'` for valid empty metadata, null otherwise.
Object? _appliedDiffs(Object? meta) {
  if (meta is! Map) return null;
  final diffs = meta['diffs'];
  if (diffs is! List) return null;
  if (diffs.isEmpty) return 'empty';
  return _narrowDiffs(diffs);
}

/// Derive the diff of a root write/edit (and the running
/// `str_replace_editor` create/replace) call, or null for the generic path
/// (dsh `diffCardModel`).
List<DshDiffHunk>? diffCardModel(ToolCall call) {
  if (call.parentCallId != null) return null;
  final intended = _intendedDiff(call);
  if (intended == null) return null;
  if (call is! ToolResult) return [intended.diff];
  if (intended.tool == 'str_replace_editor') return null;
  if (call.isError) return null;
  final applied = _appliedDiffs(call.meta);
  if (applied == null || applied == 'empty') {
    return intended.tool == 'write' ? [intended.diff] : null;
  }
  final path = recordedAbsolutePath(call.meta, 'path');
  return [
    for (final d in applied as List<DshDiffHunk>)
      d.path == path
          ? DshDiffHunk(
              path: intended.diff.path,
              oldText: d.oldText,
              newText: d.newText,
            )
          : d,
  ];
}
