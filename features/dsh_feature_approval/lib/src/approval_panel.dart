import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import 'approval_tracker.dart';

/// Composer takeover for one pending approval (dsh `ApprovalPanel.tsx`):
/// a status strip, the headline reason (or the generic escalation sentence),
/// and Reject / Allow once. Reads only the theme contract and the `approval`
/// i18n namespace; never branches on a theme or pack name.
class ApprovalPanel extends StatefulWidget {
  const ApprovalPanel({super.key, required this.approval, required this.i18n});

  final PendingApproval approval;
  final DshI18n i18n;

  @override
  State<ApprovalPanel> createState() => _ApprovalPanelState();
}

class _ApprovalPanelState extends State<ApprovalPanel> {
  bool _answered = false;

  Future<void> _answer(String outcome) async {
    if (_answered) return;
    setState(() => _answered = true);
    try {
      await widget.approval.answer(outcome);
    } on Object {
      // The host refused or the connection dropped: stay answerable.
      if (mounted) setState(() => _answered = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<DshThemeData>()!;
    final t = (String key, {Map<String, Object?> params = const {}}) =>
        widget.i18n.t('approval', key, params: params);
    final reason = widget.approval.reasonFor(widget.i18n.locale.name);
    final label = theme.color('--dsw-alias-label-primary');
    final warn = theme.color('--dsw-alias-state-warn-primary');
    return Container(
      key: const ValueKey('approval-panel'),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-bg-layer-2'),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l4'),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(theme.number('--dsw-radius-lg')),
      ),
      padding: const EdgeInsets.all(12),
      child: DefaultTextStyle(
        style: theme.textStyle('--dsw-font-s-14').copyWith(color: label),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: warn,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                DshChromeText(
                  t('waiting'),
                  key: const ValueKey('approval-waiting'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: t('detail.aria'),
              child: DshChromeText(
                reason ??
                    t(
                      'escalation',
                      params: {'toolName': widget.approval.toolName},
                    ),
                key: const ValueKey('approval-headline'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DshButton(
                  key: const ValueKey('approval-reject'),
                  variant: DshButtonVariant.outline,
                  onPressed: _answered ? null : () => _answer('rejected'),
                  child: DshChromeText(t('reject')),
                ),
                const SizedBox(width: 8),
                DshButton(
                  key: const ValueKey('approval-allow'),
                  variant: DshButtonVariant.primary,
                  onPressed: _answered ? null : () => _answer('allowed-once'),
                  child: DshChromeText(t('allowOnce')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
