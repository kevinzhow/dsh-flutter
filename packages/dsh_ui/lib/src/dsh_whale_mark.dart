import 'package:flutter/widgets.dart';

import 'theme_access.dart';

/// Whalee's brand mark: the 🐳 emoji in the platform's own emoji font, fitted
/// to the box dsh's DeepSeek mark takes (24px in the sidebar, 34px in the hero).
/// An intended difference from dsh web (docs/parity.md, "Icons"): Whalee uses
/// no DeepSeek brand asset.
class DshWhaleMark extends StatelessWidget {
  const DshWhaleMark({super.key, required this.size});

  /// Edge of the box the glyph is fitted into.
  final double size;

  /// The emoji, as one string so a test or a screen reader names it.
  static const String glyph = '\u{1F433}';

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: FittedBox(
          child: Text(
            glyph,
            key: const ValueKey('whale-mark'),
            textScaler: TextScaler.noScaling,
            style: theme.textStyle('--dsw-font-xl-24').copyWith(height: 1),
          ),
        ),
      ),
    );
  }
}
