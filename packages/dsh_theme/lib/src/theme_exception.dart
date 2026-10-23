/// A theme pack or theme settings value the engine cannot use.
///
/// Carries the JSON path of the offending entry (`modes.light.colors.--dsw-x`)
/// because "invalid theme" alone is not something a pack author can fix.
class ThemeException implements Exception {
  /// Creates an exception with a [message] and the optional JSON path [where].
  const ThemeException(this.message, {this.where});

  /// What is wrong.
  final String message;

  /// JSON path of the offending key, when there is one.
  final String? where;

  @override
  String toString() => where == null ? message : '$where: $message';
}
