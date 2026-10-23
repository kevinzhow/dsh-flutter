import 'package:dsh_i18n/dsh_i18n.dart';

/// One direct child of a session (dsh `SubagentCatalogEntry`): the parent's
/// catalog projection row.
class SubagentEntry {
  const SubagentEntry({
    required this.id,
    required this.mode,
    required this.createdAt,
    this.label,
  });

  final String id;

  /// `one-shot`, `continuable`, `external` or `unknown`.
  final String mode;
  final num createdAt;
  final String? label;

  /// An external task has no session to open.
  bool get openable => mode != 'external';
}

/// Read the `subagentCatalog` projection value (a list of rows), dropping rows
/// that are not objects with a string id.
List<SubagentEntry> catalogOf(Object? projection) => [
  if (projection is List)
    for (final row in projection)
      if (row is Map<String, Object?> && row['id'] is String)
        SubagentEntry(
          id: row['id']! as String,
          mode: row['mode'] is String ? row['mode']! as String : 'unknown',
          createdAt: row['createdAt'] is num ? row['createdAt']! as num : 0,
          label: row['label'] is String && (row['label']! as String).isNotEmpty
              ? row['label']! as String
              : null,
        ),
];

/// What the host's session list says about one child: activity, usage, time.
class SubagentStatus {
  const SubagentStatus({
    this.running = false,
    this.completed = false,
    this.tokens,
    this.durationMs,
  });

  final bool running;

  /// The latest closed turn completed normally.
  final bool completed;
  final int? tokens;
  final num? durationMs;
}

/// The mode label of a catalog row (`subagent` namespace).
String modeLabel(DshI18n i18n, String mode) =>
    i18n.t('subagent', switch (mode) {
      'one-shot' => 'mode.oneShot',
      'continuable' => 'mode.continuable',
      'external' => 'mode.external',
      _ => 'mode.unknown',
    });

/// Compact token count (dsh `formatTokens`).
String formatTokens(num value, DshI18n i18n) {
  String scaled(double v) => v >= 100
      ? '${v.round()}'
      : '${(v * 10).round() / 10}'.replaceAll(RegExp(r'\.0$'), '');
  if (value < 1000) return '${value.round()}';
  if (value < 1000000) {
    return i18n.t(
      'subagent',
      'tokens.thousand',
      params: {'value': scaled(value / 1000)},
    );
  }
  return i18n.t(
    'subagent',
    'tokens.million',
    params: {'value': scaled(value / 1000000)},
  );
}

/// Duration with decreasing precision at larger scales (dsh `formatDuration`,
/// without the month and year tiers a phone row never reaches).
String formatDuration(num ms, DshI18n i18n) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final seconds = total % 60;
  final minutes = (total ~/ 60) % 60;
  final hours = total ~/ 3600;
  String t(String key, Map<String, Object?> p) =>
      i18n.t('subagent', key, params: p);
  if (hours > 0) {
    return t('duration.hours', {
      'hours': hours,
      'minutes': minutes,
      'seconds': seconds,
    });
  }
  if (minutes > 0) {
    return t('duration.minutes', {'minutes': minutes, 'seconds': seconds});
  }
  return t('duration.seconds', {'seconds': seconds});
}
