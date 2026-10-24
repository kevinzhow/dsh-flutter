import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'model/ask_model.dart';
import 'model/details_model.dart';
import 'model/diff_model.dart';
import 'model/image_card_model.dart';
import 'model/raw_call.dart';
import 'model/read_search_web_model.dart';
import 'model/row_model.dart';
import 'model/terminal_model.dart';
import 'widgets/ask_card.dart';
import 'widgets/tool_details.dart';
import 'widgets/tool_row.dart';

/// What every tool view reads: the active locale and the host's open actions.
class ToolEnv {
  const ToolEnv({
    required this.i18n,
    this.actions = const ToolHostActions(),
    this.expandedByDefault,
    this.slots,
  });

  final DshI18n i18n;
  final ToolHostActions actions;

  /// Renders the image gallery of a `read_image` result through the
  /// `tool.call.images` slot; without it the card shows the text lines only.
  final SlotRegistry? slots;

  /// Whether a call's row starts expanded: the seat of dsh's chat-owned
  /// `useDisclosure` (open state that survives rebuilds of the row). Absent:
  /// every row starts collapsed.
  final bool Function(String callId)? expandedByDefault;

  Tr get t =>
      (key, [params = const {}]) => i18n.t('conversation', key, params: params);
}

/// Everything one view needs about its call.
class ToolContext {
  ToolContext(this.owner, this.env)
    : call = owner.call,
      cwd = owner.session.cwd,
      home = owner.session.hostHome.isEmpty ? null : owner.session.hostHome;

  final ToolViewOwner owner;
  final ToolEnv env;
  final ToolCall call;
  final String? cwd;
  final String? home;
  Tr get t => env.t;
  bool get expanded => env.expandedByDefault?.call(call.callId) ?? false;
  String get name => owner.call.name;
}

/// Leading glyph of a generic row per variant (dsh `VARIANT_ICONS`).
DshIconData variantIcon(ToolRowVariant variant) => switch (variant) {
  ToolRowVariant.search => DshIcons.search,
  ToolRowVariant.read => DshIcons.browse,
  ToolRowVariant.bash => DshIcons.api,
  ToolRowVariant.write || ToolRowVariant.edit => DshIcons.edit,
  ToolRowVariant.code => DshIcons.code,
  ToolRowVariant.others => DshIcons.sparkle,
};

DshTerminalLabels terminalLabels(Tr t) => DshTerminalLabels(
  commandLine: (line) => t('terminal.commandLine', {'n': line}),
  signal: (signal) => t('terminal.signal', {'signal': signal}),
  exitCode: (code) => t('terminal.exitCode', {'code': code}),
  noExitCode: t('terminal.noExitCode'),
  running: t('terminal.running'),
  failed: t('terminal.failed'),
  done: t('terminal.done'),
  copy: t('copy'),
  copied: t('copied'),
  noOutput: t('terminal.noOutput'),
  collapse: t('collapse'),
  expand: (hidden) => t('terminal.expandRest', {'n': hidden}),
);

DshCodeToolbarLabels toolbarLabels(Tr t) => DshCodeToolbarLabels(
  codeLabel: t('codeBlock.title'),
  wrapLabel: t('codeBlock.wrap'),
  unwrapLabel: t('codeBlock.unwrap'),
  copy: t('copy'),
  copied: t('copied'),
);

/// Terminal-send commands show their text, or a label for a bare submit.
({String command, String? description}) terminalCopy(
  TerminalCardModel m,
  Tr t,
) {
  if (m.sendSessionId == null) {
    return (command: m.command, description: m.description);
  }
  return (
    command: m.sendEmptyText ? t('terminal.sendInput') : m.command,
    description: t('terminal.session', {'sessionId': m.sendSessionId}),
  );
}

/// The generic view and fallback of dsh's `tool.call.toolview` (dsh
/// `GenericToolCard`): variant icon, title, summary and, where the call has
/// one, the structured terminal/read/diff/search/web card.
Widget genericView(ToolContext c) {
  final model = toolRowModel(c.name, c.call, cwd: c.cwd, home: c.home);
  final autoReview = model.autoReviewDenial == null
      ? null
      : localizeAutoReviewDenial(model.autoReviewDenial!, c.t);
  final terminal = terminalCardModel(c.call, sessionCwd: c.cwd);
  final read = readCardModel(c.call, cwd: c.cwd, home: c.home);
  final diff = diffCardModel(c.call);
  final search = searchCardModel(c.call);
  final web = webCardModel(c.call);
  final state =
      model.state == ToolRowState.ok && terminal != null && terminal.failed
      ? ToolRowState.error
      : model.state;
  final singleFile = model.filePath != null;
  final hasCard =
      terminal != null ||
      read != null ||
      diff != null ||
      search != null ||
      web != null;
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: c.t,
    toolName: c.name,
    variant: model.variant,
    icon: variantIcon(model.variant),
    title: c.t(model.titleKey),
    summary: model.summary,
    bodyRaw: singleFile || autoReview != null || hasCard ? null : model.bodyRaw,
    output: autoReview?.output ?? (hasCard ? null : model.output),
    errorSummary: autoReview?.summary ?? model.errorSummary,
    state: state,
    filePath: model.filePath,
    onOpenFile: singleFile ? c.env.actions.openFile : null,
    exitLabel: terminalExitLabel(terminal, c.t),
    summaryOverride: terminal == null
        ? null
        : terminalCopy(terminal, c.t).description,
    diffStat: diff == null ? null : diffTotals(diff),
    card: _cardFor(c, terminal, read, diff, search, web),
  );
}

WidgetBuilder? _cardFor(
  ToolContext c,
  TerminalCardModel? terminal,
  ReadCardModel? read,
  List<DshDiffHunk>? diff,
  SearchCardModel? search,
  WebCardModel? web,
) {
  final t = c.t;
  if (terminal != null) {
    final copy = terminalCopy(terminal, t);
    return (_) => DshTerminalBlock(
      command: copy.command,
      cwd: terminal.cwd,
      home: c.home,
      output: terminal.output,
      exitCode: terminal.exitCode,
      exitCodeMissing: terminal.exitCodeMissing,
      signal: terminal.signal,
      running: terminal.running,
      background: terminal.background,
      labels: terminalLabels(t),
    );
  }
  if (diff != null) {
    return (_) => DshDiffBlock(
      diffs: diff,
      toolbar: toolbarLabels(t),
      fold: DshFoldLabels(
        collapse: t('collapse'),
        expand: (n) => t('diff.expandRest', {'count': n}),
      ),
      maxLines: chatDiffMaxLines,
    );
  }
  if (read != null) {
    return (_) => DshReadBlock(
      label: read.label,
      lines: read.lines,
      totalLines: read.totalLines,
      lang: read.lang,
      maxLines: chatReadMaxLines,
      labels: DshReadLabels(
        toolbar: toolbarLabels(t),
        fold: DshFoldLabels(
          collapse: t('collapse'),
          expand: (n) => t('read.expandRest', {'count': n}),
        ),
        window: (shown, total) =>
            t('read.window', {'shown': shown, 'total': total}),
      ),
    );
  }
  if (search != null) {
    final labels = DshSearchLabels(
      pathsSummary: (shown, total, truncated) => t(
        truncated ? 'search.paths.truncated' : 'search.paths',
        {'shown': shown, 'total': total},
      ),
      matchesSummary: (shown, total, files, truncated) => t(
        truncated ? 'search.matches.truncated' : 'search.matches',
        {'shown': shown, 'total': total, 'files': files},
      ),
      copy: t('copy'),
      copied: t('copied'),
      noResults: t('search.noResults'),
      collapse: t('collapse'),
      expand: (n) => t('search.expandRest', {'count': n}),
    );
    return (context) {
      final block = search.files != null
          ? DshSearchBlock.matches(
              files: search.files!,
              truncated: search.truncated,
              total: search.total,
              labels: labels,
              maxLines: chatSearchMaxLines,
            )
          : DshSearchBlock.paths(
              paths: search.paths!,
              truncated: search.truncated,
              total: search.total,
              labels: labels,
              maxLines: chatSearchMaxLines,
            );
      if (search.recovery == null) return block;
      final theme = context.dsh;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block,
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DshChromeText(
              search.recovery!,
              style: theme
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
            ),
          ),
        ],
      );
    };
  }
  if (web != null) {
    final labels = DshWebLabels(
      noResults: t('web.noResults'),
      sourcesTruncated: t('web.sourcesTruncated'),
      http: t('web.http'),
      contentTruncated: t('web.contentTruncated'),
    );
    final open = c.env.actions.openUrl ?? (_) {};
    return (_) => web.url != null
        ? DshWebBlock.fetch(
            url: web.url!,
            statusCode: web.statusCode!,
            truncated: web.truncated,
            labels: labels,
            onOpenUrl: open,
          )
        : DshWebBlock.search(
            answer: web.answer,
            sources: web.sources!,
            truncated: web.truncated,
            labels: labels,
            onOpenUrl: open,
          );
  }
  return null;
}

/// `bash` / `pwsh`: the terminal row (dsh `BashRow`). Persistent shells,
/// spill previews, background launches and errors keep the input/output card.
Widget bashView(ToolContext c) => genericView(c);

/// `edit` / `write`: path link, size while content arrives, diff totals, and
/// the diff card once the call has input (dsh `FileMutationRow`).
Widget mutationView(ToolContext c) {
  final model = toolRowModel(c.name, c.call, cwd: c.cwd, home: c.home);
  final diff = diffCardModel(c.call);
  final kilobytes = _contentKilobytes(c.call.args);
  final size = kilobytes == null
      ? null
      : c.t('tool.preparing.content', {'kilobytes': kilobytes});
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: c.t,
    toolName: c.name,
    variant: model.variant,
    icon: DshIcons.edit,
    title: c.t(model.titleKey),
    summary: model.summary,
    summarySuffix: size != null && model.summary.isNotEmpty ? size : null,
    output: diff == null ? model.output : null,
    errorSummary: model.errorSummary,
    state: model.state,
    filePath: model.filePath,
    onOpenFile: c.env.actions.openFile,
    diffStat: diff == null ? null : diffTotals(diff),
    card: _cardFor(c, null, null, diff, null, null),
  );
}

const _contentFields = ['content', 'old_string', 'new_string'];

/// Kilobytes of decoded input at every stage (dsh `contentKilobytes`): null
/// before any content field arrives.
int? _contentKilobytes(PartialArguments args) {
  int length(String key) => args.text(key)?.length ?? 0;
  String? open;
  for (final key in _contentFields) {
    if (args.has(key) && !args.complete(key)) {
      open = key;
      break;
    }
  }
  var completed = 0;
  for (final key in _contentFields) {
    if (key != open && args.complete(key)) completed += length(key);
  }
  if (open == null) {
    return _contentFields.any(args.has) ? (completed / 1024).ceil() : null;
  }
  return ((completed + length(open)) / 1024).ceil();
}

/// `read`: an openable path, expanding to the line-numbered card.
Widget readView(ToolContext c) {
  final model = toolRowModel(c.name, c.call, cwd: c.cwd, home: c.home);
  final read = readCardModel(c.call, cwd: c.cwd, home: c.home);
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: c.t,
    toolName: c.name,
    variant: model.variant,
    icon: DshIcons.browse,
    title: c.t(model.titleKey),
    summary: model.summary,
    output: read == null ? model.output : null,
    errorSummary: model.errorSummary,
    state: model.state,
    filePath: model.filePath,
    filePathLine: readCallLine(c.call),
    onOpenFile: c.env.actions.openFile,
    card: _cardFor(c, null, read, null, null, null),
  );
}

/// `grep` / `glob`: grouped matches or a path list.
Widget searchView(ToolContext c) {
  final model = toolRowModel(c.name, c.call);
  final search = searchCardModel(c.call);
  final titleKey = c.name == 'grep'
      ? 'tool.title.grep'
      : c.name == 'glob'
      ? 'tool.title.glob'
      : model.titleKey;
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: c.t,
    toolName: c.name,
    variant: model.variant,
    icon: DshIcons.search,
    title: c.t(titleKey),
    summary: model.summary,
    output: search == null ? model.output : null,
    errorSummary: model.errorSummary,
    state: model.state,
    card: _cardFor(c, null, null, null, search, null),
  );
}

/// `web_search` / `web_fetch`: sources or a fetch summary; the collapsed
/// `web_fetch` URL links out.
Widget webView(ToolContext c) {
  final model = toolRowModel(c.name, c.call);
  final web = webCardModel(c.call);
  final titleKey = c.name == 'web_search'
      ? 'tool.title.webSearch'
      : c.name == 'web_fetch'
      ? 'tool.title.webFetch'
      : model.titleKey;
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: c.t,
    toolName: c.name,
    variant: model.variant,
    icon: c.name == 'web_fetch' ? DshIcons.browse : DshIcons.globe,
    title: c.t(titleKey),
    summary: model.summary,
    output: web == null ? model.output : null,
    errorSummary: model.errorSummary,
    state: model.state,
    href: webFetchHref(c.call),
    onOpenUrl: c.env.actions.openUrl,
    card: _cardFor(c, null, null, null, null, web),
  );
}

/// `read_image`: path row; the image gallery needs the attachment slot, so the
/// result text stays visible (dsh falls back the same way without it).
Widget readImageView(ToolContext c) {
  final model = toolRowModel(c.name, c.call, cwd: c.cwd, home: c.home);
  final image = imageCardModel(c.call);
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: c.t,
    toolName: c.name,
    variant: model.variant,
    icon: DshIcons.browse,
    title: c.t(model.titleKey),
    summary: model.summary,
    output: image == null ? model.output : null,
    errorSummary: model.errorSummary,
    state: model.state,
    filePath: model.filePath,
    onOpenFile: c.env.actions.openFile,
    card: image == null ? null : (context) => _ImageCard(c: c, model: image),
  );
}

/// The `read_image` card (dsh `ToolRow` image body): the gallery of the
/// returned images, then the full path and each image's size in the small code
/// font, then any extra text.
class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.c, required this.model});

  final ToolContext c;
  final ImageCardModel model;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final slots = c.env.slots;
    final gallery = slots?.renderSingle(
      DshSlots.toolCallImages.typed<ImageGalleryOwner, Widget>(),
      ImageGalleryOwner(
        session: c.owner.session,
        images: [for (final ref in model.images) DurableGalleryImage(ref)],
      ),
    );
    final small = theme
        .textStyle('--dsw-font-markdown-code-block-small')
        .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
    final t = c.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?gallery,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DshChromeText(
                model.path,
                key: const ValueKey('image-path'),
                style: small,
              ),
              for (var i = 0; i < model.images.length; i++)
                DshChromeText(
                  model.originalSizes[i] == null
                      ? t('row.imageSize', {
                          'width': model.images[i].width,
                          'height': model.images[i].height,
                          'bytes': model.images[i].bytes,
                        })
                      : t('row.imageSizeDownscaled', {
                          'width': model.images[i].width,
                          'height': model.images[i].height,
                          'originalWidth': model.originalSizes[i]!.width,
                          'originalHeight': model.originalSizes[i]!.height,
                          'bytes': model.images[i].bytes,
                        }),
                  style: small,
                ),
            ],
          ),
        ),
        if (model.extraText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DshChromeText(
              model.extraText!,
              style: theme
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
            ),
          ),
      ],
    );
  }
}

/// `todo_write`: completion summary with the active item, the change summary
/// against the previous list, and the list diff (dsh `TodoRow`).
Widget todoView(ToolContext c, TodoHistory history, bool hasMore) {
  final t = c.t;
  final model = toolRowModel(c.name, c.call);
  final baseline = history.get(c.call.callId);
  final diff = todoDiffModel(c.call, baseline, hasMore, t);
  final summary = _todoSummary(model.bodyRaw, t);
  final parts = [
    ?diff?.summary,
    if (summary != null && summary.extra > 0) '+${summary.extra}',
  ];
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: t,
    toolName: c.name,
    variant: model.variant,
    icon: DshIcons.checklist,
    title: t(model.titleKey),
    summary: summary?.text ?? model.summary,
    summarySuffix: parts.isEmpty ? null : parts.join(' · '),
    bodyRaw: diff == null ? model.bodyRaw : null,
    output: diff == null ? model.output : null,
    errorSummary: model.errorSummary,
    state: model.state,
    card: diff == null ? null : (_) => ToolDetailsView(model: diff.details),
  );
}

({String text, int extra})? _todoSummary(String? argsRaw, Tr t) {
  if (argsRaw == null) return null;
  final parsed = parsedFromRaw(argsRaw);
  if (parsed == null) return null;
  final todos = parsed['todos'];
  if (todos is! List || !todos.every((e) => e is Map)) return null;
  final items = todos.cast<Map<String, Object?>>();
  final done = items.where((e) => e['status'] == 'completed').length;
  final active = items
      .where((e) => e['status'] == 'in_progress')
      .map((e) => '${e['content'] ?? ''}'.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final head = t('todo.completed', {'done': done, 'total': items.length});
  return (
    text: active.isEmpty ? head : '$head · ${active.first}',
    extra: active.length > 1 ? active.length - 1 : 0,
  );
}

/// `ask_user_question`: pending, answered, cancelled or interrupted, with the
/// answer transcript.
Widget askView(
  ToolContext c, {
  required bool answerable,
  required List<AskAnswer>? settledAnswers,
}) {
  final t = c.t;
  final model = toolRowModel(c.name, c.call);
  final p = presentAsk(
    c.call,
    model,
    t,
    answerable: answerable,
    settledAnswers: settledAnswers,
  );
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: t,
    toolName: c.name,
    variant: model.variant,
    icon: DshIcons.question,
    title: t(model.titleKey),
    summary: p.summary,
    bodyRaw: p.transcript == null ? model.bodyRaw : null,
    output: p.transcript == null ? model.output : null,
    state: p.state,
    card: p.transcript == null ? null : (_) => AskCardView(card: p.transcript!),
  );
}

DshIconData _detailIcon(String name) {
  const teammate = {
    'spawn_teammate',
    'list_agents',
    'send_message',
    'interrupt_agent',
    'wait_agent',
  };
  if (teammate.contains(name)) return DshIcons.users;
  if (name.startsWith('schedule_')) return DshIcons.clock;
  if (name.endsWith('_goal')) return DshIcons.goal;
  if (name.startsWith('cordis_')) return DshIcons.cordisPlugin;
  if (name.startsWith('terminal_')) return DshIcons.code;
  if (name.startsWith('session_') || name == 'lsp') return DshIcons.search;
  if (name.startsWith('job_') || name.startsWith('team_task_')) {
    return DshIcons.checklist;
  }
  if (name == 'workflow' || name == 'ralph') return DshIcons.branch;
  return DshIcons.agentPreset;
}

const _lspTitles = {
  'goToDefinition': 'tool.title.findDefinition',
  'findReferences': 'tool.title.findReferences',
  'goToImplementation': 'tool.title.findImplementation',
  'hover': 'tool.title.hoverSymbol',
};

/// The recorded-result family (goal, schedule, jobs, terminals, subagent
/// control, sessions, workflows, LSP, ...): the tool's own icon and title,
/// structured details for the results this client models (goal, schedule) and
/// the input/output card for the rest.
Widget detailsView(ToolContext c) {
  final t = c.t;
  final model = toolRowModel(c.name, c.call, cwd: c.cwd, home: c.home);
  final details = detailsCardModel(c.call, t);
  // A started subagent names its child in the result: offer its transcript.
  String? childId;
  final call = c.call;
  if (c.name == 'subagent' &&
      call is ToolResult &&
      !call.isError &&
      c.env.actions.openSubagent != null) {
    childId = RegExp(r'started subagent (\S+)')
        .firstMatch(singleResultText(call) ?? '')
        ?.group(1);
  }
  final operation = c.name == 'lsp'
      ? parsedCall(c.call)?.args['operation']
      : null;
  final titleKey = operation is String && _lspTitles.containsKey(operation)
      ? _lspTitles[operation]!
      : model.titleKey;
  return ToolRow(
    key: ValueKey('tool-${c.call.callId}'),
    initiallyExpanded: c.expanded,
    stateId: c.call.callId,
    t: t,
    toolName: c.name,
    variant: model.variant,
    icon: _detailIcon(c.name),
    title: t(titleKey),
    summary:
        details?.summary ??
        (details != null && details.items.isNotEmpty
            ? details.items.first.title
            : null) ??
        details?.empty ??
        model.summary,
    bodyRaw: details == null ? model.bodyRaw : null,
    output: details == null ? model.output : null,
    errorSummary: model.errorSummary,
    state: model.state,
    card: details == null ? null : (_) => ToolDetailsView(model: details),
    panelLabel: childId == null
        ? null
        : c.env.i18n.t('open-in-app', 'path.open'),
    onPanel: childId == null
        ? null
        : () {
            c.env.actions.openSubagent!(c.owner.session, childId!);
            return true;
          },
  );
}

/// Tool names the details family claims (dsh `detailsToolview`).
const detailsTools = [
  'create_goal',
  'get_goal',
  'update_goal',
  'schedule_create',
  'schedule_list',
  'schedule_delete',
  'schedule_update',
  'cordis_inspect_list',
  'cordis_inspect_query',
  'cordis_inspect_self',
  'workflow',
  'ralph',
  'session_event_read',
  'session_event_search',
  'session_event_trace',
  'session_search',
  'session_trace',
  'list_subagent_models',
  'subagent',
  'list_agents',
  'send_message',
  'interrupt_agent',
  'job_list',
  'job_output',
  'job_kill',
  'terminal_open',
  'terminal_read',
  'terminal_list',
  'terminal_signal',
  'terminal_close',
  'lsp',
  'spawn_teammate',
  'team_task_create',
  'team_task_get',
  'team_task_update',
  'team_task_list',
  'wait_agent',
];
