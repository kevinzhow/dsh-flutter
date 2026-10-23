import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

/// The resolved theme contract of the ambient `Theme`.
///
/// Every dsh_ui widget (and every feature) reads colours, radii and text
/// styles through this; none looks at which pack produced them.
extension DshThemeContext on BuildContext {
  DshThemeData get dsh {
    final theme = Theme.of(this).extension<DshThemeData>();
    if (theme == null) {
      throw FlutterError(
        'A dsh widget needs a DshThemeData in Theme.of(context).extensions. '
        'Build one with resolveTheme() and pass it as ThemeData(extensions: [...]).',
      );
    }
    return theme;
  }
}

/// Layout rhythm shared by the app. dsh's stylesheets keep paddings and gaps in
/// component sheets rather than in the token contract (like `DshButton`'s
/// heights), so the Flutter client names them once here instead of scattering
/// literals through feature code.
abstract final class DshSpace {
  /// 4: icon gaps.
  static const double xs = 4;

  /// 8: tight stacks.
  static const double sm = 8;

  /// 12: card padding.
  static const double md = 12;

  /// 16: screen padding.
  static const double lg = 16;

  /// 24: section gaps.
  static const double xl = 24;

  /// Minimum touch target on phones.
  static const double touch = 44;

  /// Widest readable column of the conversation on tablets and desktops.
  static const double readableWidth = 760;
}

/// Width of dsh's `0.5px` hairlines (card borders, dividers) as Chromium paints
/// them: whole device pixels, two at the 2x density of the parity captures.
const double dshHairline = 1.0;
