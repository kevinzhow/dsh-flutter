import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/widgets.dart';

import 'dsh_ansi.dart';
import 'dsh_copy_feedback.dart';
import 'dsh_head_tail_cap.dart';
import 'dsh_pill.dart';
import 'dsh_state_dot.dart';
import 'dsh_text_scale.dart';
import 'theme_access.dart';

/// Output lines shown before the height cap collapses the middle.
const int defaultTerminalMaxLines = 16;

/// Display copy of the terminal surface, supplied by the owning feature (this
/// package knows no catalog), like dsh's `TerminalBlockLabels`.
class DshTerminalLabels {
  const DshTerminalLabels({
    required this.commandLine,
    required this.signal,
    required this.exitCode,
    required this.noExitCode,
    required this.running,
    required this.failed,
    required this.done,
    required this.copy,
    required this.copied,
    required this.noOutput,
    required this.collapse,
    required this.expand,
  });

  final String Function(int line) commandLine;
  final String Function(String signal) signal;
  final String Function(int code) exitCode;
  final String noExitCode;
  final String running;
  final String failed;
  final String done;
  final String copy;
  final String copied;
  final String noOutput;
  final String collapse;
  final String Function(int hidden) expand;
}

/// Prompt label of a working directory: `~` for home itself, else the last
/// path segment (dsh `promptLabel`).
String terminalPromptLabel(String cwd, String? home) {
  final trimmed = cwd.replaceAll(RegExp(r'[/\\]+$'), '');
  if (home != null && trimmed == home.replaceAll(RegExp(r'[/\\]+$'), '')) {
    return '~';
  }
  final segment = trimmed.split(RegExp(r'[/\\]')).last;
  return segment.isEmpty ? cwd : segment;
}

/// Status pill text of a settled command, null when it settled cleanly.
String? terminalStatusText(
  int? exitCode,
  bool exitCodeKnown,
  String? signal,
  DshTerminalLabels labels,
) {
  if (signal != null) return labels.signal(signal);
  if (exitCodeKnown && exitCode == null) return labels.noExitCode;
  if (exitCode != null && exitCode != 0) return labels.exitCode(exitCode);
  return null;
}

/// A shell command as a terminal surface (dsh `TerminalBlock`): a prompt
/// banner with one row per command line, a run-state dot in the gutter, an
/// exit-status capsule and a copy action, then the output.
class DshTerminalBlock extends StatefulWidget {
  const DshTerminalBlock({
    super.key,
    required this.command,
    required this.labels,
    this.cwd,
    this.home,
    this.output,
    this.exitCode,
    this.exitCodeMissing = false,
    this.signal,
    this.running = false,
    this.background = false,
    this.maxLines = 1 << 30,
    this.copyText,
    this.runStateDot = true,
    this.outputMaxHeight = 224,
  });

  final String command;
  final String? cwd;
  final String? home;
  final String? output;

  /// Settled exit code; non-zero shows the status pill.
  final int? exitCode;

  /// Settled without any exit code (`exitCode: null` in dsh): the no-exit-code pill.
  final bool exitCodeMissing;
  final String? signal;
  final bool running;
  final bool background;

  /// Output lines before the middle collapses; the chat row passes none.
  final int maxLines;
  final String? copyText;
  final bool runStateDot;

  /// Vertical scroll cap of the output (the chat row's 224px).
  final double outputMaxHeight;
  final DshTerminalLabels labels;

  @override
  State<DshTerminalBlock> createState() => _DshTerminalBlockState();
}

class _DshTerminalBlockState extends State<DshTerminalBlock>
    with DshCopyFeedback {
  bool _expanded = false;

  List<AnsiLine> _lines() {
    final parsed = parseAnsiLines(widget.output ?? '');
    final last = parsed.last;
    final terminated =
        parsed.length > 1 && last.every((span) => span.text.isEmpty);
    return terminated ? parsed.sublist(0, parsed.length - 1) : parsed;
  }

  TextSpan _span(AnsiSpan span, DshThemeData theme) {
    if (span.plain) return TextSpan(text: span.text);
    Color? color;
    final fg = span.fg;
    if (fg != null) {
      final token = fg.rgb != null && span.bg == null
          ? ansiTokenFor(fg.rgb!)
          : null;
      color = token != null
          ? theme.color(token)
          : (fg.rgb != null ? dshRgb(fg.rgb!) : null);
    }
    final bg = span.bg?.rgb;
    return TextSpan(
      text: span.text,
      style: TextStyle(
        color: span.hidden ? theme.bgBase.withValues(alpha: 0) : color,
        backgroundColor: bg == null ? null : dshRgb(bg),
        fontWeight: span.bold ? FontWeight.w700 : null,
        fontStyle: span.italic ? FontStyle.italic : null,
        decoration: TextDecoration.combine([
          if (span.underline) TextDecoration.underline,
          if (span.strike) TextDecoration.lineThrough,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final labels = w.labels;
    final theme = context.dsh;
    final lines = _lines();
    final empty = lines.every(
      (line) => line.every((span) => span.text.trim().isEmpty),
    );
    final status = w.background
        ? null
        : terminalStatusText(w.exitCode, w.exitCodeMissing, w.signal, labels);
    final (state, stateLabel) = w.running
        ? (DshStateDotState.ongoing, labels.running)
        : status != null
        ? (DshStateDotState.error, labels.failed)
        : (DshStateDotState.done, labels.done);
    final showState = w.runStateDot && (!w.background || w.running);
    final body = !w.background && (!w.running || !empty);

    final base = theme.textStyle('--dsw-font-markdown-code-block-small');
    final code = base.copyWith(height: 16 / base.fontSize!);
    final promptStyle = code.copyWith(height: 18 / base.fontSize!);
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final primary = theme.labelPrimary;
    final cmd = w.command.endsWith('\n')
        ? w.command.substring(0, w.command.length - 1)
        : w.command;
    final commandLines = cmd.split('\n');

    Widget promptLine(int index, String line) {
      final label = index > 0 || w.cwd == null
          ? r'$'
          : terminalPromptLabel(w.cwd!, w.home);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (index == 0 && showState)
            Positioned(
              left: -22,
              top: 9,
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: Semantics(label: stateLabel, child: DshStateDot(state)),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: promptStyle.copyWith(color: tertiary)),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  label: labels.commandLine(index + 1),
                  child: Text(
                    line,
                    style: promptStyle.copyWith(color: primary),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(30, 9, 14, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < commandLines.length; i++)
                  promptLine(i, commandLines[i]),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: 12),
            DshPill(
              height: 18,
              color: theme.color('--dsw-alias-state-error-primary'),
              child: Text(status, key: const ValueKey('terminal-status')),
            ),
          ],
          if (w.copyText != null ||
              (!w.background && !w.running && !empty)) ...[
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => copyText(w.copyText ?? (w.output ?? '')),
              child: Text(
                copied ? labels.copied : labels.copy,
                key: const ValueKey('terminal-copy'),
                style: theme
                    .textStyle('--dsw-font-xs-13')
                    .copyWith(color: theme.labelSecondary, height: 18 / 13),
              ),
            ),
          ],
        ],
      ),
    );

    Widget lineText(AnsiLine line) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 18),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text.rich(
          TextSpan(
            style: code.copyWith(color: primary),
            children: [for (final s in line) _span(s, theme)],
          ),
          softWrap: false,
        ),
      ),
    );

    final cap = headTailCap(lines.length, w.maxLines, _expanded);
    final head = cap.capped ? lines.sublist(0, cap.headLines) : lines;
    final tail = cap.capped
        ? lines.sublist(lines.length - cap.tailLines)
        : const <AnsiLine>[];
    final output = Padding(
      padding: const EdgeInsets.fromLTRB(30, 12, 14, 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: w.outputMaxHeight - 24),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in head) lineText(line),
                if (cap.hidden > 0)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? labels.collapse : labels.expand(cap.hidden),
                      key: const ValueKey('terminal-expand'),
                      style: code.copyWith(color: tertiary),
                    ),
                  ),
                for (final line in tail) lineText(line),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      key: const ValueKey('terminal-block'),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-markdown-code-block'),
        borderRadius: BorderRadius.circular(theme.radiusLg),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l1'),
          width: dshHairline,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.radiusLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                border: body
                    ? Border(
                        bottom: BorderSide(
                          color: theme.color('--dsw-alias-border-l2'),
                          width: dshHairline,
                        ),
                      )
                    : null,
              ),
              child: header,
            ),
            if (body)
              empty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(30, 12, 14, 12),
                      child: Text(
                        labels.noOutput,
                        style: code.copyWith(color: tertiary),
                      ),
                    )
                  : output,
          ],
        ),
      ),
    );
  }
}
