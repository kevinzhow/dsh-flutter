import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';

/// Appearance and language: the theme preference (system, light, dark) and the
/// two locales dsh ships.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final i18n = controller.i18n;
    String a(String key) => i18n.t(appNamespace, key);
    Widget row(String title, List<Widget> choices) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme
              .textStyle('--dsw-font-xs-strong-13')
              .copyWith(color: theme.labelSecondary),
        ),
        const SizedBox(height: DshSpace.sm),
        Wrap(spacing: DshSpace.sm, runSpacing: DshSpace.sm, children: choices),
      ],
    );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(DshSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(a('settings.theme'), [
              for (final p in ThemePreference.values)
                DshButton(
                  key: ValueKey('theme-${p.name}'),
                  variant: controller.themePreference == p
                      ? DshButtonVariant.primary
                      : DshButtonVariant.outline,
                  onPressed: () => controller.setThemePreference(p),
                  child: Text(a('settings.theme.${p.name}')),
                ),
            ]),
            const SizedBox(height: DshSpace.lg),
            row(a('settings.language'), [
              for (final l in DshLocale.values)
                DshButton(
                  key: ValueKey('locale-${l.name}'),
                  variant: controller.locale == l
                      ? DshButtonVariant.primary
                      : DshButtonVariant.outline,
                  onPressed: () => controller.setLocale(l),
                  child: Text(a('settings.language.${l.name}')),
                ),
            ]),
            if (controller.phase == ConnectionPhase.connected) ...[
              const SizedBox(height: DshSpace.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DshButton(
                  key: const ValueKey('settings-disconnect'),
                  variant: DshButtonVariant.outline,
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await controller.disconnect();
                  },
                  child: Text(a('sessions.disconnect')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
