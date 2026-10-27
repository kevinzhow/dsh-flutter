import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'dsh_button.dart';
import 'dsh_headed_dialog.dart';
import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_presentation.dart';
import 'dsh_recipes.g.dart';
import 'dsh_settings.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Show the source RiskConfirmation through the shared Modal route.
/// An explicit acknowledgement gates confirmation; cancellation answers false.
Future<bool> showDshRiskDialog(
  BuildContext context, {
  required String title,
  required String description,
  required String acknowledgeLabel,
  required String cancelLabel,
  required String closeLabel,
  required String confirmLabel,
  bool disabled = false,
  FocusNode? restoreFocus,
}) async {
  final opener = restoreFocus ?? FocusManager.instance.primaryFocus;
  final confirmed = await showDshDialog<bool>(
    context,
    width: DshRiskDialogRecipe.width,
    label: title,
    restoreFocus: opener,
    builder: (_) => DshRiskDialog.content(
      title: title,
      description: description,
      acknowledgeLabel: acknowledgeLabel,
      cancelLabel: cancelLabel,
      closeLabel: closeLabel,
      confirmLabel: confirmLabel,
      disabled: disabled,
    ),
  );
  return confirmed ?? false;
}

/// The RiskConfirmation card. A caller may control acknowledgement explicitly;
/// the route helper otherwise owns that state for the lifetime of the dialog.
class DshRiskDialog extends StatefulWidget {
  const DshRiskDialog({
    super.key,
    required this.title,
    required this.description,
    required this.acknowledgeLabel,
    required this.cancelLabel,
    required this.closeLabel,
    required this.confirmLabel,
    this.acknowledged,
    this.onAcknowledgedChange,
    this.disabled = false,
    this.onCancel,
    this.onConfirm,
  }) : _framed = true,
       assert((acknowledged == null) == (onAcknowledgedChange == null));

  /// Content profile for a frame already owned by [showDshDialog].
  const DshRiskDialog.content({
    super.key,
    required this.title,
    required this.description,
    required this.acknowledgeLabel,
    required this.cancelLabel,
    required this.closeLabel,
    required this.confirmLabel,
    this.disabled = false,
    this.acknowledged,
    this.onAcknowledgedChange,
    this.onCancel,
    this.onConfirm,
  }) : _framed = false,
       assert((acknowledged == null) == (onAcknowledgedChange == null));

  final String title,
      description,
      acknowledgeLabel,
      cancelLabel,
      closeLabel,
      confirmLabel;
  final bool? acknowledged;
  final ValueChanged<bool>? onAcknowledgedChange;
  final bool disabled, _framed;
  final VoidCallback? onCancel, onConfirm;

  @override
  State<DshRiskDialog> createState() => _DshRiskDialogState();
}

class _DshRiskDialogState extends State<DshRiskDialog> {
  bool _acknowledged = false;
  final _acknowledgement = GlobalKey(debugLabel: 'risk acknowledgement');
  bool get _checked => widget.acknowledged ?? _acknowledged;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.disabled ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      FocusManager.instance.applyFocusChangesIfNeeded();
      final target = _acknowledgement.currentContext;
      if (target == null) {
        return;
      }
      var focused = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
        element,
      ) {
        if (element == target) {
          focused = true;
          return false;
        }
        return true;
      });
      if (focused) {
        // Browser focus reveals the preferred checkbox when it is below the
        // viewport. Flutter autofocus itself does not perform that scroll.
        Scrollable.ensureVisible(
          target,
          alignment: 1,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _change(bool value) {
    if (widget.acknowledged == null) {
      setState(() => _acknowledged = value);
    }
    widget.onAcknowledgedChange?.call(value);
  }

  void _cancel() {
    if (widget.onCancel case final cancel?) {
      cancel();
    } else {
      Navigator.of(context).pop(false);
    }
  }

  void _confirm() {
    if (widget.onConfirm case final confirm?) {
      confirm();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final warningStyle = theme
        .fixedTextStyle(
          size: DshRiskDialogRecipe.warningFontSize,
          line: DshRiskDialogRecipe.warningLineHeight,
        )
        .copyWith(color: theme.color(DshRiskDialogRecipe.warningLabelToken));
    final content = DshHeadedDialogContent(
      key: widget._framed ? null : const ValueKey('risk-dialog'),
      title: widget.title,
      closeLabel: widget.closeLabel,
      closeKey: const ValueKey('risk-close'),
      headerKey: const ValueKey('risk-header'),
      bodyKey: const ValueKey('risk-body'),
      contentKey: const ValueKey('risk-content'),
      footerKey: const ValueKey('risk-footer'),
      onClose: _cancel,
      scrollContent: true,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: DshRiskDialogRecipe.warningIconTop,
                ),
                child: DshIcon(
                  DshIcons.warning,
                  size: DshRiskDialogRecipe.warningIconSize,
                  color: theme.color(DshRiskDialogRecipe.errorIconToken),
                ),
              ),
              const SizedBox(width: DshRiskDialogRecipe.warningGap),
              Expanded(
                child: DshChromeText(
                  widget.description,
                  key: const ValueKey('risk-description'),
                  style: warningStyle,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: DshCheckboxRecipe.riskMarginTop,
            ),
            child: KeyedSubtree(
              key: _acknowledgement,
              child: DshCheckbox(
                key: const ValueKey('risk-acknowledge'),
                value: _checked,
                onChanged: widget.disabled ? null : _change,
                label: widget.acknowledgeLabel,
                profile: DshCheckboxProfile.riskAcknowledgement,
                autofocus: !widget.disabled,
              ),
            ),
          ),
        ],
      ),
      footer: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: DshRiskDialogRecipe.actionMinWidth,
          ),
          child: DshButton(
            key: const ValueKey('risk-cancel'),
            variant: DshButtonVariant.outline,
            onPressed: _cancel,
            child: DshChromeText(
              widget.cancelLabel,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: DshRiskDialogRecipe.confirmMinWidth,
          ),
          child: DshButton(
            key: const ValueKey('risk-confirm'),
            variant: DshButtonVariant.primary,
            onPressed: widget.disabled || !_checked ? null : _confirm,
            child: DshChromeText(
              widget.confirmLabel,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
    if (!widget._framed) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.max(
          DshRiskDialogRecipe.contentMinHeight,
          MediaQuery.sizeOf(context).height -
              DshRiskDialogRecipe.dynamicViewportInset,
        ),
      ),
      child: DshDialogFrame(
        key: const ValueKey('risk-dialog'),
        width: DshRiskDialogRecipe.width,
        child: content,
      ),
    );
  }
}
