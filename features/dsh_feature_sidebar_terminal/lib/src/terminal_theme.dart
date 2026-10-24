import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart' as xterm;

/// The emulator's colours: background, default text, cursor and selection come
/// from the DSH theme (`--dsw-alias-bg-base`, `--dsw-alias-label-primary`), as
/// dsh's `TerminalTheme` takes them, and the sixteen ANSI colours are the
/// emulator's own defaults, which dsh leaves alone (xterm.js's palette).
xterm.TerminalTheme terminalThemeOf(DshThemeData theme) {
  final foreground = theme.labelPrimary;
  final background = theme.bgBase;
  return xterm.TerminalTheme(
    cursor: foreground,
    // xterm.js paints the selection in the text colour with the background as
    // its text; the Flutter emulator draws the selection as a fill under the
    // text, so it is the text colour at a readable strength.
    selection: foreground.withValues(alpha: 0.3),
    foreground: foreground,
    background: background,
    black: const Color(0xFF2E3436),
    red: const Color(0xFFCC0000),
    green: const Color(0xFF4E9A06),
    yellow: const Color(0xFFC4A000),
    blue: const Color(0xFF3465A4),
    magenta: const Color(0xFF75507B),
    cyan: const Color(0xFF06989A),
    white: const Color(0xFFD3D7CF),
    brightBlack: const Color(0xFF555753),
    brightRed: const Color(0xFFEF2929),
    brightGreen: const Color(0xFF8AE234),
    brightYellow: const Color(0xFFFCE94F),
    brightBlue: const Color(0xFF729FCF),
    brightMagenta: const Color(0xFFAD7FA8),
    brightCyan: const Color(0xFF34E2E2),
    brightWhite: const Color(0xFFEEEEEC),
    searchHitBackground: const Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: const Color(0xFF31FF26),
    searchHitForeground: const Color(0xFF000000),
  );
}

/// The emulator's text style: the user's terminal font size and family list
/// (Settings), ahead of the built-in monospace stack.
xterm.TerminalStyle terminalStyleOf(DshThemeData theme) {
  final text = theme.terminalTextStyle;
  return xterm.TerminalStyle(
    fontSize: text.fontSize ?? 13,
    // xterm.js lays rows out at the font's natural height; the Flutter
    // emulator needs an explicit multiple, 1.2 as dsh's own terminal style.
    height: text.height ?? 1.2,
    fontFamily: text.fontFamily ?? 'monospace',
    fontFamilyFallback: [
      ...?text.fontFamilyFallback,
      'ui-monospace',
      'SFMono-Regular',
      'Menlo',
      'Consolas',
      'monospace',
    ],
  );
}
