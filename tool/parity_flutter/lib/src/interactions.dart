import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applies the manifest's interaction steps (the Flutter counterpart of `applyInteractions` in
/// tool/parity-web/capture.mjs). Real pointer and key events; a `press` stays held until
/// [ParityInteractions.release].
class ParityInteractions {
  /// Creates an interpreter bound to [tester].
  ParityInteractions(this.tester);

  /// The test driver.
  final WidgetTester tester;

  TestGesture? _mouse;
  TestGesture? _held;

  Finder _target(Map<String, dynamic> step) {
    final id = step['target'] as String;
    final finder = find.byKey(ValueKey<String>(id));
    if (finder.evaluate().isEmpty) {
      throw StateError('interaction target "$id" not found');
    }
    return finder.first;
  }

  Future<TestGesture> _pointer() async {
    var mouse = _mouse;
    if (mouse == null) {
      mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      _mouse = mouse;
    }
    return mouse;
  }

  /// Runs [steps] in order.
  Future<void> apply(List<dynamic> steps) async {
    for (final raw in steps.cast<Map<String, dynamic>>()) {
      switch (raw['type']) {
        case 'hover':
          final mouse = await _pointer();
          await mouse.moveTo(tester.getCenter(_target(raw)));
        case 'press':
          final mouse = await _pointer();
          await mouse.moveTo(tester.getCenter(_target(raw)));
          await mouse.down(tester.getCenter(_target(raw)));
          _held = mouse;
        case 'click':
          await tester.tap(_target(raw), warnIfMissed: false);
        case 'tab':
          for (var i = 0; i < ((raw['count'] as num?) ?? 1); i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          }
        case 'focus-by-tab':
          final target = tester.element(_target(raw));
          var reached = false;
          for (var i = 0; i < 40 && !reached; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            final focused = FocusManager.instance.primaryFocus?.context;
            if (focused == target) reached = true;
            focused?.visitAncestorElements((element) {
              if (element == target) {
                reached = true;
                return false;
              }
              return true;
            });
          }
          if (!reached)
            throw StateError('keyboard focus did not reach ${raw['target']}');
        case 'type':
          await tester.enterText(
            find
                .descendant(
                  of: _target(raw),
                  matching: find.byType(EditableText),
                )
                .first,
            raw['text'] as String,
          );
        case 'set-scroll':
          final scrollable = find.descendant(
            of: _target(raw),
            matching: find.byType(Scrollable),
          );
          if (scrollable.evaluate().length != 1) {
            throw StateError(
              'set-scroll requires one scrollable under ${raw['target']}',
            );
          }
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(
            (raw['offset'] as num).toDouble().clamp(
              0,
              position.maxScrollExtent,
            ),
          );
        case 'wait':
          await tester.pump(Duration(milliseconds: (raw['ms'] as num).toInt()));
        default:
          throw StateError('unknown interaction $raw');
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// Releases a held `press` so no pointer stays down after the capture.
  Future<void> release() async {
    final held = _held;
    _held = null;
    if (held != null) {
      await held.up();
      await tester.pump();
    }
  }
}
