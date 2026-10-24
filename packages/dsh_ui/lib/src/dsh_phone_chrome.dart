import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_shell_icons.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Below 600 logical pixels the left sidebar is a modal drawer (Whalee's phone
/// design: the one place it departs from dsh web, which keeps an icon rail).
const double phoneDrawerBreakpoint = 600;

/// The drawer's width: 85% of the window, at most this.
const double phoneDrawerMaxWidth = 320;

/// What a phone page needs from its frame: opening the drawer and starting a
/// Session. The frame provides it only on a phone; a page that finds none draws
/// the desktop chrome.
class PhoneChrome extends InheritedWidget {
  const PhoneChrome({
    super.key,
    required this.openDrawer,
    required this.newSession,
    required this.menuLabel,
    required this.newSessionLabel,
    required super.child,
  });

  final VoidCallback openDrawer;
  final VoidCallback newSession;
  final String menuLabel;
  final String newSessionLabel;

  /// The phone chrome of [context], or null on a desktop window.
  static PhoneChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhoneChrome>();

  @override
  bool updateShouldNotify(PhoneChrome old) =>
      menuLabel != old.menuLabel || newSessionLabel != old.newSessionLabel;
}

/// Three bars: the menu glyph (dsh has no menu icon; its sidebar glyph is the
/// panel the drawer replaces).
const DshIconData _menuGlyph = DshIconData(
  viewBox: 18,
  size: 18,
  strokeWidth: 1.4,
  shapes: [DshIconShape('M3 5h12M3 9h12M3 13h12', cap: DshIconCap.round)],
);

/// The phone top bar: the menu button that opens the drawer, the Session title
/// and the new-session button, 52px, over the page.
class PhoneTopBar extends StatelessWidget {
  const PhoneTopBar({super.key, required this.title, required this.chrome});

  final String title;
  final PhoneChrome chrome;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    Widget button(Key key, DshIconData icon, String label, VoidCallback tap) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: DshIcon(icon, size: 20, color: theme.labelPrimary),
              ),
            ),
          ),
        );
    return DshContainer(
      key: const ValueKey('phone-top-bar'),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          button(
            const ValueKey('phone-menu'),
            _menuGlyph,
            chrome.menuLabel,
            chrome.openDrawer,
          ),
          Expanded(
            child: Center(
              child: DshChromeText(
                title,
                key: const ValueKey('phone-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme
                    .textStyle('--dsw-font-base-strong-16')
                    .copyWith(color: theme.labelPrimary, height: 24 / 16),
              ),
            ),
          ),
          button(
            const ValueKey('phone-new-session'),
            DshShellIcons.newChatRegular,
            chrome.newSessionLabel,
            chrome.newSession,
          ),
        ],
      ),
    );
  }
}
