import 'package:flutter/services.dart';

/// The DOM `KeyboardEvent.code` of a physical key, for the keys a binding may
/// name (dsh stores these names in its preference documents) and the four
/// modifier pairs the adapter needs; null for every other key.
String? domCodeOf(PhysicalKeyboardKey key) => _codes[key.usbHidUsage];

/// Whether [code] is one of the modifier keys (`ControlLeft`, `ShiftRight`, ...).
bool isModifierCode(String code) =>
    RegExp(r'^(Control|Alt|Shift|Meta)(Left|Right)$').hasMatch(code);

final Map<int, String> _codes = () {
  final map = <int, String>{};
  // Letters and digits: HID usage page 7, 0x04.. and 0x1e..
  for (var i = 0; i < 26; i++) {
    map[0x70004 + i] = 'Key${String.fromCharCode(0x41 + i)}';
  }
  for (var i = 1; i <= 9; i++) {
    map[0x7001d + i] = 'Digit$i';
  }
  map[0x70027] = 'Digit0';
  map.addAll({
    0x70028: 'Enter',
    0x70029: 'Escape',
    0x7002a: 'Backspace',
    0x7002b: 'Tab',
    0x7002c: 'Space',
    0x7002d: 'Minus',
    0x7002e: 'Equal',
    0x7002f: 'BracketLeft',
    0x70030: 'BracketRight',
    0x70031: 'Backslash',
    0x70033: 'Semicolon',
    0x70034: 'Quote',
    0x70035: 'Backquote',
    0x70036: 'Comma',
    0x70037: 'Period',
    0x70038: 'Slash',
    0x7004c: 'Delete',
    0x7004f: 'ArrowRight',
    0x70050: 'ArrowLeft',
    0x70051: 'ArrowDown',
    0x70052: 'ArrowUp',
    0x700e0: 'ControlLeft',
    0x700e1: 'ShiftLeft',
    0x700e2: 'AltLeft',
    0x700e3: 'MetaLeft',
    0x700e4: 'ControlRight',
    0x700e5: 'ShiftRight',
    0x700e6: 'AltRight',
    0x700e7: 'MetaRight',
  });
  for (var i = 1; i <= 12; i++) {
    map[0x70039 + i] = 'F$i';
  }
  for (var i = 13; i <= 24; i++) {
    map[0x70068 + (i - 13)] = 'F$i';
  }
  return map;
}();
