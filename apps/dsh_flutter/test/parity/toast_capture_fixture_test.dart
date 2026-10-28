import 'dart:convert';

import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cases/toasts.dart';
import 'helpers/toast_fixture.dart';

void main() {
  test(
    'shared helper keeps seven exact scenario props and native default hold',
    () {
      expect(jsonDecode(toastScenarioJson), toastFixtureData);
      expect(toastScenarios.keys, {
        'no-icon',
        'success',
        'warning',
        'long-warning',
        'long-no-icon',
        'whitespace',
        'unbroken-word',
      });
      final sourceDefault = toastFixtureWidget('warning', 'en', onDone: () {});
      expect(sourceDefault.hold, isNull);
      expect(sourceDefault.icon, isA<DshIcon>());
      expect(
        toastFixtureWidget('success', 'zh-CN', onDone: () {}).tone,
        DshToastTone.success,
      );
      expect(toastFixtureText('whitespace', 'en'), contains('\n'));
      expect(toastFixtureText('whitespace', 'en'), contains('\u00a0'));
    },
  );

  for (final id in toastScenarios.keys) {
    testWidgets('actual Toast scenario $id keeps raw text and glyph props', (
      t,
    ) async {
      await t.pumpWidget(
        dshTestApp(
          ToastCaptureSurface(
            id: id,
            locale: 'en',
            reduced: false,
            hold: const Duration(seconds: 60),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(
        t.widget<DshChromeText>(find.byType(DshChromeText)).semanticsLabel,
        toastFixtureText(id, 'en'),
      );
      expect(
        t.widget<DshToast>(find.byType(DshToast)).text,
        toastFixtureText(id, 'en'),
      );
      if (id == 'whitespace') {
        expect(
          t.widget<DshChromeText>(find.byType(DshChromeText)).data,
          'Synthetic spaces and line breaks with\u00a0a non-breaking space.',
        );
      }
      final expected =
          toastScenario(id)['tone'] == 'success' ||
          toastScenario(id)['icon'] == 'warning';
      expect(find.byType(DshIcon).evaluate().length, expected ? 1 : 0);
      expect(
        t.widget<DshToast>(find.byType(DshToast)).hold,
        const Duration(seconds: 60),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final theme in ['light', 'dark']) {
    for (final locale in ['en', 'zh-CN']) {
      for (final width in [800.0, 390.0]) {
        for (final density in [1.0, 2.625]) {
          testWidgets('long real Toast cap $theme/$locale/$width/$density', (
            t,
          ) async {
            t.view.physicalSize = Size(
              (width * density).ceilToDouble(),
              (600 * density).ceilToDouble(),
            );
            t.view.devicePixelRatio = density;
            addTearDown(t.view.reset);
            final ctx = ParityContext(
              caseJson: {
                'id': 'components.toast.test.$theme',
                'kind': 'toast.source',
                'theme': theme,
                'locale': locale,
                'viewport': {'width': width, 'height': 600, 'density': density},
              },
              variant: {
                'props': {
                  'scenarioId': 'long-warning',
                  'scenario': toastScenario('long-warning'),
                  'holdMs': 60000,
                  'reducedMotion': false,
                },
              },
              theme: resolveParityTheme(theme),
              fixtures: const {},
            );
            await t.pumpWidget(
              dshTestApp(
                ToastCaptureSurface(
                  id: 'long-warning',
                  locale: locale,
                  reduced: false,
                  hold: const Duration(seconds: 60),
                ),
                brightness: ctx.theme.brightness,
              ),
            );
            await t.pump();
            await t.pump();
            await t.pump(const Duration(milliseconds: 200));
            final root = t.renderObject<RenderBox>(
              find.byType(ToastCaptureSurface),
            );
            final geometry = toastGeometryProbe(t, ctx, root),
                box = (geometry['toast'] as Map)['bounds'] as List;
            final actualViewport = t.view.physicalSize.width / density;
            final cap = actualViewport - 48 < 640 ? actualViewport - 48 : 640;
            expect(box[2], closeTo(cap + 32, 1e-9));
            expect(box[1], 40);
            expect(geometry['opacity'], 1);
            expect(geometry['rowSeatCount'], 3);
            expect(geometry['reducedMotion'], false);
            expect(
              toastFixtureText('long-warning', locale),
              t.widget<DshChromeText>(find.byType(DshChromeText)).data,
            );
            await t.pumpWidget(const SizedBox());
          });
        }
      }
    }
  }
}
