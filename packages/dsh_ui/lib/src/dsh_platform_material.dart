import 'package:dsh_theme/dsh_theme.dart' show ColorValue;
import 'package:flutter/widgets.dart';

import 'dsh_recipes.g.dart';
import 'dsh_shell_chrome.dart';
import 'theme_access.dart';

/// The source menu token's platform scope, kept separate from global colours.
/// Root overlays retain [ShellScope] so a macOS panel uses the same material as
/// its trigger. Other platforms continue to resolve the active theme token.
Color dshSpecificMenuFillOf(BuildContext context) {
  final theme = context.dsh;
  if (!ShellScope.of(context).darwin) {
    return theme.color('--dsw-specific-menu');
  }
  return ColorValue.parse(
    theme.brightness == Brightness.dark
        ? DshPlatformMaterialRecipe.darwinDarkMenuFill
        : DshPlatformMaterialRecipe.darwinLightMenuFill,
    where: 'darwin/--dsw-specific-menu',
  );
}
