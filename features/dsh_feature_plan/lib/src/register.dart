import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'plan_cards.dart';
import 'plan_document.dart';

/// `conversation.chat.turnTail` as this feature uses it: an entry returns
/// null when the turn has nothing to show.
final Slot<TurnTailOwner, Widget?> turnTailSlot = DshSlots
    .conversationChatTurnTail
    .typed<TurnTailOwner, Widget?>();

/// `conversation.input.dock` as this feature uses it.
final Slot<SessionOwner, Widget> dockSlot = DshSlots.conversationInputDock
    .typed<SessionOwner, Widget>();

/// The plan-mode state of a `plan` projection value: the effective target is
/// `pending ? !active : active`, a folded host value, never client optimism.
bool planModeOn(Object? projection) {
  if (projection is! Map) return false;
  final active = projection['active'] == true;
  return projection['pending'] == true ? !active : active;
}

/// Occupy `conversation.chat.turnTail` with the submitted-plan cards and
/// `conversation.input.dock` with the plan-mode chip (dsh `ui-plan`).
void registerPlanFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) {
  slots.register<TurnTailOwner, Widget?>(turnTailSlot, (owner) {
    final plans = owner.snapshot.plansOfTurn(owner.turn);
    if (plans.isEmpty) return null;
    return Builder(
      builder: (context) => PlanCards(
        plans: plans,
        i18n: i18n(),
        onOpen: (plan) => showPlanSheet(context, plan: plan, i18n: i18n()),
      ),
    );
  }, id: 'plan-cards');
  slots.register<SessionOwner, Widget>(
    dockSlot,
    (owner) => _PlanChip(owner: owner, i18n: i18n()),
    id: 'plan-chip',
    order: -1,
  );
}

class _PlanChip extends StatefulWidget {
  const _PlanChip({required this.owner, required this.i18n});

  final SessionOwner owner;
  final DshI18n i18n;

  @override
  State<_PlanChip> createState() => _PlanChipState();
}

class _PlanChipState extends State<_PlanChip> {
  late final StreamSubscription<Object?> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.owner.session.projections.changes.listen(
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!planModeOn(widget.owner.session.projections.get('plan'))) {
      return const SizedBox.shrink();
    }
    final theme = context.dsh;
    final color = theme.color('--dsw-alias-state-business-primary');
    final label = widget.i18n.t('plan', 'chip.label');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.md,
        0,
        DshSpace.md,
        DshSpace.sm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: widget.i18n.t('plan', 'chip.on.title'),
          child: Container(
            key: const ValueKey('plan-chip'),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.color('--dsw-alias-state-business-tertiary'),
              borderRadius: BorderRadius.circular(theme.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DshIcon(DshIcons.plan, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(
                        height: 20 / 13,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
