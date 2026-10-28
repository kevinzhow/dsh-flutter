import 'dart:async';

import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/screens/pairing_screen.dart';
import 'package:dsh_flutter/src/screens/qr_scanner_screen.dart';
import 'package:dsh_flutter/src/screens/settings_route.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _QuietCamera implements QrCamera {
  const _QuietCamera();

  @override
  Widget preview(
    BuildContext context, {
    required void Function(String raw) onCode,
    required Widget Function(CameraProblem problem) problem,
  }) => const SizedBox.expand();
}

void main() {
  for (final route in ['pairing-settings', 'repair-back', 'scan-close']) {
    for (final scenario in [
      (width: 1200.0, brightness: Brightness.light, input: 'pointer'),
      (width: 1200.0, brightness: Brightness.dark, input: 'keyboard'),
      (width: 1200.0, brightness: Brightness.light, input: 'semantics'),
      (width: 390.0, brightness: Brightness.dark, input: 'pointer'),
      (width: 390.0, brightness: Brightness.light, input: 'keyboard'),
      (width: 390.0, brightness: Brightness.dark, input: 'semantics'),
    ]) {
      testWidgets(
        '$route ${scenario.width} ${scenario.input} keeps its route',
        (t) async {
          final density = scenario.width < 600 ? 2.625 : 1.0;
          t.view.devicePixelRatio = density;
          t.view.physicalSize = Size(scenario.width, 844) * density;
          t.binding.platformDispatcher.platformBrightnessTestValue =
              scenario.brightness;
          addTearDown(t.view.reset);
          addTearDown(
            t.binding.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final backend = FakeBackend();
          final controller = makeController(backend);
          addTearDown(() async {
            controller.dispose();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          });
          await t.pumpWidget(WhaleeApp(controller: controller));
          await t.pumpAndSettle();
          if (route != 'pairing-settings') {
            unawaited(
              controller.navigatorKey.currentState!.push<void>(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => route == 'repair-back'
                      ? RepairRoute(controller: controller)
                      : QrScannerScreen(
                          camera: const _QuietCamera(),
                          i18n: DshI18n(DshLocale.en),
                          openSystemSettings: () {},
                        ),
                ),
              ),
            );
            await t.pumpAndSettle();
          }
          final button = find.byKey(ValueKey(route));
          // The real native route adopts the published action profile. Its
          // surrounding native-only page has no exact Web route counterpart.
          expect(t.getSize(button), const Size(28, 28));
          expect(
            t.widget<DshButton>(button).profile,
            DshButtonProfile.iconAction,
          );
          final icon = t.widget<DshIcon>(
            find.descendant(of: button, matching: find.byType(DshIcon)),
          );
          expect(icon.size, 16);
          switch (scenario.input) {
            case 'pointer':
              await t.tap(button);
            case 'keyboard':
              final detector = t.widget<FocusableActionDetector>(
                find.descendant(
                  of: button,
                  matching: find.byType(FocusableActionDetector),
                ),
              );
              detector.focusNode!.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            case 'semantics':
              final node = t.getSemantics(button);
              expect(
                node.getSemanticsData().hasAction(SemanticsAction.tap),
                isTrue,
              );
              node.owner!.performAction(node.id, SemanticsAction.tap);
          }
          await t.pumpAndSettle();
          if (route == 'pairing-settings') {
            expect(find.byType(SettingsRoute), findsOneWidget);
            expect(controller.navigatorKey.currentState!.canPop(), isTrue);
          } else {
            expect(find.byType(RepairRoute), findsNothing);
            expect(find.byType(QrScannerScreen), findsNothing);
            expect(controller.navigatorKey.currentState!.canPop(), isFalse);
            expect(
              find.byKey(const ValueKey('pairing-connect')),
              findsOneWidget,
            );
          }
          expect(backend.connects, isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
