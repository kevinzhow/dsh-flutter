import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/widgets.dart';

/// Resolves the official pack in the requested mode (`light` or `dark`).
///
/// The mode is explicit per capture; the platform brightness never decides. Unknown names throw.
DshThemeData resolveParityTheme(String name) {
  final preference = switch (name) {
    'light' => ThemePreference.light,
    'dark' => ThemePreference.dark,
    _ => throw ArgumentError.value(name, 'name', 'unknown parity theme'),
  };
  // The platform brightness argument is deliberately the opposite of the request for `dark`, so a
  // theme that silently followed the platform would be caught by [verifyCapturedTheme].
  return resolveTheme(
    officialPack,
    ThemeSettings(preference: preference),
    name == 'dark' ? Brightness.light : Brightness.dark,
  );
}

/// Theme self-test of one capture: the theme the live widget tree resolves must be the requested
/// one (official pack, requested brightness), and the frame's fill must really be that theme's
/// `--dsw-alias-bg-base`. Throws a [StateError] naming the mismatch.
void verifyCapturedTheme({
  required String requested,
  required DshThemeData? inTree,
  required DshThemeData expected,
  required Color? framePixel,
}) {
  if (inTree == null) {
    throw StateError('theme self-test: no DshThemeData in the widget tree');
  }
  if (inTree.packId != officialPackId) {
    throw StateError(
      'theme self-test: pack ${inTree.packId}, expected $officialPackId',
    );
  }
  if (inTree.brightness.name != requested) {
    throw StateError(
      'theme self-test: tree is ${inTree.brightness.name}, requested $requested',
    );
  }
  if (framePixel != null) {
    int channel(double v) => (v * 255).round();
    final want = expected.bgBase;
    final diff = [
      (framePixel.r - want.r).abs(),
      (framePixel.g - want.g).abs(),
      (framePixel.b - want.b).abs(),
    ].map((d) => channel(d)).reduce((a, b) => a > b ? a : b);
    if (diff > 1) {
      throw StateError(
        'theme self-test: captured frame pixel $framePixel is not the '
        '$requested bg-base $want',
      );
    }
  }
}
