import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Effective Host target, including a pending mode transition.
bool planModeOn(Object? projection) {
  if (projection is! Map) return false;
  final active = projection['active'] == true;
  return projection['pending'] == true ? !active : active;
}

class PlanChip extends StatefulWidget {
  const PlanChip({
    super.key,
    required this.projection,
    required this.i18n,
    this.locked = false,
    this.exitPlanMode,
  });
  final Object? projection;
  final DshI18n i18n;
  final bool locked;
  final Future<String?> Function()? exitPlanMode;
  @override
  State<PlanChip> createState() => _PlanChipState();
}

class _PlanChipState extends State<PlanChip> {
  bool leaving = false, hover = false, focused = false;
  String? error;
  String t(String key) => widget.i18n.t('plan', key);
  Future<void> leave() async {
    if (widget.locked || leaving || widget.exitPlanMode == null) return;
    setState(() {
      leaving = true;
      error = null;
    });
    try {
      final failure = await widget.exitPlanMode!();
      if (mounted) setState(() => error = failure);
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!planModeOn(widget.projection)) return const SizedBox.shrink();
    final theme = context.dsh;
    final enabled = !widget.locked && !leaving && widget.exitPlanMode != null;
    final active = theme.color('--dsw-alias-state-business-primary');
    final fill = theme.color('--dsw-alias-state-business-tertiary');
    Widget button = DshContainer(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: enabled && (hover || focused)
            ? Color.lerp(fill, active, .06)
            : fill,
        borderRadius: BorderRadius.circular(theme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DshIcon(
            enabled && (hover || focused)
                ? DshShellIcons.closeCircleFill
                : DshIcons.plan,
            size: 14,
            color: active,
          ),
          const SizedBox(width: 4),
          DshChromeText(
            t('chip.label'),
            style: theme
                .textStyle('--dsw-font-xs-13')
                .copyWith(
                  height: 20 / 13,
                  fontWeight: FontWeight.w500,
                  color: active,
                ),
          ),
        ],
      ),
    );
    button = Opacity(opacity: enabled ? 1 : .6, child: button);
    button = GestureDetector(
      key: const ValueKey('plan-chip'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? leave : null,
      child: button,
    );
    button = MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: button,
    );
    button = FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: (v) => setState(() => focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            leave();
            return null;
          },
        ),
      },
      child: button,
    );
    button = DshTooltip(label: t('chip.on.title'), child: button);
    button = Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: t('chip.on.aria'),
      onTap: enabled ? leave : null,
      child: ExcludeSemantics(child: button),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (error != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: DshTooltip(
                label: error!,
                child: DshChromeText(
                  t('chip.exitFailed'),
                  key: const ValueKey('plan-exit-error'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        height: 18 / 12,
                        color: theme.color('--dsw-alias-state-error-primary'),
                      ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
