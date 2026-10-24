import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// A key of the phone key bar.
enum TerminalBarKey { escape, tab, ctrl, up, down, left, right }

/// The control code a Ctrl-modified character stands for, or null when the
/// character has none (only `@`, `A`-`Z`, `[`, `\`, `]`, `^`, `_` and the
/// lower-case letters do).
String? controlCharacterFor(String data) {
  if (data.length != 1) return null;
  final c = data.codeUnitAt(0);
  if (c >= 0x61 && c <= 0x7a) return String.fromCharCode(c - 0x60);
  if (c >= 0x40 && c <= 0x5f) return String.fromCharCode(c - 0x40);
  return null;
}

/// The small key bar for phones: the keys a soft keyboard lacks (Escape, Tab,
/// a sticky Ctrl, the arrows). The bar only reports key presses; the screen
/// turns them into terminal input.
class TerminalKeyBar extends StatelessWidget {
  const TerminalKeyBar({
    super.key,
    required this.i18n,
    required this.ctrlArmed,
    required this.onKey,
  });

  final DshI18n i18n;

  /// Ctrl was pressed and waits for the next character.
  final bool ctrlArmed;
  final void Function(TerminalBarKey key) onKey;

  static const _labels = {
    TerminalBarKey.escape: 'Esc',
    TerminalBarKey.tab: 'Tab',
    TerminalBarKey.ctrl: 'Ctrl',
    TerminalBarKey.up: '↑',
    TerminalBarKey.down: '↓',
    TerminalBarKey.left: '←',
    TerminalBarKey.right: '→',
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DecoratedBox(
      key: const ValueKey('terminal-key-bar'),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-bg-layer-1'),
        border: Border(
          top: BorderSide(
            color: theme.color('--dsw-alias-border-l4'),
            width: dshHairline,
          ),
        ),
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            for (final key in TerminalBarKey.values)
              Expanded(
                child: _KeyButton(
                  key: ValueKey('terminal-key-${key.name}'),
                  label: _labels[key]!,
                  active: key == TerminalBarKey.ctrl && ctrlArmed,
                  onTap: () => onKey(key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: DecoratedBox(
            decoration: active
                ? context.dshOutlined(
                    theme.radiusSm,
                    fill: theme.color('--dsw-alias-state-business-primary'),
                  )
                : const BoxDecoration(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: DshChromeText(
                label,
                style: theme
                    .textStyle('--dsw-font-xs-13')
                    .copyWith(
                      color: active
                          ? theme.labelPrimaryForeground
                          : theme.labelPrimary,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
