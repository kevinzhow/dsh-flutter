import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show TextField, InputDecoration, OutlineInputBorder;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

String actionText(
  DshI18n i18n,
  String key, [
  Map<String, Object?> params = const {},
]) => i18n.t('workspace', key, params: params);
String actionFailure(Object error) => error is RemoteException
    ? error.message
    : error is StateError
    ? error.message
    : '$error';

/// A settled row operation's notice is independent of the row that just left
/// the list. An undo keeps its exact archived Session identity.
void showWorkspaceNotice(
  BuildContext context,
  String message, {
  String? undoLabel,
  Future<void> Function()? undo,
}) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Notice(
      message: message,
      undoLabel: undoLabel,
      undo: undo,
      close: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _Notice extends StatefulWidget {
  const _Notice({
    required this.message,
    required this.close,
    this.undoLabel,
    this.undo,
  });
  final String message;
  final String? undoLabel;
  final Future<void> Function()? undo;
  final VoidCallback close;
  @override
  State<_Notice> createState() => _NoticeState();
}

class _NoticeState extends State<_Notice> {
  Timer? timer;
  String? failure;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(seconds: 5), widget.close);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    bottom: 24,
    left: 24,
    right: 24,
    child: Center(
      child: DshContainer(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.dsh.color('--dsw-alias-bg-layer-2'),
          borderRadius: BorderRadius.circular(context.dsh.radiusLg),
          boxShadow: context.dsh.boxShadow('--dsw-elevation-panel'),
        ),
        child: Semantics(
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: DshChromeText(failure ?? widget.message)),
              if (widget.undo != null) ...[
                const SizedBox(width: 12),
                DshButton(
                  variant: DshButtonVariant.ghost,
                  onPressed: busy
                      ? null
                      : () async {
                          timer?.cancel();
                          setState(() => busy = true);
                          try {
                            await widget.undo!();
                            widget.close();
                          } on Object catch (e) {
                            if (mounted) {
                              setState(() {
                                busy = false;
                                failure = actionFailure(e);
                              });
                            }
                          }
                        },
                  child: DshChromeText(widget.undoLabel ?? ''),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// The shared rename/delete/archive form. A refused operation keeps its draft
/// and the dialog; in-flight operations cannot be dismissed or duplicated.
class WorkspaceActionForm extends StatefulWidget {
  const WorkspaceActionForm({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.i18n,
    required this.submit,
    this.initial,
    this.fieldLabel,
    this.description,
    this.validate,
    this.detail,
  });
  final String title, confirmLabel;
  final DshI18n i18n;
  final Future<void> Function(String?) submit;
  final String? initial, fieldLabel, description;
  final String? Function(String)? validate;
  final Widget? detail;
  @override
  State<WorkspaceActionForm> createState() => _WorkspaceActionFormState();
}

class _WorkspaceActionFormState extends State<WorkspaceActionForm> {
  late final TextEditingController draft = TextEditingController(
    text: widget.initial ?? '',
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  bool get blocked =>
      busy ||
      (widget.initial != null &&
          (draft.text.trim().isEmpty ||
              widget.validate?.call(draft.text.trim()) != null));
  void close() {
    if (!busy) Navigator.of(context).pop();
  }

  Future<void> confirm() async {
    if (blocked ||
        draft.value.composing.isValid && !draft.value.composing.isCollapsed) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit(widget.initial == null ? null : draft.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = actionFailure(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final validation = widget.initial == null
        ? null
        : widget.validate?.call(draft.text.trim());
    return PopScope(
      canPop: !busy,
      child: Padding(
        key: const ValueKey('workspace-action-form'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DshChromeText(
                    widget.title,
                    style: theme.textStyle('--dsw-font-base-strong-16'),
                  ),
                ),
                DshIconButton(
                  icon: DshIcons.close,
                  semanticLabel: actionText(widget.i18n, 'close'),
                  onPressed: busy ? null : close,
                ),
              ],
            ),
            if (widget.description != null) ...[
              const SizedBox(height: 12),
              DshChromeText(
                widget.description!,
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(color: theme.labelSecondary),
              ),
            ],
            if (widget.initial != null) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('workspace-action-name'),
                controller: draft,
                autofocus: true,
                enabled: !busy,
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(color: theme.labelPrimary),
                decoration: InputDecoration(
                  labelText: widget.fieldLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => error = null),
                onSubmitted: (_) => unawaited(confirm()),
                onTap: () {
                  if (draft.selection.isValid) return;
                  draft.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: draft.text.length,
                  );
                },
              ),
            ],
            if (widget.detail != null) ...[
              const SizedBox(height: 12),
              widget.detail!,
            ],
            if (error ?? validation case final message?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: DshChromeText(
                  message,
                  key: const ValueKey('workspace-action-error'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: theme.color('--dsw-alias-state-error-primary'),
                      ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DshButton(
                  variant: DshButtonVariant.outline,
                  onPressed: busy ? null : close,
                  child: DshChromeText(actionText(widget.i18n, 'cancel')),
                ),
                const SizedBox(width: 8),
                DshButton(
                  key: const ValueKey('workspace-action-confirm'),
                  variant: DshButtonVariant.primary,
                  onPressed: blocked ? null : () => unawaited(confirm()),
                  child: DshChromeText(widget.confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> renameSessionDialog(
  BuildContext context,
  WorkspaceManagement actions,
  DshI18n i18n,
  String id,
  String current,
) => showDshDialog<void>(
  context,
  label: actionText(i18n, 'close'),
  builder: (_) => WorkspaceActionForm(
    title: actionText(i18n, 'rename.session.title'),
    confirmLabel: actionText(i18n, 'rename'),
    fieldLabel: actionText(i18n, 'field.sessionName'),
    initial: current,
    i18n: i18n,
    submit: (title) => actions.renameSession(id, title!),
  ),
);

Future<void> renameWorkspaceDialog(
  BuildContext context,
  WorkspaceManagement actions,
  DshI18n i18n,
  String id,
  String current,
) => showDshDialog<void>(
  context,
  label: actionText(i18n, 'close'),
  builder: (_) => WorkspaceActionForm(
    title: actionText(i18n, 'rename.workspace.title'),
    confirmLabel: actionText(i18n, 'rename'),
    fieldLabel: actionText(i18n, 'field.workspaceName'),
    initial: current,
    i18n: i18n,
    validate: (title) => title == current
        ? ''
        : actions.workspaces.items.any(
            (w) => w.workspaceId != id && w.title == title,
          )
        ? actionText(i18n, 'conflict.named', {'name': title})
        : null,
    submit: (title) => actions.renameWorkspace(id, title!),
  ),
);

Future<void> deleteWorkspaceDialog(
  BuildContext context,
  WorkspaceManagement actions,
  DshI18n i18n,
  String id,
  String title,
) => showDshDialog<void>(
  context,
  label: actionText(i18n, 'close'),
  builder: (_) => WorkspaceActionForm(
    title: actionText(i18n, 'delete.workspace'),
    description: actionText(i18n, 'delete.desc', {'name': title}),
    confirmLabel: actionText(i18n, 'delete.workspace'),
    i18n: i18n,
    submit: (_) => actions.deleteWorkspace(id),
  ),
);

Future<void> archiveSessionAction(
  BuildContext context,
  WorkspaceManagement actions,
  DshI18n i18n,
  String id,
  String title,
) async {
  try {
    await actions.archiveSession(id);
  } on RemoteException catch (e) {
    if (!context.mounted) return;
    final activity = e.details['activity'];
    if (e.code != 'workspace/session-active' || activity is! List) rethrow;
    await showDshDialog<void>(
      context,
      label: actionText(i18n, 'close'),
      builder: (_) => WorkspaceActionForm(
        title: actionText(i18n, 'archive.confirm.title'),
        description: actionText(i18n, 'archive.confirm.desc', {'title': title}),
        confirmLabel: actionText(i18n, 'archive.confirm.action'),
        i18n: i18n,
        detail: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in activity)
              DshChromeText(archiveActivityLine(entry, i18n)),
          ],
        ),
        submit: (_) => actions.archiveSession(id, stopActivity: true),
      ),
    );
    return;
  }
  if (context.mounted) {
    showWorkspaceNotice(
      context,
      actionText(i18n, 'toast.archived'),
      undoLabel: actionText(i18n, 'menu.unarchiveSession'),
      undo: () => actions.unarchiveSession(id),
    );
  }
}

String archiveActivityLine(Object? raw, DshI18n i18n) {
  if (raw is! Map) return '$raw';
  final kind = raw['kind'];
  final items = raw['items'] is List ? raw['items'] as List : const [];
  final count = items.length;
  final names = [
    for (final item in items)
      if (item is Map) item['label'] ?? item['id'] ?? '',
  ].join(actionText(i18n, 'archive.confirm.listSeparator'));
  if (kind == 'turn') return actionText(i18n, 'archive.confirm.turn');
  final family = switch (kind) {
    'subagent' => 'subagents',
    'job' => 'jobs',
    'schedule' => 'schedules',
    _ => 'other',
  };
  return actionText(
    i18n,
    'archive.confirm.$family.${count == 1 ? 'one' : 'other'}',
    {'n': count, 'names': names, 'kind': kind},
  );
}

/// The same verbs occupy the sidebar row and the conversation overflow.
class WorkspaceSessionMenu extends StatelessWidget {
  const WorkspaceSessionMenu({
    super.key,
    required this.actions,
    required this.i18n,
    required this.sessionId,
    required this.title,
    required this.builder,
    this.pinned = false,
    this.archived = false,
  });
  final WorkspaceManagement actions;
  final DshI18n i18n;
  final String sessionId, title;
  final bool pinned, archived;
  final Widget Function(BuildContext, DshMenuController) builder;
  @override
  Widget build(BuildContext context) {
    String t(String key) => actionText(i18n, key);
    return DshMenu(
      align: DshMenuAlign.end,
      dense: true,
      builder: builder,
      entries: [
        if (!archived)
          DshMenuItem(
            'pin',
            t(pinned ? 'menu.unpinSession' : 'menu.pinSession'),
            icon: DshShellIcons.pinFill,
          ),
        DshMenuItem('rename', t('rename'), icon: DshShellIcons.editOutline),
        DshMenuItem('fork', t('menu.fork'), icon: DshIcons.branch),
        DshMenuItem(
          'archive',
          t(archived ? 'menu.unarchiveSession' : 'menu.archiveSession'),
          icon: DshShellIcons.archive,
        ),
        const DshMenuSeparator('copy-separator'),
        DshMenuItem(
          'copy',
          t('menu.sessionId'),
          icon: DshShellIcons.copyOutline,
        ),
      ],
      onSelect: (id) => unawaited(() async {
        try {
          switch (id) {
            case 'pin':
              if (pinned) {
                await actions.unpinSession(sessionId);
              } else {
                await actions.pinSession(sessionId);
              }
            case 'rename':
              if (context.mounted) {
                await renameSessionDialog(
                  context,
                  actions,
                  i18n,
                  sessionId,
                  title,
                );
              }
            case 'fork':
              await actions.forkSession(sessionId);
            case 'archive':
              if (archived) {
                await actions.unarchiveSession(sessionId);
              } else if (context.mounted) {
                await archiveSessionAction(
                  context,
                  actions,
                  i18n,
                  sessionId,
                  title,
                );
              }
            case 'copy':
              await Clipboard.setData(ClipboardData(text: sessionId));
              if (context.mounted) {
                showWorkspaceNotice(context, t('toast.sessionIdCopied'));
              }
          }
        } on Object catch (e) {
          if (context.mounted) showWorkspaceNotice(context, actionFailure(e));
        }
      }()),
    );
  }
}
