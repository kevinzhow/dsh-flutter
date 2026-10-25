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
    this.danger = false,
    this.pendingLabel,
    this.keepBody = false,
  });
  final String title, confirmLabel;
  final DshI18n i18n;
  final Future<void> Function(String?) submit;
  final String? initial, fieldLabel, description;
  final String? Function(String)? validate;
  final Widget? detail;
  final bool danger;
  final String? pendingLabel;
  final bool keepBody;
  @override
  State<WorkspaceActionForm> createState() => _WorkspaceActionFormState();
}

class _WorkspaceActionFormState extends State<WorkspaceActionForm> {
  late final TextEditingController draft = TextEditingController(
    text: widget.initial ?? '',
  );
  final FocusNode focus = FocusNode();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (focus.hasFocus) {
        draft.selection = TextSelection(
          baseOffset: 0,
          extentOffset: draft.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    focus.dispose();
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
    final message = error ?? validation;
    final body = <Widget>[
      if (widget.initial != null)
        Semantics(
          label: widget.fieldLabel,
          child: SizedBox(
            height: 44,
            child: TextField(
              key: const ValueKey('workspace-action-name'),
              controller: draft,
              focusNode: focus,
              autofocus: true,
              enabled: !busy,
              cursorColor: theme.labelPrimary,
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(
                    color: busy
                        ? theme.color('--dsw-alias-label-dimmed')
                        : theme.labelPrimary,
                    height: 22 / 14,
                  ),
              decoration: InputDecoration(
                hintText: widget.fieldLabel,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.radiusLg),
                  borderSide: BorderSide(
                    color: theme.color('--dsw-alias-border-l4'),
                    width: .5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.radiusLg),
                  borderSide: BorderSide(
                    color: theme.color('--dsw-alias-border-l4'),
                    width: .5,
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.radiusLg),
                  borderSide: BorderSide(
                    color: theme.color('--dsw-alias-border-l4'),
                    width: .5,
                  ),
                ),
              ),
              onChanged: (_) => setState(() => error = null),
              onSubmitted: (_) => unawaited(confirm()),
            ),
          ),
        ),
      if (widget.detail != null) widget.detail!,
      if (busy && widget.pendingLabel != null)
        DshChromeText(
          widget.pendingLabel!,
          style: theme
              .textStyle('--dsw-font-xxs-12')
              .copyWith(color: theme.labelSecondary, height: 18 / 12),
        ),
      if (message != null && message.isNotEmpty) ...[
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: DshChromeText(
            message,
            key: const ValueKey('workspace-action-error'),
            style: theme
                .textStyle('--dsw-font-xxs-12')
                .copyWith(
                  height: 18 / 12,
                  color: theme.color('--dsw-alias-state-error-primary'),
                ),
          ),
        ),
      ],
    ];
    final closeButton = Semantics(
      button: true,
      enabled: !busy,
      label: actionText(widget.i18n, 'close'),
      child: FocusableActionDetector(
        enabled: !busy,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              close();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: const ValueKey('workspace-action-close'),
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : close,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: DshIcon(
                DshIcons.close,
                size: 14,
                color: theme.labelSecondary,
              ),
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !busy,
      child: Padding(
        key: const ValueKey('workspace-action-form'),
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: DshChromeText(
                      widget.title,
                      style: theme
                          .textStyle('--dsw-font-base-strong-16')
                          .copyWith(height: 24 / 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  closeButton,
                ],
              ),
            ),
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DshChromeText(
                  widget.description!,
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelPrimary, height: 22 / 14),
                ),
              ),
            if (body.isNotEmpty || widget.keepBody)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
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
                    variant: widget.danger
                        ? DshButtonVariant.outline
                        : DshButtonVariant.primary,
                    onPressed: blocked ? null : () => unawaited(confirm()),
                    child: DshChromeText(
                      widget.confirmLabel,
                      style: widget.danger && !busy
                          ? TextStyle(
                              color: theme.color(
                                '--dsw-alias-state-error-primary',
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
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
    danger: true,
    keepBody: true,
    pendingLabel: actionText(i18n, 'delete.pending'),
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
    final stopped = await showDshDialog<bool>(
      context,
      label: actionText(i18n, 'close'),
      builder: (_) => WorkspaceActionForm(
        title: actionText(i18n, 'archive.confirm.title'),
        danger: true,
        description: actionText(i18n, 'archive.confirm.desc', {'title': title}),
        confirmLabel: actionText(i18n, 'archive.confirm.action'),
        i18n: i18n,
        pendingLabel: actionText(i18n, 'archive.confirm.pending'),
        detail: WorkspaceArchiveActivity(activity: activity, i18n: i18n),
        submit: (_) => actions.archiveSession(id, stopActivity: true),
      ),
    );
    if (stopped == true && context.mounted) {
      showWorkspaceNotice(
        context,
        actionText(i18n, 'toast.stoppedAndArchived'),
        undoLabel: actionText(i18n, 'menu.unarchiveSession'),
        undo: () => actions.unarchiveSession(id),
      );
    }
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
    this.slots,
  });
  final WorkspaceManagement actions;
  final DshI18n i18n;
  final String sessionId, title;
  final bool pinned, archived;
  final SlotRegistry? slots;
  final Widget Function(BuildContext, DshMenuController) builder;
  @override
  Widget build(BuildContext context) {
    String t(String key) => actionText(i18n, key);
    void perform(String verb) => unawaited(
      performSessionAction(
        context,
        actions,
        i18n,
        sessionId,
        title,
        pinned: pinned,
        archived: archived,
        verb: verb,
      ),
    );
    final owner = SessionRowOwner(
      sessionId: sessionId,
      displayTitle: title,
      pinned: pinned,
      archived: archived,
      onAction: perform,
    );
    final contributions =
        slots
            ?.renderList(
              DshSlots.sidebarWorkspacesSessionMenuItem
                  .typed<SessionRowOwner, DshMenuEntry?>(),
              owner,
            )
            .whereType<DshMenuEntry>()
            .toList() ??
        <DshMenuEntry>[];
    return DshMenu(
      align: DshMenuAlign.end,
      builder: builder,
      entries: contributions.isNotEmpty
          ? contributions
          : [
              if (!archived)
                DshMenuItem(
                  'pin',
                  t(pinned ? 'menu.unpinSession' : 'menu.pinSession'),
                  icon: DshShellIcons.pinFill,
                ),
              DshMenuItem(
                'rename',
                t('rename'),
                icon: DshShellIcons.editOutline,
              ),
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
      onSelect: (id) {
        if (!contributions.any((e) => e.id == id)) perform(id);
      },
    );
  }
}

Future<void> performSessionAction(
  BuildContext context,
  WorkspaceManagement actions,
  DshI18n i18n,
  String sessionId,
  String title, {
  required bool pinned,
  required bool archived,
  required String verb,
}) async {
  final id = verb;
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
          await renameSessionDialog(context, actions, i18n, sessionId, title);
        }
      case 'fork':
        await actions.forkSession(sessionId);
      case 'archive':
        if (archived) {
          await actions.unarchiveSession(sessionId);
        } else if (context.mounted) {
          await archiveSessionAction(context, actions, i18n, sessionId, title);
        }
      case 'copy':
        await Clipboard.setData(ClipboardData(text: sessionId));
        if (context.mounted) {
          showWorkspaceNotice(
            context,
            actionText(i18n, 'toast.sessionIdCopied'),
          );
        }
    }
  } on Object catch (e) {
    if (context.mounted) showWorkspaceNotice(context, actionFailure(e));
  }
}

class WorkspaceArchiveActivity extends StatelessWidget {
  const WorkspaceArchiveActivity({
    super.key,
    required this.activity,
    required this.i18n,
  });
  final List<Object?> activity;
  final DshI18n i18n;
  @override
  Widget build(BuildContext context) {
    final style = context.dsh
        .textStyle('--dsw-font-xs-13')
        .copyWith(height: 20 / 13, color: context.dsh.labelPrimary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in activity)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 18, child: DshChromeText('•', style: style)),
                Expanded(
                  child: DshChromeText(
                    archiveActivityLine(item, i18n),
                    style: style,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
