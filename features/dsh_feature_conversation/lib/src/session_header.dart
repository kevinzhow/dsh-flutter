import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The model the next turn will use: `modelSelection.next`, else the one the
/// last turn used, as `provider/model` plus the reasoning effort. Null when
/// the host has not reported a selection.
({String model, String? effort})? modelIndicator(Object? modelSelection) {
  if (modelSelection is! Map) return null;
  for (final key in const ['next', 'lastUsed']) {
    final entry = modelSelection[key];
    if (entry is Map && entry['model'] is String) {
      final effort = entry['reasoningEffort'];
      return (
        model: entry['model']! as String,
        effort: effort is String && effort.isNotEmpty ? effort : null,
      );
    }
  }
  return null;
}

/// Header of an open session (dsh `conversation.header`): the title projection
/// and the model indicator, with a running dot.
class SessionHeader extends StatefulWidget {
  const SessionHeader({
    super.key,
    required this.owner,
    required this.i18n,
    this.slots,
  });

  final SessionOwner owner;
  final DshI18n i18n;

  /// Renders `conversation.session.header.actions` (the subagent trigger, the
  /// sidebar button) at the end of the header.
  final SlotRegistry? slots;

  @override
  State<SessionHeader> createState() => _SessionHeaderState();
}

class _SessionHeaderState extends State<SessionHeader> {
  StreamSubscription<Object?>? _projections;
  StreamSubscription<Object?>? _session;

  @override
  void initState() {
    super.initState();
    _projections = widget.owner.session.projections.changes.listen(_changed);
    _session = widget.owner.session.snapshot.changes.listen(_changed);
  }

  void _changed(Object? _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_projections?.cancel());
    unawaited(_session?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final session = widget.owner.session;
    final title = (session.projections.get('title') as String?)?.trim() ?? '';
    final model = modelIndicator(session.projections.get('modelSelection'));
    final running = session.snapshot.value.running;
    final caption = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
    final actions = widget.slots?.renderList(
      DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
      widget.owner,
    );
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (running) ...[
              const DshStatusDot(DshStatus.running),
              const SizedBox(width: DshSpace.sm),
            ],
            Flexible(
              child: DshChromeText(
                title.isEmpty
                    ? widget.i18n.t(appNamespace, 'sessions.untitled')
                    : title,
                key: const ValueKey('session-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme
                    .textStyle('--dsw-font-base-strong-16')
                    .copyWith(color: theme.labelPrimary),
              ),
            ),
          ],
        ),
        DshChromeText(
          model == null
              ? widget.i18n.t(appNamespace, 'session.model.unknown')
              : (model.effort == null
                    ? model.model
                    : '${model.model} · ${model.effort}'),
          key: const ValueKey('model-indicator'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: caption,
        ),
      ],
    );
    if (actions == null || actions.isEmpty) return titles;
    return Row(
      children: [
        Expanded(child: titles),
        for (final action in actions) action,
      ],
    );
  }
}
