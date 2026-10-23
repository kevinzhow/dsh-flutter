import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show MaterialPageRoute, showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'catalog.dart';
import 'transcript.dart';

/// What the app provides the feature: the child's read-only session as an
/// owner, the host's list facts for a child, and the navigator to push on.
abstract interface class SubagentServices {
  /// The app's navigator, for the transcript route.
  GlobalKey<NavigatorState> get navigatorKey;

  /// The read-only session owner of one direct child; the first call starts
  /// following it.
  SessionOwner childOwner(SessionOwner parent, SubagentEntry entry);

  /// Activity, usage and duration of a child from the session list.
  SubagentStatus statusOf(String childId);

  /// Fires when the session list (and so a status) changes.
  Stream<Object?> get changes;
}

/// The subagent feature (dsh `ui-subagent`).
class SubagentFeature {
  SubagentFeature._(this._slots, this._i18n, this._services);

  final SlotRegistry _slots;
  final DshI18n Function() _i18n;
  final SubagentServices _services;

  final Slot<SessionOwner, Widget> _viewSlot = DshSlots.conversationView
      .typed<SessionOwner, Widget>();

  /// Open one child's transcript by id, resolved against the parent's
  /// catalog; does nothing for an unknown or external row.
  void openById(SessionOwner parent, String childId) {
    final entry = catalogOf(parent.session.projections.get('subagentCatalog'))
        .where((e) => e.id == childId)
        .firstOrNull;
    if (entry != null) open(parent, entry);
  }

  /// Open [entry]'s transcript full screen.
  void open(SessionOwner parent, SubagentEntry entry) {
    if (!entry.openable) return;
    final navigator = _services.navigatorKey.currentState;
    if (navigator == null) return;
    final child = _services.childOwner(parent, entry);
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (context) => SubagentTranscript(
          child: child,
          entry: entry,
          slots: _slots,
          i18n: _i18n(),
          viewSlot: _viewSlot,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

/// Occupy `conversation.session.header.actions` with the subagent trigger.
SubagentFeature registerSubagentFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  required SubagentServices services,
}) {
  final feature = SubagentFeature._(slots, i18n, services);
  slots.register<SessionOwner, Widget>(
    DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
    (owner) => SubagentTrigger(
      owner: owner,
      i18n: i18n,
      services: services,
      onOpen: feature.open,
    ),
    id: 'subagent',
  );
  return feature;
}

/// The header trigger: the subagent glyph with the direct-child count (and a
/// running mark); hidden while the catalog is empty. Opens the catalog sheet.
class SubagentTrigger extends StatefulWidget {
  const SubagentTrigger({
    super.key,
    required this.owner,
    required this.i18n,
    required this.services,
    required this.onOpen,
  });

  final SessionOwner owner;
  final DshI18n Function() i18n;
  final SubagentServices services;
  final void Function(SessionOwner parent, SubagentEntry entry) onOpen;

  @override
  State<SubagentTrigger> createState() => _SubagentTriggerState();
}

class _SubagentTriggerState extends State<SubagentTrigger> {
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void initState() {
    super.initState();
    void changed(Object? _) {
      if (mounted) setState(() {});
    }

    _subs.add(widget.owner.session.projections.changes.listen(changed));
    _subs.add(widget.services.changes.listen(changed));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = catalogOf(
      widget.owner.session.projections.get('subagentCatalog'),
    );
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = context.dsh;
    final i18n = widget.i18n();
    final running = entries
        .where((e) => widget.services.statusOf(e.id).running)
        .length;
    final label = running > 0
        ? i18n.t(
            'subagent',
            running == 1 ? 'count.running.one' : 'count.running.other',
            params: {'count': running},
          )
        : i18n.t(
            'subagent',
            entries.length == 1 ? 'count.total.one' : 'count.total.other',
            params: {'count': entries.length},
          );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('subagent-trigger'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: theme.bgBase,
          builder: (sheet) => SubagentCatalogSheet(
            owner: widget.owner,
            i18n: widget.i18n,
            services: widget.services,
            onOpen: (entry) {
              Navigator.of(sheet).pop();
              widget.onOpen(widget.owner, entry);
            },
          ),
        ),
        child: SizedBox(
          height: DshSpace.touch,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DshSpace.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (running > 0)
                  const DshStateDot(DshStateDotState.ongoing)
                else
                  DshIcon(
                    DshIcons.agentPreset,
                    size: 14,
                    color: theme.labelSecondary,
                  ),
                const SizedBox(width: 4),
                Text(
                  '${entries.length}',
                  key: const ValueKey('subagent-count'),
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(color: theme.labelSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The direct catalog of one session as a sheet (dsh's lineage tree, one
/// level on a phone): per child its activity dot, label or id, mode, token
/// total and active duration.
class SubagentCatalogSheet extends StatefulWidget {
  const SubagentCatalogSheet({
    super.key,
    required this.owner,
    required this.i18n,
    required this.services,
    required this.onOpen,
  });

  final SessionOwner owner;
  final DshI18n Function() i18n;
  final SubagentServices services;
  final void Function(SubagentEntry entry) onOpen;

  @override
  State<SubagentCatalogSheet> createState() => _SubagentCatalogSheetState();
}

class _SubagentCatalogSheetState extends State<SubagentCatalogSheet> {
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void initState() {
    super.initState();
    void changed(Object? _) {
      if (mounted) setState(() {});
    }

    _subs.add(widget.owner.session.projections.changes.listen(changed));
    _subs.add(widget.services.changes.listen(changed));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final i18n = widget.i18n();
    final entries = catalogOf(
      widget.owner.session.projections.get('subagentCatalog'),
    );
    final caption = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: ListView(
        key: const ValueKey('subagent-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: DshSpace.sm),
        children: [
          for (final entry in entries)
            Builder(
              builder: (context) {
                final status = widget.services.statusOf(entry.id);
                final state = status.running
                    ? DshStateDotState.ongoing
                    : status.completed
                    ? DshStateDotState.done
                    : DshStateDotState.idle;
                final meta = [
                  modeLabel(i18n, entry.mode),
                  if (status.tokens != null)
                    i18n.t(
                      'subagent',
                      'tokens.total',
                      params: {'value': formatTokens(status.tokens!, i18n)},
                    ),
                  if (status.durationMs != null)
                    formatDuration(status.durationMs!, i18n),
                ].join(' · ');
                return GestureDetector(
                  key: ValueKey('subagent-row-${entry.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: entry.openable ? () => widget.onOpen(entry) : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: DshSpace.touch + 8,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DshSpace.lg,
                        vertical: DshSpace.sm,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            child: Center(child: DshStateDot(state)),
                          ),
                          const SizedBox(width: DshSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.label ?? entry.id,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme
                                      .textStyle('--dsw-font-s-14')
                                      .copyWith(
                                        color: entry.openable
                                            ? theme.labelPrimary
                                            : theme.labelSecondary,
                                      ),
                                ),
                                Text(meta, style: caption),
                              ],
                            ),
                          ),
                          if (entry.openable)
                            Transform.rotate(
                              angle: -1.5708,
                              child: DshIcon(
                                DshIcons.chevronDown,
                                size: 14,
                                color: theme.color(
                                  '--dsw-alias-label-tertiary',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
