import 'dart:async';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _openerKey = ValueKey('long-risk-opener');
const _contentKey = ValueKey('risk-content');
const _acknowledgeKey = ValueKey('risk-acknowledge');
const _cancelKey = ValueKey('risk-cancel');
const _closeKey = ValueKey('risk-close');
const _footerKey = ValueKey('risk-footer');
const _checkboxRingKey = ValueKey('dsh-checkbox-focus-ring');

// Same English warning repeated six times as the actual source long-risk
// probe. Assert the measured maximum rather than a font-dependent pixel count.
const _warning =
    'Full access reduces confirmation steps and lets the agent perform more '
    'actions directly, including sensitive operations, file changes, or external '
    'commands. Only use it when you trust the current task.';

void main() {
  FocusNode focusOf(WidgetTester tester, Key key) => tester
      .widget<FocusableActionDetector>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(FocusableActionDetector),
        ),
      )
      .focusNode!;

  Future<void> previousFocus(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'long risk entry reveals its focused acknowledgement and keyboard traversal returns to Close',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 320);
      addTearDown(tester.view.reset);
      final opener = FocusNode(debugLabel: 'long risk opener');
      final other = FocusNode(debugLabel: 'other home control');
      addTearDown(opener.dispose);
      addTearDown(other.dispose);
      final results = <bool>[];
      await tester.pumpWidget(
        dshTestApp(
          Builder(
            builder: (context) => Column(
              children: [
                DshButton(
                  key: _openerKey,
                  focusNode: opener,
                  onPressed: () => unawaited(
                    showDshRiskDialog(
                      context,
                      title: 'Enable Full access?',
                      description: List.filled(6, _warning).join(' '),
                      acknowledgeLabel:
                          'I understand the risks and want to continue',
                      cancelLabel: 'Cancel',
                      closeLabel: 'Close risk confirmation',
                      confirmLabel: 'Enable',
                      restoreFocus: opener,
                    ).then(results.add),
                  ),
                  child: const Text('Open long risk confirmation'),
                ),
                DshButton(
                  focusNode: other,
                  onPressed: () {},
                  child: const Text('Other control'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      other.requestFocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_openerKey));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(_contentKey),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final checkbox = focusOf(tester, _acknowledgeKey);
      final footer = tester.getRect(find.byKey(_footerKey));
      expect(checkbox.hasPrimaryFocus, isTrue);
      expect(position.maxScrollExtent, greaterThan(0));
      // No drag, wheel, ensureVisible or scroll-controller mutation precedes
      // this assertion: the source's preferred focus itself reveals the end.
      expect(
        position.pixels,
        closeTo(position.maxScrollExtent, 0.01),
        reason:
            'Initial autofocus must reveal the trailing acknowledgement at the '
            'actual maximum scroll offset without explicit scrolling.',
      );
      final viewport = tester.getRect(find.byKey(_contentKey));
      final input = tester.getRect(
        find.byKey(const ValueKey('dsh-checkbox-box')),
      );
      expect(input.top, greaterThanOrEqualTo(viewport.top));
      expect(input.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(find.byKey(_checkboxRingKey), findsNothing);
      expect(
        tester.widget<DshCheckbox>(find.byKey(_acknowledgeKey)).value,
        isFalse,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DshCheckbox>(find.byKey(_acknowledgeKey)).value,
        isTrue,
      );
      expect(checkbox.hasPrimaryFocus, isTrue);
      expect(find.byKey(_checkboxRingKey), findsNothing);
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(focusOf(tester, _cancelKey).hasPrimaryFocus, isTrue);
      expect(tester.getRect(find.byKey(_footerKey)), footer);
      await previousFocus(tester);
      expect(checkbox.hasPrimaryFocus, isTrue);
      expect(find.byKey(_checkboxRingKey), findsOneWidget);
      await previousFocus(tester);
      expect(
        focusOf(tester, _closeKey).hasPrimaryFocus,
        isTrue,
        reason:
            'Primary focus after reverse traversal: ${FocusManager.instance.primaryFocus}',
      );
      expect(position.pixels, 0);
      expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byKey(_footerKey)), footer);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DshRiskDialog), findsNothing);
      expect(results, [false]);
      expect(opener.hasPrimaryFocus, isTrue);
      expect(other.hasFocus, isFalse);
      expect(
        find.descendant(
          of: find.byKey(_openerKey),
          matching: find.byKey(DshButton.focusRingKey),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
