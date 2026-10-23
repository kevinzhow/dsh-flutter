/// Syntax highlighting that reproduces dsh web's shiki css-variables colouring.
///
/// Pure Dart: the TextMate engine imports no Flutter. For grammar assets in a
/// Flutter app see `package:dsh_highlight/dsh_highlight_flutter.dart`; for
/// files (tests, tools) see `package:dsh_highlight/dsh_highlight_io.dart`.
library;

export 'src/api.dart';
export 'src/engine.dart' show HighlightEngine, PatternStats;
