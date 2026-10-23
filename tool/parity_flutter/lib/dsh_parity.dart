/// Flutter provider of the dsh-flutter visual parity tool.
///
/// A capture is a `flutter_test` widget test that pumps the real dsh_flutter widgets for one manifest
/// case at the case's viewport and density, with the official theme pack in the requested theme and
/// the pinned parity fonts, and writes the provider output contract
/// (`<results>/flutter/<captureKey>.png` + `.metadata.json`) that `tool/parity` diffs against the
/// React provider's capture. See `docs/parity.md`.
library;

export 'src/capture.dart' show captureParityCase, enclosingPixelRect;
export 'src/case.dart';
export 'src/fonts.dart';
export 'src/layout.dart';
export 'src/runner.dart' show runParityCapture;
export 'src/settle.dart';
export 'src/theme.dart';
