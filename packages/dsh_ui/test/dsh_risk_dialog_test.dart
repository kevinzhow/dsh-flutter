import 'dart:async';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _acknowledgeKey = ValueKey('risk-acknowledge');
const _cancelKey = ValueKey('risk-cancel');
const _closeKey = ValueKey('risk-close');
const _confirmKey = ValueKey('risk-confirm');
const _openerKey = ValueKey('risk-test-opener');
const _title = 'Enable privileged access?';
const _description = 'Review the risks before continuing.';
const _acknowledgeLabel = 'I understand the risks';
const _cancelLabel = 'Cancel';
const _closeLabel = 'Close risk confirmation';
const _confirmLabel = 'Enable';

DshRiskDialog _risk({
  bool? acknowledged,
  ValueChanged<bool>? onAcknowledgedChange,
  bool disabled = false,
  VoidCallback? onCancel,
  VoidCallback? onConfirm,
}) => DshRiskDialog(
  title: _title,
  description: _description,
  acknowledgeLabel: _acknowledgeLabel,
  cancelLabel: _cancelLabel,
  closeLabel: _closeLabel,
  confirmLabel: _confirmLabel,
  acknowledged: acknowledged,
  onAcknowledgedChange: onAcknowledgedChange,
  disabled: disabled,
  onCancel: onCancel,
  onConfirm: onConfirm,
);

class _RiskRouteHarness {
  _RiskRouteHarness({
    this.description = _description,
    this.explicitRestore = true,
  });

  final String description;
  final bool explicitRestore;
  final opener = FocusNode(debugLabel: 'risk opener');
  final other = FocusNode(debugLabel: 'other home control');
  final results = <bool>[];

  Widget get widget => dshTestApp(
    Builder(
      builder: (context) => Column(
        children: [
          DshButton(
            key: _openerKey,
            focusNode: opener,
            onPressed: () => unawaited(
              showDshRiskDialog(
                context,
                title: _title,
                description: description,
                acknowledgeLabel: _acknowledgeLabel,
                cancelLabel: _cancelLabel,
                closeLabel: _closeLabel,
                confirmLabel: _confirmLabel,
                restoreFocus: explicitRestore ? opener : null,
              ).then(results.add),
            ),
            child: const Text('Open risk confirmation'),
          ),
          DshButton(
            focusNode: other,
            onPressed: () {},
            child: const Text('Other control'),
          ),
        ],
      ),
    ),
  );

  void dispose() {
    opener.dispose();
    other.dispose();
  }
}

void main() {
  Future<void> pumpCard(WidgetTester t, Widget card) async {
    await t.pumpWidget(dshTestApp(Center(child: card)));
    await t.pumpAndSettle();
  }

  void confirmEnabled(WidgetTester t, bool enabled) {
    expect(find.bySemanticsLabel(_confirmLabel), findsOneWidget);
    expect(
      t.getSemantics(find.byKey(_confirmKey)),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: enabled,
        hasTapAction: enabled,
      ),
    );
  }

  FocusNode buttonFocus(WidgetTester t, Key key) => t
      .widget<FocusableActionDetector>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(FocusableActionDetector),
        ),
      )
      .focusNode!;

  void returnedToOpener(WidgetTester t, _RiskRouteHarness harness) {
    expect(find.byType(DshRiskDialog), findsNothing);
    expect(harness.opener.hasPrimaryFocus, isTrue);
    expect(harness.other.hasFocus, isFalse);
    expect(
      find.descendant(
        of: find.byKey(_openerKey),
        matching: find.byKey(DshButton.focusRingKey),
      ),
      findsNothing,
    );
  }

  testWidgets(
    'controlled acknowledgement changes only when its owner accepts',
    (t) async {
      final owner = ValueNotifier(false);
      addTearDown(owner.dispose);
      final requests = <bool>[];
      var confirmed = 0;
      await pumpCard(
        t,
        ValueListenableBuilder<bool>(
          valueListenable: owner,
          builder: (_, checked, _) => _risk(
            acknowledged: checked,
            onAcknowledgedChange: requests.add,
            onConfirm: () => confirmed++,
          ),
        ),
      );
      confirmEnabled(t, false);
      await t.tap(find.byKey(_acknowledgeKey));
      await t.pumpAndSettle();
      expect(requests, [true]);
      expect(t.widget<DshCheckbox>(find.byKey(_acknowledgeKey)).value, isFalse);
      await t.tap(find.byKey(_confirmKey));
      expect(confirmed, 0);

      owner.value = true;
      await t.pumpAndSettle();
      confirmEnabled(t, true);
      await t.tap(find.byKey(_confirmKey));
      expect(confirmed, 1);
      await t.tap(find.byKey(_acknowledgeKey));
      await t.pumpAndSettle();
      expect(requests, [true, false]);
      expect(t.widget<DshCheckbox>(find.byKey(_acknowledgeKey)).value, isTrue);
      confirmEnabled(t, true);

      owner.value = false;
      await t.pumpAndSettle();
      confirmEnabled(t, false);
      await t.tap(find.byKey(_confirmKey));
      expect(confirmed, 1);
    },
  );

  for (final checked in [false, true]) {
    testWidgets(
      'disabled risk with acknowledged=$checked cannot change or confirm',
      (t) async {
        final requests = <bool>[];
        var confirmed = 0;
        var canceled = 0;
        await pumpCard(
          t,
          _risk(
            acknowledged: checked,
            onAcknowledgedChange: requests.add,
            disabled: true,
            onConfirm: () => confirmed++,
            onCancel: () => canceled++,
          ),
        );
        final checkbox = t.getSemantics(find.byKey(_acknowledgeKey));
        expect(
          checkbox,
          isSemantics(
            label: _acknowledgeLabel,
            hasCheckedState: true,
            isChecked: checked,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
            hasFocusAction: false,
          ),
        );
        confirmEnabled(t, false);
        await t.tap(find.byKey(_acknowledgeKey));
        await t.tap(find.byKey(_confirmKey));
        await t.pumpAndSettle();
        expect(requests, isEmpty);
        expect(confirmed, 0);
        expect(
          t.widget<DshCheckbox>(find.byKey(_acknowledgeKey)).value,
          checked,
        );
        await t.tap(find.byKey(_cancelKey));
        await t.tap(find.byKey(_closeKey));
        expect(canceled, 2);
      },
    );
  }

  testWidgets(
    'named Cancel and Close activate cancellation from the keyboard',
    (t) async {
      var canceled = 0;
      await pumpCard(t, _risk(onCancel: () => canceled++));
      final checkbox = t.getSemantics(find.byKey(_acknowledgeKey));
      expect(checkbox, isSemantics(isFocused: true));
      final close = t.getSemantics(find.byKey(_closeKey));
      expect(
        close,
        isSemantics(
          label: _closeLabel,
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel(_cancelLabel), findsOneWidget);
      expect(buttonFocus(t, _cancelKey).hasPrimaryFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(canceled, 1);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pumpAndSettle();
      expect(buttonFocus(t, _closeKey).hasPrimaryFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(canceled, 2);
    },
  );

  testWidgets('the route returns true only after explicit acknowledgement', (
    t,
  ) async {
    final harness = _RiskRouteHarness();
    addTearDown(harness.dispose);
    await t.pumpWidget(harness.widget);
    await t.pumpAndSettle();
    harness.other.requestFocus();
    await t.pumpAndSettle();
    await t.tap(find.byKey(_openerKey));
    await t.pumpAndSettle();
    expect(
      t.getSemantics(find.byKey(_acknowledgeKey)),
      isSemantics(isFocused: true, isChecked: false),
    );
    expect(find.byKey(const ValueKey('dsh-checkbox-focus-ring')), findsNothing);
    confirmEnabled(t, false);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.tap(find.byKey(_confirmKey));
    await t.pumpAndSettle();
    expect(harness.results, isEmpty);
    confirmEnabled(t, false);

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(
      t.getSemantics(find.byKey(_acknowledgeKey)),
      isSemantics(isChecked: true),
    );
    confirmEnabled(t, true);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(buttonFocus(t, _confirmKey).hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(harness.results, [true]);
    returnedToOpener(t, harness);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final dismissal in ['cancel', 'close', 'Escape']) {
    testWidgets(
      'the route answers false for $dismissal and restores its opener without a ring',
      (t) async {
        final harness = _RiskRouteHarness(explicitRestore: false);
        addTearDown(harness.dispose);
        await t.pumpWidget(harness.widget);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        expect(harness.opener.hasPrimaryFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(find.byType(DshRiskDialog), findsOneWidget);
        expect(
          find.byKey(const ValueKey('dsh-checkbox-focus-ring')),
          findsNothing,
        );
        if (dismissal == 'Escape') {
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await t.tap(
            find.byKey(dismissal == 'cancel' ? _cancelKey : _closeKey),
          );
        }
        await t.pumpAndSettle();
        expect(harness.results, [false]);
        returnedToOpener(t, harness);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets(
    'long actual risk content scrolls its header while actions stay reachable',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 360);
      addTearDown(t.view.reset);
      final harness = _RiskRouteHarness(
        description: List.generate(
          70,
          (i) => 'Risk $i: review access to your workspace.',
        ).join('\n'),
      );
      addTearDown(harness.dispose);
      await t.pumpWidget(harness.widget);
      await t.pumpAndSettle();
      await t.tap(find.byKey(_openerKey));
      await t.pumpAndSettle();
      final content = find.byKey(const ValueKey('risk-content'));
      final scrollable = find.descendant(
        of: content,
        matching: find.byType(Scrollable),
      );
      final position = t.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      // Start at the top even if platform autofocus revealed the last control.
      await t.drag(content, const Offset(0, 10000));
      await t.pumpAndSettle();
      expect(position.pixels, 0);
      final headerTop = t
          .getTopLeft(find.byKey(const ValueKey('risk-header')))
          .dy;
      final warningTop = t
          .getTopLeft(find.byKey(const ValueKey('risk-description')))
          .dy;
      final footer = t.getRect(find.byKey(const ValueKey('risk-footer')));
      expect(footer.top, greaterThanOrEqualTo(0));
      expect(footer.bottom, lessThanOrEqualTo(360));
      expect(find.byKey(_cancelKey).hitTestable(), findsOneWidget);
      expect(find.byKey(_confirmKey).hitTestable(), findsOneWidget);

      await t.drag(content, const Offset(0, -180));
      await t.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(
        t.getTopLeft(find.byKey(const ValueKey('risk-header'))).dy,
        lessThan(headerTop),
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('risk-description'))).dy,
        lessThan(warningTop),
      );
      expect(t.getRect(find.byKey(const ValueKey('risk-footer'))), footer);
      expect(find.byKey(_cancelKey).hitTestable(), findsOneWidget);
      expect(find.byKey(_confirmKey).hitTestable(), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(_acknowledgeKey),
        240,
        scrollable: scrollable,
      );
      await t.pumpAndSettle();
      expect(find.byKey(_acknowledgeKey).hitTestable(), findsOneWidget);
      await t.tap(find.byKey(_acknowledgeKey));
      await t.pumpAndSettle();
      expect(t.getRect(find.byKey(const ValueKey('risk-footer'))), footer);
      expect(find.byKey(_confirmKey).hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(_confirmKey));
      await t.pumpAndSettle();
      expect(harness.results, [true]);
      returnedToOpener(t, harness);
    },
  );
}
