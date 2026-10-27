import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> headedDialogsCases = {
  'headed-dialogs.risk': ParityCase(
    widgets: const ['dsh_ui:DshRiskDialog', 'dsh_ui:DshCheckbox'],
    framed: false,
    notes:
        'Actual controlled RiskConfirmation copy, checkbox states and overflow. '
        'Long cases repeat the real localized warning and scroll only risk-content; '
        'the canonical risk frame owns header/body/footer geometry.',
    build: (ctx) => _RiskFixture(
      locale: DshLocale.fromTag(ctx.locale),
      checked: ctx.props['checked'] as bool,
      disabled: ctx.props['disabled'] as bool,
      repeat: (ctx.props['repeat'] as num).toInt(),
    ),
  ),
};

class _RiskFixture extends StatefulWidget {
  const _RiskFixture({
    required this.locale,
    required this.checked,
    required this.disabled,
    required this.repeat,
  });

  final DshLocale locale;
  final bool checked, disabled;
  final int repeat;

  @override
  State<_RiskFixture> createState() => _RiskFixtureState();
}

class _RiskFixtureState extends State<_RiskFixture> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final t = DshI18n(widget.locale);
      showDshDialog<void>(
        context,
        width: DshRiskDialogRecipe.width,
        label: t.t('permission.access', 'confirm.title'),
        builder: (_) => _RiskContent(
          locale: widget.locale,
          checked: widget.checked,
          disabled: widget.disabled,
          repeat: widget.repeat,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _RiskContent extends StatefulWidget {
  const _RiskContent({
    required this.locale,
    required this.checked,
    required this.disabled,
    required this.repeat,
  });
  final DshLocale locale;
  final bool checked, disabled;
  final int repeat;
  @override
  State<_RiskContent> createState() => _RiskContentState();
}

class _RiskContentState extends State<_RiskContent> {
  late bool _checked;

  @override
  void initState() {
    super.initState();
    _checked = widget.checked;
  }

  @override
  Widget build(BuildContext context) {
    final t = DshI18n(widget.locale);
    String text(String key) => t.t('permission.access', key);
    final description = List.filled(
      widget.repeat,
      text('confirm.description'),
    ).join(' ');
    return DshRiskDialog.content(
      title: text('confirm.title'),
      description: description,
      acknowledgeLabel: text('confirm.acknowledge'),
      cancelLabel: text('confirm.cancel'),
      closeLabel: text('close'),
      confirmLabel: text('confirm.enable'),
      acknowledged: _checked,
      onAcknowledgedChange: (next) => setState(() => _checked = next),
      disabled: widget.disabled,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: () => Navigator.of(context).pop(),
    );
  }
}
