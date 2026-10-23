import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';

import 'raw_call.dart';
import 'workspace_path.dart';

/// Tool-call row variants (dsh `ToolRowVariant`).
enum ToolRowVariant { search, read, bash, write, edit, code, others }

/// Row lifecycle state for summary styling and accessible status text.
enum ToolRowState { preparing, running, ok, error, stopped }

const _variantTitleKeys = {
  ToolRowVariant.search: 'tool.title.search',
  ToolRowVariant.read: 'tool.title.read',
  ToolRowVariant.bash: 'tool.title.bash',
  ToolRowVariant.write: 'tool.title.write',
  ToolRowVariant.edit: 'tool.title.edit',
  ToolRowVariant.code: 'tool.title.code',
  ToolRowVariant.others: 'tool.title.generic',
};

/// Known tool name -> variant (dsh `TOOL_VARIANTS`).
const _toolVariants = {
  'bash': ToolRowVariant.bash,
  'pwsh': ToolRowVariant.bash,
  'read': ToolRowVariant.read,
  'read_image': ToolRowVariant.read,
  'web_fetch': ToolRowVariant.read,
  'web_search': ToolRowVariant.search,
  'grep': ToolRowVariant.search,
  'glob': ToolRowVariant.search,
  'write': ToolRowVariant.write,
  'edit': ToolRowVariant.edit,
  'run_code': ToolRowVariant.code,
  'cordis_package_inspect': ToolRowVariant.read,
  'cordis_runtime_inspect': ToolRowVariant.read,
  'cordis_run': ToolRowVariant.others,
  'cordis_stop': ToolRowVariant.others,
  'cordis_undefine': ToolRowVariant.others,
};

/// Tool-owned titles that refine a variant (dsh `TOOL_TITLE_KEYS`).
const _toolTitleKeys = {
  'cordis_package_inspect': 'tool.title.inspect',
  'cordis_runtime_inspect': 'tool.title.inspect',
  'cordis_run': 'tool.title.runCordis',
  'cordis_stop': 'tool.title.stopCordis',
  'cordis_undefine': 'tool.title.removeCordis',
  'pwsh': 'tool.title.pwsh',
  'read_image': 'tool.title.readImage',
  'todo_write': 'todo.rowTitle',
  'ask_user_question': 'ask.rowTitle',
  'create_goal': 'tool.title.createGoal',
  'get_goal': 'tool.title.getGoal',
  'update_goal': 'tool.title.updateGoal',
  'schedule_create': 'tool.title.createSchedule',
  'schedule_list': 'tool.title.listSchedules',
  'schedule_delete': 'tool.title.deleteSchedule',
  'schedule_update': 'tool.title.updateSchedule',
  'cordis_inspect_list': 'tool.title.inspectProviders',
  'cordis_inspect_query': 'tool.title.queryRuntime',
  'cordis_inspect_self': 'tool.title.inspectPlugins',
  'workflow': 'tool.title.workflow',
  'ralph': 'tool.title.ralph',
  'session_event_read': 'tool.title.readEvent',
  'session_event_search': 'tool.title.searchEvents',
  'session_event_trace': 'tool.title.traceEvent',
  'session_search': 'tool.title.searchSessions',
  'session_trace': 'tool.title.traceSession',
  'list_subagent_models': 'tool.title.listModels',
  'subagent': 'tool.title.subagent',
  'list_agents': 'tool.title.listAgents',
  'send_message': 'tool.title.sendMessage',
  'interrupt_agent': 'tool.title.interruptAgent',
  'job_list': 'tool.title.listJobs',
  'job_output': 'tool.title.readJob',
  'job_kill': 'tool.title.killJob',
  'terminal_open': 'tool.title.openTerminal',
  'terminal_read': 'tool.title.readTerminal',
  'terminal_list': 'tool.title.listTerminals',
  'terminal_signal': 'tool.title.signalTerminal',
  'terminal_close': 'tool.title.closeTerminal',
  'lsp': 'tool.title.lsp',
  'spawn_teammate': 'tool.title.spawnTeammate',
  'team_task_create': 'tool.title.createTeamTask',
  'team_task_get': 'tool.title.getTeamTask',
  'team_task_update': 'tool.title.updateTeamTask',
  'team_task_list': 'tool.title.listTeamTasks',
  'wait_agent': 'tool.title.waitAgent',
};

ToolRowVariant classifyTool(String toolName) =>
    _toolVariants[toolName] ?? ToolRowVariant.others;

String toolTitleKey(String toolName) =>
    _toolTitleKeys[toolName] ?? _variantTitleKeys[classifyTool(toolName)]!;

/// Everything a tool row needs, derived once from a call (dsh `ToolRowModel`).
class ToolRowModel {
  const ToolRowModel({
    required this.variant,
    required this.titleKey,
    required this.summary,
    required this.filePath,
    required this.bodyRaw,
    required this.output,
    required this.errorSummary,
    required this.autoReviewDenial,
    required this.state,
  });

  final ToolRowVariant variant;
  final String titleKey;
  final String summary;
  final String? filePath;
  final String? bodyRaw;
  final String? output;
  final String? errorSummary;

  /// Auto-review denial: the persisted reviewer reason (possibly null) when
  /// the call was denied, otherwise absent.
  final ({String? reason})? autoReviewDenial;
  final ToolRowState state;
}

/// Flatten a settled result to display text: text blocks verbatim, other
/// blocks as pretty JSON; an empty failed result falls back to `name: code`.
String resultText(ToolResult node) {
  final parts = <String>[];
  for (final block in node.content) {
    if (block is Map && block['type'] == 'text') {
      parts.add('${block['text']}');
    } else {
      parts.add(const JsonEncoder.withIndent('  ').convert(block));
    }
  }
  if (parts.isEmpty && node.error != null) {
    parts.add('${node.error!['name']}: ${node.error!['code']}');
  }
  return parts.join('\n');
}

Object? _parse(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

String? _pickString(Map<String, Object?> args, List<String> keys) {
  for (final key in keys) {
    final v = args[key];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

const _summaryKeys = {
  ToolRowVariant.bash: ['description', 'command'],
  ToolRowVariant.read: ['path', 'file_path', 'url'],
  ToolRowVariant.search: ['query', 'pattern', 'url'],
  ToolRowVariant.write: ['path', 'file_path'],
  ToolRowVariant.edit: ['path', 'file_path'],
  ToolRowVariant.code: ['description'],
  ToolRowVariant.others: <String>[],
};

String _deriveSummary(ToolRowVariant variant, String argsRaw) {
  final parsed = _parse(argsRaw);
  if (parsed is! Map<String, Object?>) return firstLine(argsRaw);
  if (variant == ToolRowVariant.search && parsed['queries'] is List) {
    final queries = (parsed['queries'] as List)
        .whereType<String>()
        .where((q) => q.isNotEmpty)
        .toList();
    if (queries.isNotEmpty) return queries.map(firstLine).join(', ');
  }
  final picked = _pickString(parsed, _summaryKeys[variant]!);
  if (picked != null) return firstLine(picked);
  for (final v in parsed.values) {
    if (v is String && v.isNotEmpty) return firstLine(v);
  }
  return firstLine(argsRaw);
}

const _filePathKeys = ['path', 'file_path'];
const _filePathVariants = {
  ToolRowVariant.read,
  ToolRowVariant.write,
  ToolRowVariant.edit,
};

({String summary, String? filePath}) _argumentSummary(
  ToolRowVariant variant,
  PartialArguments args,
  String? cwd,
  String? home,
) {
  if (_filePathVariants.contains(variant)) {
    final path = args.complete('file_path') ? args.text('file_path') : null;
    final filePath =
        path != null && path.isNotEmpty && args.complete('file_path')
        ? firstLine(path)
        : null;
    return (
      summary: filePath == null
          ? ''
          : abbreviateHomePath(relativizeToCwd(filePath, cwd), home),
      filePath: filePath,
    );
  }
  final description = args.text('description');
  return (
    summary: description == null ? '' : firstLine(description),
    filePath: null,
  );
}

String? _deriveFilePath(ToolRowVariant variant, String argsRaw) {
  if (!_filePathVariants.contains(variant)) return null;
  final parsed = _parse(argsRaw);
  if (parsed is! Map<String, Object?>) return null;
  final picked = _pickString(parsed, _filePathKeys);
  return picked == null ? null : firstLine(picked);
}

/// Format an argument payload when its generic input body becomes visible.
String? formatToolBody(ToolRowVariant variant, String argsRaw) {
  if (argsRaw.isEmpty) return null;
  final parsed = _parse(argsRaw);
  if (parsed == null && argsRaw.trim() != 'null') return argsRaw;
  if (variant == ToolRowVariant.code && parsed is Map<String, Object?>) {
    final code = parsed['code'];
    if (code is String && code.isNotEmpty) return code;
  }
  return const JsonEncoder.withIndent('  ').convert(parsed);
}

/// Derive the row model from a call (dsh `toolRowModel`).
ToolRowModel toolRowModel(
  String toolName,
  ToolCall call, {
  String? cwd,
  String? home,
}) {
  final variant = classifyTool(toolName);
  final titleKey = toolTitleKey(toolName);
  final String? argsRaw = switch (call) {
    ToolResult(:final callArgsRaw) => callArgsRaw ?? '',
    StartedToolCall(:final argsRaw) => argsRaw,
    PreparingToolCall() => null,
  };
  final primary = _argumentSummary(variant, call.args, cwd, home);
  final argumentPath =
      primary.filePath ??
      (argsRaw == null ? null : _deriveFilePath(variant, argsRaw));
  final recorded = call is ToolResult
      ? recordedAbsolutePath(call.meta, 'path')
      : null;
  final canUseArgumentPath =
      argumentPath != null &&
      (isAbsoluteWorkspacePath(argumentPath) ||
          (call is ToolResult && !call.isError && call.parentCallId == null));
  final filePath = argumentPath == null
      ? null
      : recorded ?? (canUseArgumentPath ? argumentPath : null);
  final state = switch (call) {
    PreparingToolCall() => ToolRowState.preparing,
    StartedToolCall() => ToolRowState.running,
    ToolResult(:final error, :final isError) =>
      error?['code'] == 'interrupted'
          ? ToolRowState.stopped
          : (isError ? ToolRowState.error : ToolRowState.ok),
  };
  final base = primary.summary.isNotEmpty || argsRaw == null
      ? primary.summary
      : argsRaw.isEmpty
      ? call.callId
      : abbreviateHomePath(
          relativizeToCwd(_deriveSummary(variant, argsRaw), cwd),
          home,
        );
  final summary = [
    titleKey == 'tool.title.generic' ? toolName : '',
    base,
  ].where((s) => s.isNotEmpty).join(' · ');
  final output = call is ToolResult
      ? (resultText(call).isEmpty ? null : resultText(call))
      : null;
  final errorSummary = state == ToolRowState.error && output != null
      ? firstLine(output)
      : null;
  ({String? reason})? denial;
  if (call is ToolResult &&
      call.isError &&
      call.error?['name'] == 'AutoReviewDeniedError' &&
      call.error?['code'] == 'AUTO_REVIEW_DENIED') {
    final reason = call.error?['reason'];
    denial = (reason: reason is String ? reason : null);
  }
  return ToolRowModel(
    variant: variant,
    titleKey: titleKey,
    summary: summary,
    filePath: filePath,
    bodyRaw: argsRaw == null || argsRaw.isEmpty ? null : argsRaw,
    output: output,
    errorSummary: errorSummary,
    autoReviewDenial: denial,
    state: state,
  );
}

/// The localized auto-review denial (dsh `localizeAutoReviewDenial`).
({String summary, String output}) localizeAutoReviewDenial(
  ({String? reason}) denial,
  String Function(String key, [Map<String, Object?> params]) t,
) {
  final normalized = denial.reason?.trim().replaceAll(RegExp('[\r\n  ]+'), ' ');
  final reason = normalized == null || normalized.isEmpty
      ? t('tool.autoReviewReasonFallback')
      : normalized;
  return (
    summary: t('tool.autoReviewRejected'),
    output: t('tool.autoReviewNotExecuted', {'reason': reason}),
  );
}
