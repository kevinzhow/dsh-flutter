import 'package:dsh_conversation/dsh_conversation.dart';

import 'raw_call.dart';
import 'workspace_path.dart';

/// Shell call material read from validated arguments (dsh `ShellCall`).
class _ShellCall {
  const _ShellCall({
    required this.command,
    required this.description,
    required this.workdir,
    required this.persistent,
    required this.background,
  });
  final String command;
  final String? description;
  final String? workdir;
  final bool persistent;
  final bool background;
}

_ShellCall? _shellCall(String name, Map<String, Object?> args) {
  if (name != 'bash' && name != 'pwsh') return null;
  final command = args['command'];
  if (command is! String || command.trim().isEmpty) return null;
  final timeout = args['timeoutMs'];
  if (args.containsKey('timeoutMs') &&
      (timeout is! num || !timeout.isFinite || timeout <= 0)) {
    return null;
  }
  final workdir = args['workdir'];
  if (args.containsKey('workdir') && workdir is! String) return null;
  final background = args['run_in_background'];
  if (args.containsKey('run_in_background') && background is! bool) return null;
  final description = args['description'];
  if (!args.containsKey('description')) {
    // The standard schemas require `description`; persistent shells omit it.
    return _ShellCall(
      command: command,
      description: null,
      workdir: null,
      persistent: true,
      background: false,
    );
  }
  if (description is! String || description.trim().isEmpty) return null;
  return _ShellCall(
    command: command,
    description: description,
    workdir: workdir as String?,
    persistent: false,
    background: background == true,
  );
}

class _SendCall {
  const _SendCall(this.text, this.sessionId, this.background);
  final String text;
  final String sessionId;
  final bool background;
}

_SendCall? _terminalSendCall(String name, Map<String, Object?> args) {
  if (name != 'terminal_send') return null;
  final sessionId = args['sessionId'];
  final text = args['text'];
  if (sessionId is! String || sessionId.isEmpty || text is! String) return null;
  final submit = args['submit'];
  if (args.containsKey('submit') && submit is! bool) return null;
  final background = args['run_in_background'];
  if (args.containsKey('run_in_background') && background is! bool) return null;
  return _SendCall(text, sessionId, background == true);
}

/// A background shell launch whose result acknowledges a job, not its exit.
bool isBackgroundShellCall(ToolCall call) {
  final p = parsedCall(call);
  return p != null && _shellCall(p.name, p.args)?.background == true;
}

/// A settled root persistent bash/pwsh call: its result stays generic.
bool isSettledPersistentShellCall(ToolCall call) {
  if (call is! ToolResult || call.parentCallId != null) return false;
  final p = parsedCall(call);
  if (p == null) return false;
  return _shellCall(p.name, p.args)?.persistent == true;
}

/// A settled foreground shell preview whose spill footer can hide the exit
/// marker, so it must stay generic. dsh recognises the notice through its
/// browser-safe `hasSpillNotice`; this is the same check over the notice text.
bool isSpilledShellCall(ToolCall call) {
  if (call is! ToolResult) return false;
  final p = parsedCall(call);
  if (p == null) return false;
  final shell = _shellCall(p.name, p.args);
  if (shell == null || shell.background) return false;
  final output = singleResultText(call);
  return output != null && hasSpillNotice(output);
}

const _open = '(';
const _close = ')';
const _location = ' Full formatted result stored at: ';
const _guidanceSeparator = '. ';
const _separator = '\n\n';

bool _isOmission(String text) {
  final image = RegExp(r' Omitted ([1-9][0-9]*) images\.$').firstMatch(text);
  if (image != null) text = text.substring(0, image.start);
  if (text == '' || text == 'More bytes were omitted.') return true;
  final m = RegExp(r'^Omitted (\d+) bytes\.$').firstMatch(text);
  return m != null && int.tryParse(m.group(1)!) != null;
}

/// Whether a complete spill-policy notice ends [text] (dsh
/// `hasSpillNotice` in `@deepseek-ai/dsh-spill-policy/notice`): the text
/// convention only, not authenticated tool-output origin.
bool hasSpillNotice(String text) {
  if (!text.endsWith(_close)) return false;
  var start = 0;
  while (true) {
    final next = text.indexOf('$_separator$_open', start);
    final candidate = text.substring(
      start,
      next < 0 ? text.length - _close.length : next,
    );
    final location = candidate.indexOf(_location, _open.length);
    if (candidate.startsWith(_open) &&
        location >= 0 &&
        _isOmission(candidate.substring(_open.length, location))) {
      return text.indexOf(
            _guidanceSeparator,
            start + location + _location.length,
          ) >=
          0;
    }
    if (next < 0) return false;
    start = next + _separator.length;
  }
}

/// The data a terminal card draws (dsh `TerminalCardModel`).
class TerminalCardModel {
  const TerminalCardModel({
    required this.command,
    required this.description,
    required this.cwd,
    required this.output,
    required this.exitCode,
    required this.exitCodeMissing,
    required this.signal,
    required this.running,
    required this.background,
    this.sendSessionId,
    this.sendEmptyText = false,
  });

  /// The command as authored (a `terminal_send` text; empty becomes a label).
  final String command;
  final String? description;
  final String? cwd;
  final String? output;
  final int? exitCode;

  /// The result ended without an exit code (`exitCode: null`).
  final bool exitCodeMissing;
  final String? signal;
  final bool running;
  final bool background;

  /// Set for `terminal_send`: the session id the description names.
  final String? sendSessionId;
  final bool sendEmptyText;

  bool get failed =>
      !running &&
      ((exitCode != null && exitCode != 0) ||
          exitCodeMissing ||
          signal != null);
}

String? _resolveTerminalCwd(String? workdir, String? sessionCwd) {
  if (workdir == null || workdir.isEmpty) return sessionCwd;
  if (sessionCwd == null || sessionCwd.isEmpty) {
    return normalizeSegments(workdir);
  }
  return normalizeSegments(resolveWorkspacePath(sessionCwd, workdir));
}

/// Collapse `.` and `..` segments so the prompt names the directory the
/// command ran in (dsh `normalizeSegments`).
String normalizeSegments(String path) {
  if (!RegExp(r'(?:^|[/\\])\.\.?(?:[/\\]|$)').hasMatch(path)) return path;
  final unc = RegExp(r'^[/\\]{2}([^/\\]+)[/\\]+([^/\\]+)').firstMatch(path);
  if (unc != null) {
    final root = '\\\\${unc.group(1)}\\${unc.group(2)}';
    final rest = _collapse(path.substring(unc.end), true, r'\');
    return rest.isEmpty ? root : '$root\\$rest';
  }
  final backslashed = path.contains(r'\') && !path.contains('/');
  final separator = backslashed ? r'\' : '/';
  final rooted = RegExp(r'^[/\\]').hasMatch(path);
  final drive = RegExp(r'^[A-Za-z]:').firstMatch(path)?.group(0) ?? '';
  final body = _collapse(
    path.substring(drive.length),
    rooted || drive.isNotEmpty,
    separator,
  );
  final leading = rooted ? separator : '';
  return drive.isEmpty
      ? '$leading$body'
      : '$drive${rooted ? leading : separator}$body';
}

String _collapse(String body, bool rooted, [String separator = '/']) {
  final kept = <String>[];
  for (final segment in body.split(RegExp(r'[/\\]'))) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (kept.isNotEmpty && kept.last != '..') {
        kept.removeLast();
      } else if (!rooted) {
        kept.add(segment);
      }
      continue;
    }
    kept.add(segment);
  }
  return kept.join(separator);
}

({String output, int? exitCode, bool missing, String? signal}) _parseExitStatus(
  String text,
) {
  final signal = RegExp(r'\n\[killed by signal: ([^\]\n]+)\]$')
      .firstMatch(text);
  if (signal != null) {
    return (
      output: text.substring(0, signal.start),
      exitCode: null,
      missing: false,
      signal: signal.group(1),
    );
  }
  final exit = RegExp(r'\n\[exit code: (-?\d+|null)\]$').firstMatch(text);
  if (exit != null) {
    final value = exit.group(1)!;
    return (
      output: text.substring(0, exit.start),
      exitCode: value == 'null' ? null : int.parse(value),
      missing: value == 'null',
      signal: null,
    );
  }
  return (output: text, exitCode: 0, missing: false, signal: null);
}

/// Derive the terminal card of a supported shell or terminal-send call, or
/// null for the generic path (dsh `terminalCardModel`).
TerminalCardModel? terminalCardModel(ToolCall call, {String? sessionCwd}) {
  final p = parsedCall(call);
  if (p == null) return null;
  final shell = _shellCall(p.name, p.args);
  final send = shell == null ? _terminalSendCall(p.name, p.args) : null;
  if (shell == null && send == null) return null;
  if (send != null && send.background) return null;

  final workdir = shell?.workdir;
  final absoluteRequestCwd = workdir != null && isAbsoluteWorkspacePath(workdir)
      ? normalizeSegments(workdir)
      : null;
  final command = shell?.command ?? send!.text;
  // The terminal_send description is localized by the render site.
  final description = shell?.description;
  String? cwd;
  if (call is ToolResult) {
    cwd =
        recordedAbsolutePath(call.meta, 'cwd') ??
        (shell != null && call.parentCallId == null
            ? _resolveTerminalCwd(workdir, sessionCwd)
            : absoluteRequestCwd);
  } else {
    cwd = absoluteRequestCwd;
  }

  TerminalCardModel build({
    String? output,
    int? exitCode,
    bool missing = false,
    String? signal,
    required bool running,
    bool background = false,
  }) => TerminalCardModel(
    command: command,
    description: description,
    cwd: cwd,
    output: output,
    exitCode: exitCode,
    exitCodeMissing: missing,
    signal: signal,
    running: running,
    background: background,
    sendSessionId: send?.sessionId,
    sendEmptyText: send != null && send.text.isEmpty,
  );

  if (call is! ToolResult) {
    return build(running: true, background: shell?.background ?? false);
  }
  if (call.isError ||
      (shell != null && shell.persistent) ||
      isSpilledShellCall(call)) {
    return null;
  }
  if (shell != null && shell.background) {
    return build(running: false, background: true);
  }
  final output = singleResultText(call);
  if (output == null) return null;
  if (send != null) return build(output: output, running: false);
  final status = _parseExitStatus(output);
  return build(
    output: status.output,
    exitCode: status.exitCode,
    missing: status.missing,
    signal: status.signal,
    running: false,
  );
}

/// The localized exit capsule of a settled foreground command, null when the
/// call is running, background, or succeeded (dsh `terminalExitLabel`).
String? terminalExitLabel(
  TerminalCardModel? model,
  String Function(String key, [Map<String, Object?> params]) t,
) {
  if (model == null || model.background || !model.failed) return null;
  if (model.signal != null) {
    return t('terminal.signal', {'signal': model.signal});
  }
  if (model.exitCode == null) return t('terminal.noExitCode');
  return t('terminal.exitCode', {'code': model.exitCode});
}
