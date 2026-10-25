import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'controls.dart';
import 'file_diff.dart';

class DeliverablesTail extends StatefulWidget {
  const DeliverablesTail({
    super.key,
    required this.owner,
    required this.model,
    required this.showCodeDiff,
    required this.slots,
    required this.i18n,
    required this.openFile,
    required this.openReview,
  });
  final TurnTailOwner owner;
  final DeliverablesModel model;
  final Observable<bool> showCodeDiff;
  final SlotRegistry slots;
  final DshI18n i18n;
  final void Function(String path) openFile;
  final void Function(num seq, int turn, int index) openReview;
  @override
  State<DeliverablesTail> createState() => _TailState();
}

class _TailState extends State<DeliverablesTail> {
  bool expanded = false;
  String t(String k, [Map<String, Object?> p = const {}]) =>
      widget.i18n.t('deliverables', k, params: p);
  @override
  Widget build(BuildContext context) => DshWatch(
    changes: widget.showCodeDiff.changes,
    builder: (_) => DshWatch(
      changes: widget.model.summaries.state.changes,
      builder: (_) => DshWatch(
        changes: widget.model.host.changes,
        builder: (_) => DshWatch(
          changes: widget.model.phases.changes,
          builder: (_) => content(context),
        ),
      ),
    ),
  );
  Widget content(BuildContext context) {
    final data =
        widget.owner.snapshot.timeline.turns[widget.owner.turn]?.data.get(
          'deliverables',
        ) as DeliverablesTurnData?;
    final announced = widget.showCodeDiff.value ? data?.changes : null;
    final presented = presentedForClosing(data, widget.owner.seq),
        id = widget.owner.session.sessionId;
    final summary = announced == null
        ? null
        : widget.model.summaries.get(id, announced.seq);
    if (announced != null && summary == null) {
      unawaited(
        Future.microtask(() => widget.model.summaries.load(id, announced.seq)),
      );
    }
    if ((announced != null || presented.isNotEmpty) &&
        widget.model.host.value == null) {
      unawaited(Future.microtask(widget.model.loadHost));
    }
    final changes = summary?.value;
    final hasChanges = changes != null && changes.files.isNotEmpty;
    if (!hasChanges && presented.isEmpty) return const SizedBox.shrink();
    final host = widget.model.host.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasChanges)
          ChangedFilesCard(
            summary: changes,
            seq: announced!.seq,
            sessionId: id,
            model: widget.model,
            i18n: widget.i18n,
            onReview: (index) =>
                widget.openReview(announced.seq, changes.turn, index),
          ),
        if (presented.isNotEmpty) ...[
          SizedBox(height: hasChanges ? 16 : 4),
          if (host?.phase == HostReadPhase.error)
            Row(
              children: [
                Expanded(child: Text(t('presented.hostError'))),
                DshButton(
                  size: DshButtonSize.sm,
                  onPressed: () => unawaited(widget.model.loadHost()),
                  child: Text(t('presented.retry')),
                ),
              ],
            ),
          if (host?.value?.available == false)
            Text(
              t('presented.unavailable'),
              style: context.dsh
                  .textStyle('--dsw-font-xs-13')
                  .sized(12, line: 18)
                  .copyWith(color: context.dsh.labelSecondary),
            ),
          LayoutBuilder(
            builder: (context, c) {
              final single = presented.length == 1 || c.maxWidth <= 620;
              final width = single ? c.maxWidth : (c.maxWidth - 10) / 2;
              final shown = expanded ? presented : presented.take(4);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final file in shown)
                    SizedBox(
                      width: width,
                      child: PresentedFileCard(
                        key: ValueKey('presented-${file.seq}-${file.index}'),
                        file: file,
                        owner: widget.owner.session,
                        model: widget.model,
                        slots: widget.slots,
                        i18n: widget.i18n,
                        onPreview: () => widget.openFile(file.path),
                      ),
                    ),
                ],
              );
            },
          ),
          if (presented.length > 4)
            Align(
              child: DshButton(
                size: DshButtonSize.sm,
                semanticLabel: t(
                  expanded ? 'presented.collapseAria' : 'presented.expandAria',
                  {'count': presented.length},
                ),
                onPressed: () => setState(() => expanded = !expanded),
                icon: DshIcon(
                  expanded ? DshIcons.chevronUp : DshIcons.chevronDown,
                  size: 14,
                ),
                child: Text(
                  t(expanded ? 'presented.collapse' : 'presented.all', {
                    'count': presented.length,
                  }),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

String deliveryDescription(String? description, String fallback) {
  final trimmed = description
      ?.replaceFirst(RegExp(r'\s*(?:\([^()]*\)|（[^（）]*）)\s*$'), '')
      .trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}

Widget deliveryActions({
  required SlotRegistry slots,
  required SessionOwner session,
  required DeliverablesModel model,
  required DeliveryFile file,
  bool review = false,
}) {
  final phase = model.phases.value[file.actionKey],
      host = model.host.value?.value;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: slots
        .renderList(
          (review
                  ? DshSlots.deliverablesReviewFileActions
                  : DshSlots.deliverablesFileActions)
              .typed<DeliverablesFileActionsOwner, Widget>(),
          DeliverablesFileActionsOwner(
            session: session,
            actionUrl: file.actionKey,
            acquireApplications: () => model.acquireApplications(file),
            releaseApplications: model.releaseApplications,
            available:
                host?.available == true &&
                phase != NativeOpenPhase.nativeUnavailable,
            pending:
                phase == NativeOpenPhase.opening ||
                phase == NativeOpenPhase.revealing,
            onAction: (action, [app]) =>
                model.open(file, action: action, application: app),
          ),
        )
        .toList(),
  );
}

class PresentedFileCard extends StatelessWidget {
  const PresentedFileCard({
    super.key,
    required this.file,
    required this.owner,
    required this.model,
    required this.slots,
    required this.i18n,
    required this.onPreview,
  });
  final PresentedPath file;
  final SessionOwner owner;
  final DeliverablesModel model;
  final SlotRegistry slots;
  final DshI18n i18n;
  final VoidCallback onPreview;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh,
        name = workspaceBasename(file.path),
        coordinate = DeliveryFile(owner.sessionId, file.seq, file.index);
    final phase = model.phases.value[coordinate.actionKey],
        host = model.host.value?.value;
    String t(String k, [Map<String, Object?> p = const {}]) =>
        i18n.t('deliverables', k, params: p);
    final ext = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : t('presented.file');
    var key = phase?.name;
    if (host?.fileManager == 'directory') {
      key = switch (phase) {
        NativeOpenPhase.revealed => 'directoryOpened',
        NativeOpenPhase.revealing => 'directoryOpening',
        NativeOpenPhase.revealError => 'directoryError',
        _ => key,
      };
    }
    final status = key == null
        ? deliveryDescription(file.description, ext)
        : t('presented.$key');
    final error = const {
      NativeOpenPhase.error,
      NativeOpenPhase.revealError,
      NativeOpenPhase.nativeUnavailable,
    }.contains(phase);
    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.radiusLg),
      child: DshContainer(
        height: 60,
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.color('--dsw-alias-border-l1'),
            width: dshHairlineOf(context),
          ),
          borderRadius: BorderRadius.circular(theme.radiusLg),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DeliveryTap(
                label: t('presented.previewCard', {'name': file.path}),
                onTap: onPreview,
                fill: true,
                child: const SizedBox.expand(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  IgnorePointer(child: _FileTile(path: file.path)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IgnorePointer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DshChromeText(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme
                                .textStyle('--dsw-font-xs-13')
                                .sized(13, line: 20)
                                .copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: theme.labelPrimary,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Semantics(
                            liveRegion: phase != null,
                            child: DshChromeText(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme
                                  .textStyle('--dsw-font-xs-13')
                                  .sized(10, line: 16)
                                  .copyWith(
                                    color: error
                                        ? theme.color(
                                            '--dsw-alias-state-error-primary',
                                          )
                                        : theme.color(
                                            '--dsw-alias-label-tertiary',
                                          ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  deliveryActions(
                    slots: slots,
                    session: owner,
                    model: model,
                    file: coordinate,
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

class _FileTile extends StatelessWidget {
  const _FileTile({this.path});
  final String? path;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshContainer(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l1'),
          width: dshHairlineOf(context),
        ),
        color: theme
            .color('--dsw-static-neutral-00')
            .withValues(
              alpha: theme.brightness == Brightness.dark ? 0.05 : 0.5,
            ),
      ),
      child: DshFileTypeIcon(
        path: path,
        kind: path == null ? 'code' : null,
        size: 20,
      ),
    );
  }
}

class DeliveryCounts extends StatelessWidget {
  const DeliveryCounts({
    super.key,
    required this.added,
    required this.deleted,
    this.binary = false,
    this.oversized = false,
    required this.i18n,
  });
  final int added, deleted;
  final bool binary, oversized;
  final DshI18n i18n;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh,
        style = theme.textStyle('--dsw-font-markdown-code').sized(11, line: 18);
    return binary || oversized
        ? Text(
            i18n.t(
              'deliverables',
              binary ? 'changes.binary' : 'changes.oversized',
            ),
            style: style,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                i18n.t(
                  'deliverables',
                  'changes.added',
                  params: {'count': added},
                ),
                style: style.copyWith(
                  color: theme.color('--dsw-alias-state-success-primary'),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                i18n.t(
                  'deliverables',
                  'changes.deleted',
                  params: {'count': deleted},
                ),
                style: style.copyWith(
                  color: theme.color('--dsw-alias-state-error-primary'),
                ),
              ),
            ],
          );
  }
}

class ChangedFilesCard extends StatefulWidget {
  const ChangedFilesCard({
    super.key,
    required this.summary,
    required this.seq,
    required this.sessionId,
    required this.model,
    required this.i18n,
    required this.onReview,
  });
  final ChangesSummary summary;
  final num seq;
  final String sessionId;
  final DeliverablesModel model;
  final DshI18n i18n;
  final ValueChanged<int> onReview;
  @override
  State<ChangedFilesCard> createState() => _ChangedFilesState();
}

class _ChangedFilesState extends State<ChangedFilesCard> {
  bool expanded = false;
  String t(String k, [Map<String, Object?> p = const {}]) =>
      widget.i18n.t('deliverables', k, params: p);
  Widget preview(int index, Widget child) => _DiffHover(
    sessionId: widget.sessionId,
    seq: widget.seq,
    index: index,
    model: widget.model,
    i18n: widget.i18n,
    child: child,
  );
  @override
  Widget build(BuildContext context) {
    final summary = widget.summary,
        theme = context.dsh,
        single = summary.total == 1 && summary.files.isNotEmpty
            ? summary.files.first
            : null;
    final header = DeliveryTap(
      label: single == null
          ? t('changes.openReview')
          : t('changes.viewDiff', {'name': single.display}),
      onTap: () => widget.onReview(0),
      fill: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            _FileTile(path: single?.path),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DshChromeText(
                    single == null
                        ? t('changes.title', {'count': summary.total})
                        : t('changes.singleTitle', {
                            'name': workspaceBasename(single.path),
                          }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-xs-13')
                        .sized(13, line: 20)
                        .copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.labelPrimary,
                        ),
                  ),
                  DeliveryCounts(
                    added: summary.added,
                    deleted: summary.deleted,
                    binary: single?.binary == true,
                    oversized: single?.oversized == true,
                    i18n: widget.i18n,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.radiusLg),
      child: DshContainer(
        key: const ValueKey('changed-files-card'),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.color('--dsw-alias-border-l2'),
            width: dshHairlineOf(context),
          ),
          borderRadius: BorderRadius.circular(theme.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            single == null ? header : preview(0, header),
            if (single == null)
              for (
                var i = 0;
                i <
                    (expanded
                        ? summary.files.length
                        : summary.files.length.clamp(0, 4));
                i++
              )
                preview(
                  i,
                  DeliveryTap(
                    label: t('changes.viewDiff', {
                      'name': summary.files[i].display,
                    }),
                    onTap: () => widget.onReview(i),
                    padding: const EdgeInsets.fromLTRB(14, 7, 18, 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: DshChromeText(
                            summary.files[i].display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme
                                .textStyle('--dsw-font-xs-13')
                                .sized(12, line: 18)
                                .copyWith(
                                  color: theme.color(
                                    '--dsw-alias-label-tertiary',
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        DeliveryCounts(
                          added: summary.files[i].added,
                          deleted: summary.files[i].deleted,
                          binary: summary.files[i].binary,
                          oversized: summary.files[i].oversized,
                          i18n: widget.i18n,
                        ),
                      ],
                    ),
                  ),
                ),
            if (summary.files.length > 4)
              DshButton(
                size: DshButtonSize.sm,
                semanticLabel: t(
                  expanded ? 'changes.collapseAria' : 'changes.expandAria',
                  {'count': summary.files.length},
                ),
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(
                  t(expanded ? 'changes.collapse' : 'changes.all', {
                    'count': summary.files.length,
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffHover extends StatefulWidget {
  const _DiffHover({
    required this.sessionId,
    required this.seq,
    required this.index,
    required this.model,
    required this.i18n,
    required this.child,
  });
  final String sessionId;
  final num seq;
  final int index;
  final DeliverablesModel model;
  final DshI18n i18n;
  final Widget child;
  @override
  State<_DiffHover> createState() => _DiffHoverState();
}

class _DiffHoverState extends State<_DiffHover> {
  Timer? delay;
  OverlayEntry? entry;
  final link = LayerLink();
  void close() {
    delay?.cancel();
    entry?.remove();
    entry = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }

  void open() {
    if (entry != null || !mounted) return;
    unawaited(
      widget.model.diffs.load(widget.sessionId, widget.seq, widget.index),
    );
    entry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: MouseRegion(
            onEnter: (_) => delay?.cancel(),
            onExit: (_) => close(),
            child: SizedBox(
              width: 520,
              height: 280,
              child: DshContainer(
                decoration: BoxDecoration(
                  color: context.dsh.color('--dsw-alias-bg-layer-1'),
                  borderRadius: BorderRadius.circular(context.dsh.radiusLg),
                  border: Border.all(
                    color: context.dsh.color('--dsw-alias-border-l2'),
                    width: dshHairlineOf(context),
                  ),
                ),
                child: SingleChildScrollView(
                  child: DshWatch(
                    changes: widget.model.diffs.state.changes,
                    builder: (_) => DeliverablesFileDiff(
                      state: widget.model.diffs.get(
                        widget.sessionId,
                        widget.seq,
                        widget.index,
                      ),
                      i18n: widget.i18n,
                      retry: () => unawaited(
                        widget.model.diffs.load(
                          widget.sessionId,
                          widget.seq,
                          widget.index,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry!);
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: link,
    child: MouseRegion(
      onEnter: (_) {
        delay?.cancel();
        delay = Timer(const Duration(milliseconds: 500), open);
      },
      onExit: (_) {
        delay?.cancel();
        delay = Timer(const Duration(milliseconds: 120), close);
      },
      child: widget.child,
    ),
  );
}
