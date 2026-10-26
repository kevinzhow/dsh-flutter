import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> checkboxFamilyCases = {
  'checkbox-family.risk': ParityCase(
    widgets: const ['dsh_ui:DshRiskDialog', 'dsh_ui:DshCheckbox'],
    framed: false,
    build: (ctx) {
      final t = DshI18n(DshLocale.fromTag(ctx.locale));
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DshRiskDialog(
            title: t.t('permission.access', 'confirm.title'),
            description: t.t('permission.access', 'confirm.description'),
            acknowledgeLabel: t.t('permission.access', 'confirm.acknowledge'),
            cancelLabel: t.t('permission.access', 'confirm.cancel'),
            closeLabel: t.t('permission.access', 'close'),
            confirmLabel: t.t('permission.access', 'confirm.enable'),
          ),
        ),
      );
    },
  ),
  'checkbox-family.model': ParityCase(
    widgets: const ['dsh_ui:DshCheckbox'],
    notes: 'The source ModelInputTypes context is rendered with the shared Flutter checkbox; the model editor is not yet wired to this atom.',
    build: (ctx) => _ModelFixture(
      width: (ctx.props['width'] as num).toDouble(),
      checked: ctx.props['checked'] as bool,
      disabled: ctx.props['disabled'] as bool,
      locale: DshLocale.fromTag(ctx.locale),
    ),
  ),
};

class _ModelFixture extends StatefulWidget {
  const _ModelFixture({
    required this.width,
    required this.checked,
    required this.disabled,
    required this.locale,
  });
  final double width;
  final bool checked, disabled;
  final DshLocale locale;

  @override
  State<_ModelFixture> createState() => _ModelFixtureState();
}

class _ModelFixtureState extends State<_ModelFixture> {
  late bool text, image;

  @override
  void initState() {
    super.initState();
    text = true;
    image = widget.checked;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = DshI18n(widget.locale);
    final theme = context.dsh;
    return SizedBox(
      key: const ValueKey('model-checkbox-area'),
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DshChromeText(
            i18n.t('settings.models', 'modelInputTypes'),
            style: theme
                .fixedTextStyle(size: 12, line: 18)
                .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                parityItem(
                  'model-text',
                  DshCheckbox(
                    value: text,
                    onChanged: widget.disabled || !image
                        ? null
                        : (next) => setState(() => text = next),
                    label: i18n.t('settings.models', 'modelInputText'),
                  ),
                ),
                parityItem(
                  'model-image',
                  DshCheckbox(
                    value: image,
                    onChanged: widget.disabled || !text
                        ? null
                        : (next) => setState(() => image = next),
                    label: i18n.t('settings.models', 'modelInputImage'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
