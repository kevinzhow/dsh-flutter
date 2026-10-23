import 'catalog.g.dart';

/// One catalog entry: English text and the Chinese text (null only for a gap
/// listed in tool/i18n/known-gaps.json).
typedef DshText = ({String en, String? zh});

/// namespace -> key -> text.
typedef DshCatalog = Map<String, Map<String, DshText>>;

/// A translate function bound to one namespace, like dsh's `ctx.locale.bind(ns)`.
typedef DshTranslate = String Function(
  String key, {
  Map<String, Object?> params,
});

/// The two locales dsh ships.
enum DshLocale {
  en,
  zh;

  /// Maps a BCP 47 style tag (`zh-CN`, `zh_Hans`, `en-US`) to a shipped locale.
  /// Anything that is not Chinese resolves to English, dsh's default.
  static DshLocale fromTag(String tag) {
    final primary = tag.split(RegExp('[-_]')).first.toLowerCase();
    return primary == 'zh' ? DshLocale.zh : DshLocale.en;
  }
}

/// Looks up dsh UI copy the way `LocaleService.translate` does
/// (packages/client/locale/src/client/index.ts):
///
/// 1. the key in the requested namespace for the active locale, then the
///    fallback locale (`zh` falls back to `en`; `en` has none);
/// 2. the same in the shared `common` namespace;
/// 3. the key itself.
///
/// Interpolation is dsh's: every `{name}` (word characters only) is replaced
/// by `String(params[name])`; a placeholder without a param stays verbatim.
/// dsh has no ICU plural syntax; callers pick `.one` / `.other` key variants
/// themselves (for example `archive.confirm.jobs.one`), so this class does not
/// implement `{n, plural, ...}` either.
class DshI18n {
  const DshI18n(this.locale, {DshCatalog? catalog})
    : _catalog = catalog ?? dshCatalog;

  final DshLocale locale;
  final DshCatalog _catalog;

  /// The same catalog under another locale.
  DshI18n withLocale(DshLocale locale) => DshI18n(locale, catalog: _catalog);

  /// The shared namespace consulted when a namespace has no value for a key.
  static const commonNamespace = 'common';

  /// Translates [key] in [namespace], interpolating [params].
  String t(
    String namespace,
    String key, {
    Map<String, Object?> params = const {},
  }) {
    final template =
        lookup(namespace, key) ??
        (namespace == commonNamespace ? null : lookup(commonNamespace, key)) ??
        key;
    return params.isEmpty ? template : interpolate(template, params);
  }

  /// The raw template for [key] in [namespace] under the locale fallback
  /// chain, without the `common` fallback and without interpolation.
  String? lookup(String namespace, String key) {
    final entry = _catalog[namespace]?[key];
    if (entry == null) return null;
    return switch (locale) {
      DshLocale.en => entry.en,
      DshLocale.zh => entry.zh ?? entry.en,
    };
  }

  /// Whether [namespace] defines [key] (ignoring the `common` fallback).
  bool has(String namespace, String key) =>
      _catalog[namespace]?.containsKey(key) ?? false;

  /// A translate function bound to [namespace].
  DshTranslate bind(String namespace) =>
      (key, {params = const {}}) => t(namespace, key, params: params);

  static final _placeholder = RegExp(r'\{(\w+)\}');

  /// dsh's `template.replace(/\{(\w+)\}/g, ...)`.
  static String interpolate(String template, Map<String, Object?> params) =>
      template.replaceAllMapped(_placeholder, (m) {
        final name = m[1]!;
        if (!params.containsKey(name)) return m[0]!;
        return _stringify(params[name]);
      });

  // JavaScript String(x): integral doubles print without a fraction.
  static String _stringify(Object? v) {
    if (v is double && v.isFinite && v == v.truncateToDouble()) {
      return v.toInt().toString();
    }
    return '$v';
  }
}
