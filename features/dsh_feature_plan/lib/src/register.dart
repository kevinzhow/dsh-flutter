import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'plan_cards.dart';
import 'plan_document.dart';
import 'plan_chip.dart';
import 'plan_preview.dart';
import 'plan_resource.dart';
import 'plan_services.dart';

final Slot<TurnTailOwner, Widget?> turnTailSlot = DshSlots
    .conversationChatTurnTail
    .typed<TurnTailOwner, Widget?>();

/// Plan controls, logged document resources and pending-review navigation.
PlanFeature registerPlanFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  PlanServices? services,
}) {
  final feature = PlanFeature(services);
  slots.sidebarTabs.register(
    SidebarTabType(
      kind: 'plan',
      multiple: true,
      acceptsResource: (address) =>
          PlanAddress.parse(address) != null || isReviewPreviewAddress(address),
      titleForResource: (_) => i18n().t('plan', 'preview.title'),
    ),
  );
  slots.register<TurnTailOwner, Widget?>(turnTailSlot, (owner) {
    final plans = owner.snapshot.plansOfTurn(owner.turn);
    if (plans.isEmpty) return null;
    return Builder(
      builder: (context) => PlanCards(
        plans: plans,
        i18n: i18n(),
        onOpen: (plan) {
          if (services == null) {
            showPlanSheet(context, plan: plan, i18n: i18n());
          } else {
            feature.openPlan(owner.session, plan.callId);
          }
        },
      ),
    );
  }, id: 'plan-cards');
  slots.register<PlanInputOwner, Widget>(
    DshSlots.conversationInputPlan.typed<PlanInputOwner, Widget>(),
    (owner) => DshWatch(
      changes: owner.session.session.projections.changes,
      builder: (_) => PlanChip(
        projection: owner.session.session.projections.get('plan'),
        locked: owner.locked,
        i18n: i18n(),
        exitPlanMode: services == null
            ? null
            : () => services.exitPlanMode(owner.session.sessionId),
      ),
    ),
  );
  for (final title in [false, true]) {
    slots.register<SidebarTabOwner, Widget>(
      (title ? DshSlots.sidebarRightPaneTabTitle : DshSlots.sidebarRightPaneTab)
          .typed<SidebarTabOwner, Widget>(),
      (owner) => PlanPreview(
        owner: owner,
        feature: feature,
        i18n: i18n(),
        titleOnly: title,
      ),
      key: 'plan',
    );
  }
  slots.register<PlanReviewOwner, Widget>(
    DshSlots.conversationPlanReviewActions.typed<PlanReviewOwner, Widget>(),
    (owner) => _ReviewOpen(owner: owner, feature: feature, i18n: i18n()),
    id: 'plan-review-open',
  );
  return feature;
}

class _ReviewOpen extends StatefulWidget {
  const _ReviewOpen({
    required this.owner,
    required this.feature,
    required this.i18n,
  });
  final PlanReviewOwner owner;
  final PlanFeature feature;
  final DshI18n i18n;
  @override
  State<_ReviewOpen> createState() => _ReviewOpenState();
}

class _ReviewOpenState extends State<_ReviewOpen> {
  int _openEpoch = 0;
  bool _hover = false;
  @override
  void initState() {
    super.initState();
    autoOpen();
  }

  @override
  void didUpdateWidget(_ReviewOpen old) {
    super.didUpdateWidget(old);
    if (old.owner.requestKey != widget.owner.requestKey ||
        old.owner.callId != widget.owner.callId ||
        old.feature != widget.feature) {
      autoOpen();
    }
  }

  void autoOpen() {
    final owner = widget.owner;
    final epoch = ++_openEpoch;
    final identity = (
      owner.session.sessionId,
      owner.callId == null ? 'review' : 'call',
      owner.callId ?? owner.requestKey,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          epoch != _openEpoch ||
          widget.feature.services == null ||
          !widget.feature.openedReviews.add(identity)) {
        return;
      }
      widget.feature.openReview(owner);
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.feature.services != null;
    void open() => widget.feature.openReview(widget.owner);
    final color = _hover
        ? context.dsh.labelPrimary
        : context.dsh.labelSecondary;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.i18n.t('plan', 'preview.open'),
      onTap: enabled ? open : null,
      child: ExcludeSemantics(
        child: DshTooltip(
          label: widget.i18n.t('plan', 'preview.open'),
          child: FocusableActionDetector(
            enabled: enabled,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  open();
                  return null;
                },
              ),
            },
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              cursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                key: const ValueKey('plan-review-open'),
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? open : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DshChromeText(
                      widget.i18n.t('plan', 'preview.full'),
                      style: context.dsh
                          .textStyle('--dsw-font-s-14')
                          .copyWith(color: color, height: 20 / 14),
                    ),
                    const SizedBox(width: 4),
                    DshIcon(DshIcons.chevronRight, size: 14, color: color),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
