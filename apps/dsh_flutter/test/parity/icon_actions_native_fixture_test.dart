import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'icon_actions_main.dart';

Future<void> _shiftTab(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadPinnedFontsFromEnvironment);
  for (final size in [const Size(1280, 720), const Size(390, 844)]) {
    for (final brightness in Brightness.values) {
      testWidgets('actual native icon routes $size ${brightness.name}', (
        t,
      ) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(IconActionsNativeApp(brightness: brightness));
        await t.pumpAndSettle();
        Finder action(String key) => find.byKey(ValueKey(key));
        void counters(int settings, int back, int close) => expect(
          find.text(
            'Native actions: settings=$settings back=$back close=$close',
          ),
          findsOneWidget,
        );
        void route(String route) => expect(
          find.text('Native route: $route; network=0'),
          findsOneWidget,
        );
        void geometry(Finder button) {
          expect(t.getSize(button), const Size(28, 28));
          final data = t.getSemantics(button).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(
            t.widget<DshButton>(button).profile,
            DshButtonProfile.iconAction,
          );
        }

        void focused(Finder button) {
          final owner = t.getSemantics(button);
          final nodes = <SemanticsNode>[];
          void visit(SemanticsNode node) {
            if (node.flagsCollection.isFocused == Tristate.isTrue) {
              nodes.add(node);
            }
            node.visitChildren((child) {
              visit(child);
              return true;
            });
          }

          visit(owner);
          expect(nodes, hasLength(1));
          expect(nodes.single.rect, owner.rect);
          expect(
            nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }

        final settings = action('pairing-settings');
        geometry(settings);
        final measured = <String, Rect>{'settings': t.getRect(settings)};
        counters(0, 0, 0);
        route('pairing');
        await t.tap(settings);
        await t.pumpAndSettle();
        counters(1, 0, 0);
        route('settings');
        await t.sendKeyEvent(LogicalKeyboardKey.f8);
        await t.pumpAndSettle();
        await _shiftTab(t);
        expect(
          find.descendant(
            of: settings,
            matching: find.byKey(DshButton.focusRingKey),
          ),
          findsOneWidget,
        );
        focused(settings);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        counters(2, 0, 0);
        route('settings');
        await t.sendKeyEvent(LogicalKeyboardKey.f8);
        await t.pumpAndSettle();

        await t.sendKeyEvent(LogicalKeyboardKey.f6);
        await t.pumpAndSettle();
        final back = action('repair-back');
        geometry(back);
        measured['back'] = t.getRect(back);
        route('repair');
        await t.tap(back);
        await t.pumpAndSettle();
        counters(2, 1, 0);
        route('pairing');
        await t.sendKeyEvent(LogicalKeyboardKey.f6);
        await t.pumpAndSettle();
        await _shiftTab(t);
        expect(
          find.descendant(
            of: back,
            matching: find.byKey(DshButton.focusRingKey),
          ),
          findsOneWidget,
        );
        focused(back);
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await t.pumpAndSettle();
        counters(2, 2, 0);
        route('pairing');

        await t.sendKeyEvent(LogicalKeyboardKey.f7);
        await t.pumpAndSettle();
        final close = action('scan-close');
        geometry(close);
        measured['close'] = t.getRect(close);
        route('scanner');
        await t.tap(close);
        await t.pumpAndSettle();
        counters(2, 2, 1);
        route('pairing');
        await t.sendKeyEvent(LogicalKeyboardKey.f7);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        expect(
          find.descendant(
            of: close,
            matching: find.byKey(DshButton.focusRingKey),
          ),
          findsOneWidget,
        );
        focused(close);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        counters(2, 2, 2);
        route('pairing');

        final status = find.text('Native actions: settings=2 back=2 close=2');
        measured['status'] = t.getRect(status);
        debugPrint(
          'ICON_NATIVE_GEOMETRY ${jsonEncode({
            'viewport': [size.width, size.height],
            'theme': brightness.name,
            for (final e in measured.entries) e.key: [e.value.left, e.value.top, e.value.right, e.value.bottom],
          })}',
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
      });
    }
  }
}
