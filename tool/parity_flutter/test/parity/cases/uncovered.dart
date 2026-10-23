// Kinds the React host renders that dsh_ui has no widget for yet. They are captured on the React side
// only and count as NOT COVERED until a Flutter widget exists.
import 'package:dsh_parity/dsh_parity.dart';

final Map<String, ParityUncovered> uncoveredBase = {
  for (final kind in const [
    'input.fields',
    'tag.items',
    'pill.items',
    'switch.items',
  ])
    kind: const ParityUncovered(
      ParityGap.noFlutterSurface,
      'dsh_ui has no widget for this atom yet (phase 0 ships DshButton only).',
    ),
};

/// Settings rows (build-settings.py): React-only until the Flutter widgets register their cases.
final Map<String, ParityUncovered> uncoveredSettings = {
  for (final kind in const [
    'settings.appearance',
    'settings.font',
    'settings.permission',
    'settings.general',
  ])
    kind: const ParityUncovered(
      ParityGap.noFlutterSurface,
      'The Flutter settings rows have no parity case yet.',
    ),
};
