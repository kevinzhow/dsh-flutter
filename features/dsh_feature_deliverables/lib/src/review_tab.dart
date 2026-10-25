import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'deliverables_tail.dart';
import 'file_diff.dart';
import 'review_address.dart';

class ChangesReviewTab extends StatefulWidget {
  const ChangesReviewTab({
    super.key,
    required this.owner,
    required this.model,
    required this.slots,
    required this.i18n,
    required this.openFile,
  });
  final SidebarTabOwner owner;
  final DeliverablesModel model;
  final SlotRegistry slots;
  final DshI18n i18n;
  final ValueChanged<String> openFile;
  @override
  State<ChangesReviewTab> createState() => _ReviewState();
}

class _ReviewState extends State<ChangesReviewTab> {
  int index = 0;
  bool split = false, wrap = false;
  @override
  void initState() {
    super.initState();
    navigate();
  }

  @override
  void didUpdateWidget(ChangesReviewTab old) {
    super.didUpdateWidget(old);
    if (old.owner.revision != widget.owner.revision ||
        old.owner.contentId != widget.owner.contentId) {
      navigate();
    }
  }

  void navigate() {
    final at = widget.owner.params['index'];
    if (at is int && at >= 0) index = at;
  }

  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('deliverables', key, params: params);
  @override
  Widget build(BuildContext context) => DshWatch(
    changes: widget.model.summaries.state.changes,
    builder: (_) => DshWatch(
      changes: widget.model.diffs.state.changes,
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
    final address = ChangesReviewAddress.parse(widget.owner.contentId);
    // An address never grants authority to a different session's sidebar.
    if (address == null ||
        address.sessionId != widget.owner.session.sessionId) {
      return Text(t('diff.missing'));
    }
    final id = address.sessionId,
        seq = address.seq,
        model = widget.model,
        summary = model.summaries.get(id, seq);
    if (summary == null) {
      unawaited(Future.microtask(() => model.summaries.load(id, seq)));
    }
    if (model.host.value == null) unawaited(Future.microtask(model.loadHost));
    final files = summary?.value?.files ?? const <ChangedFile>[];
    final at = index < files.length ? index : 0,
        file = files.isEmpty ? null : files[at];
    final diff = file == null ? null : model.diffs.get(id, seq, at);
    if (file != null && diff == null) {
      unawaited(Future.microtask(() => model.diffs.load(id, seq, at)));
    }
    final theme = context.dsh;
    Widget toggle({
      required String label,
      required DshIconData icon,
      required bool selected,
      required VoidCallback press,
    }) => Semantics(
      toggled: selected,
      child: DshButton(
        size: DshButtonSize.sm,
        semanticLabel: label,
        onPressed: press,
        child: DshIcon(icon, size: 15),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DshContainer(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.color('--dsw-alias-border-l2'),
                width: dshHairlineOf(context),
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) => Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 4,
              children: [
                SizedBox(
                  width: (c.maxWidth - 180).clamp(80, 320),
                  child: file == null
                      ? Text(t('review.title', {'turn': address.turn}))
                      : DshMenu(
                          dense: true,
                          selectedIds: ['$at'],
                          entries: [
                            for (var i = 0; i < files.length; i++)
                              DshMenuItem('$i', files[i].display),
                          ],
                          onSelect: (id) =>
                              setState(() => index = int.parse(id)),
                          builder: (context, menu) => DshButton(
                            size: DshButtonSize.sm,
                            semanticLabel: t('review.selectFile'),
                            onPressed: menu.toggle,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    file.display,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const DshIcon(DshIcons.chevronDown, size: 12),
                              ],
                            ),
                          ),
                        ),
                ),
                if (file != null)
                  DeliveryCounts(
                    added: file.added,
                    deleted: file.deleted,
                    binary: file.binary,
                    oversized: file.oversized,
                    i18n: widget.i18n,
                  ),
                toggle(
                  label: t('review.splitAria'),
                  icon: DshIcons.compareSplit,
                  selected: split,
                  press: () => setState(() => split = !split),
                ),
                toggle(
                  label: t('review.wrapAria'),
                  icon: wrap ? DshIcons.nowrap : DshIcons.wrap,
                  selected: wrap,
                  press: () => setState(() => wrap = !wrap),
                ),
                if (file != null) ...[
                  DshButton(
                    size: DshButtonSize.sm,
                    semanticLabel: t('review.openFileAria', {
                      'name': file.display,
                    }),
                    onPressed: () => widget.openFile(file.path),
                    child: const DshIcon(DshIcons.inspect, size: 15),
                  ),
                  deliveryActions(
                    slots: widget.slots,
                    session: widget.owner.session,
                    model: model,
                    file: DeliveryFile(
                      id,
                      seq,
                      at,
                      kind: FileDeliveryKind.changed,
                    ),
                    review: true,
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: file == null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      t(
                        summary?.phase == HostReadPhase.missing
                            ? 'diff.missing'
                            : 'diff.loading',
                      ),
                    ),
                  )
                : DeliverablesFileDiff(
                    state: diff,
                    i18n: widget.i18n,
                    split: split,
                    wrap: wrap,
                    retry: () => unawaited(model.diffs.load(id, seq, at)),
                  ),
          ),
        ),
      ],
    );
  }
}
