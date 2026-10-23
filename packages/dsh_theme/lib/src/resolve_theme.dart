import 'dart:ui' show Brightness;

import 'dsh_theme_data.dart';
import 'official_pack.dart';
import 'theme_pack.dart';
import 'theme_settings.dart';

/// Resolves [pack] under [settings] and the platform brightness into a [DshThemeData].
///
/// * the mode follows `settings.preference` (`system` takes [platformBrightness]);
/// * the pack's `extends` chain is folded, parents looked up in [available]
///   (the built-in `official` pack is always available);
/// * each role's font stack is the user's normalized list first, then the pack's
///   built-in stack for that role.
///
/// Pure Dart: needs no running Flutter binding. Throws `ThemeException` if the
/// pack cannot be resolved.
DshThemeData resolveTheme(
  ThemePack pack,
  ThemeSettings settings,
  Brightness platformBrightness, {
  Map<String, ThemePack> available = const {},
}) {
  final resolved = pack.resolve({...builtInPacks, ...available, pack.id: pack});
  return resolveResolvedTheme(resolved, settings, platformBrightness);
}

/// Same as [resolveTheme] for a pack that is already folded.
DshThemeData resolveResolvedTheme(
  ResolvedThemePack resolved,
  ThemeSettings settings,
  Brightness platformBrightness,
) {
  final brightness = resolveBrightness(settings.preference, platformBrightness);
  final tables = resolved.tables(brightness);
  List<String> stack(FontRole role, String key) => [
    ...fontFamilyNames(settings.fontFamilies[role]),
    ...resolved.fonts[key]!,
  ];
  return DshThemeData(
    packId: resolved.id,
    brightness: brightness,
    colors: Map.unmodifiable(tables.colors),
    numbers: Map.unmodifiable(tables.numbers),
    shadows: Map.unmodifiable(tables.shadows),
    gradients: Map.unmodifiable(tables.gradients),
    typography: Map.unmodifiable(tables.typography),
    strings: Map.unmodifiable(tables.strings),
    settings: settings,
    fontStacks: Map.unmodifiable({
      FontRole.text: stack(FontRole.text, 'text'),
      FontRole.code: stack(FontRole.code, 'code'),
      FontRole.terminal: stack(FontRole.terminal, 'terminal'),
    }),
    brandFontStack: List.unmodifiable(resolved.fonts['brand']!),
  );
}
