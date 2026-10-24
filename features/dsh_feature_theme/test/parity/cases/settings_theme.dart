// dsh's theme settings rows (ui-theme) with the Flutter widgets of this feature, over the same
// props as the React host (tool/parity-ext/build-settings.py):
//   settings.appearance  AppearanceRow
//   settings.font        FontSettingsGroup (the region opens by a real click on `font-expander`)
import 'package:dsh_feature_theme/dsh_feature_theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart' show find;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshColumnEnd;

ThemeSettingsService _service(Map<String, dynamic> props) {
  final sizes = (props['fontSizes'] as Map?)?.cast<String, dynamic>();
  final families = (props['fontFamilies'] as Map?)?.cast<String, dynamic>();
  final settings = ThemeSettings(
    preference:
        ThemePreference.tryParse(props['preference']) ?? ThemePreference.system,
    fontSize: (sizes?['text'] as num?)?.toInt() ?? 14,
    codeFontSize: (sizes?['code'] as num?)?.toInt() ?? 11,
    terminalFontSize: (sizes?['terminal'] as num?)?.toInt() ?? 13,
    textFontFamily: families?['text'] as String? ?? '',
    codeFontFamily: families?['code'] as String? ?? '',
    terminalFontFamily: families?['terminal'] as String? ?? '',
  );
  final form = FakeConfigForm(
    ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: settings.toJson(),
      base: ThemeSettings().toJson(),
      user: const {},
      revision: 0,
      writable: true,
    ),
  );
  return ThemeSettingsService(host: form);
}

DshI18n _i18n(ParityContext ctx) => DshI18n(DshLocale.fromTag(ctx.locale));

final Map<String, ParityCase> settingsThemeCases = {
  'settings.appearance': ParityCase(
    widgets: const ['dsh_feature_theme:AppearanceRow'],
    build: (ctx) => ParityStack(
      layout: ctx.layout,
      children: [AppearanceRow(service: _service(ctx.props), i18n: _i18n(ctx))],
    ),
  ),
  'settings.font': ParityCase(
    widgets: const ['dsh_feature_theme:FontSettingsGroup'],
    notes:
        'After the expander click the pointer rests on it, as the browser\'s '
        'does, so its hover wash shows.',
    interact: (tester, ctx) async {
      final expander = find.byKey(const ValueKey<String>('font-expander'));
      if (expander.evaluate().isEmpty) return;
      if (find
          .byKey(const ValueKey<String>('font-group-open'))
          .evaluate()
          .isEmpty) {
        return;
      }
      // A variant that hovers elsewhere has its own pointer already.
      final steps = (ctx.variant['interactions'] as List?) ?? const [];
      if (steps.any((s) => (s as Map)['type'] == 'hover')) return;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(expander));
      await tester.pump(const Duration(milliseconds: 50));
    },
    build: (ctx) => ParityStack(
      layout: ctx.layout,
      children: [
        // dsh's CSS strips the separator of the group's last row when the group
        // is the last child of its parent, which it is alone in the frame.
        DshColumnEnd(
          child: FontSettingsGroup(
            service: _service(ctx.props),
            i18n: _i18n(ctx),
          ),
        ),
      ],
    ),
  ),
};
