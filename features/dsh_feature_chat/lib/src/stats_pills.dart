/// The session statistics pills under the composer (dsh `ui-chat`
/// `StatsPills`): turn and step counts with the decode speed, and the token
/// total with the cache hit. Each opens the shared anchored statistics panel.
library;

import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart' show SizeScale;
import 'package:flutter/services.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

String _t(DshI18n i18n, String key, [Map<String, Object?> params = const {}]) {
  try {
    final text = i18n.t('chat', key, params: params);
    if (text != key) return text;
  } on Object {
    // fall through to the shared dictionary
  }
  return i18n.t('common', key, params: params);
}

/// The `sessionStats` projection: whole-log figures (dsh
/// `SessionStatsProjection`).
class SessionStats {
  const SessionStats({
    this.turns = 0,
    this.steps = 0,
    this.llmMs = 0,
    this.toolMs = 0,
    this.ttftMs = 0,
    this.ttftSteps = 0,
    this.decodeMs = 0,
    this.decodeTokens = 0,
  });

  static SessionStats? of(Object? value) {
    if (value is! Map) return null;
    num n(String k) => value[k] is num ? value[k] as num : 0;
    return SessionStats(
      turns: n('turns').toInt(),
      steps: n('steps').toInt(),
      llmMs: n('llmMs'),
      toolMs: n('toolMs'),
      ttftMs: n('ttftMs'),
      ttftSteps: n('ttftSteps').toInt(),
      decodeMs: n('decodeMs'),
      decodeTokens: n('decodeTokens'),
    );
  }

  final int turns;
  final int steps;
  final num llmMs;
  final num toolMs;
  final num ttftMs;
  final int ttftSteps;
  final num decodeMs;
  final num decodeTokens;
}

/// The `tokenUsage` projection (dsh `TokenUsageProjection`).
class TokenUsage {
  const TokenUsage({
    this.uncachedInputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.outputTokens = 0,
  });

  static TokenUsage? of(Object? value) {
    if (value is! Map) return null;
    int n(String k) => value[k] is num ? (value[k] as num).toInt() : 0;
    return TokenUsage(
      uncachedInputTokens: n('uncachedInputTokens'),
      cacheReadTokens: n('cacheReadTokens'),
      cacheWriteTokens: n('cacheWriteTokens'),
      outputTokens: n('outputTokens'),
    );
  }

  final int uncachedInputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int outputTokens;

  /// The three disjoint prompt-side billing buckets.
  int get billedInput =>
      uncachedInputTokens + cacheReadTokens + cacheWriteTokens;
}

/// Compact token count: 517 / 12.2K / 517K / 1.2M (dsh `formatTokens`).
String formatTokens(int value, DshI18n i18n) {
  String scaled(double v) =>
      v >= 100 ? '${v.round()}' : _trimmed((v * 10).round() / 10);
  if (value < 1000) return '$value';
  if (value < 1000000) {
    return _t(i18n, 'number.thousand', {'value': scaled(value / 1000)});
  }
  return _t(i18n, 'number.million', {'value': scaled(value / 1000000)});
}

String _trimmed(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Exact count with the locale's digit grouping (dsh `formatExactTokens`).
String formatExactTokens(int value, DshI18n i18n) {
  final digits = '$value';
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
  }
  return groups.join(_t(i18n, 'number.groupSeparator'));
}

/// Cache-hit share without rounding a partial hit up to 100% (dsh
/// `formatCacheHitPercent`); null when there was no prompt input.
String? formatCacheHitPercent(int cacheRead, int prompt) {
  if (prompt == 0) return null;
  final missed = prompt - cacheRead;
  if (missed == 0) return '100';
  // Round half up to whole percent.
  final units = ((cacheRead * 200 + prompt) ~/ (prompt * 2));
  if (units < 100) return '$units';
  var places = 1;
  var gap = missed * 200;
  final tens = prompt ~/ 10;
  while (gap <= tens) {
    gap *= 10;
    places++;
  }
  final ones = prompt % 10;
  var loss = 5;
  for (var l = 1; l < 5; l++) {
    final factor = l * 2 + 1;
    final threshold = factor * tens + (factor * ones) ~/ 10;
    if (gap <= threshold) {
      loss = l;
      break;
    }
  }
  return '99.${'9' * (places - 1)}${10 - loss}';
}

/// Compact duration: 45.2s under a minute, 2m42s from there on.
String formatDuration(num ms, DshI18n i18n) {
  final s = ms / 1000;
  if (s < 60) {
    return _t(i18n, 'duration.compactSeconds', {
      'seconds': _trimmed((s * 10).round() / 10),
    });
  }
  final whole = s.round();
  return _t(i18n, 'duration.compactMinutes', {
    'minutes': whole ~/ 60,
    'seconds': whole % 60,
  });
}

String _tokensPerSecond(num tps) {
  final v = tps < 0 ? 0 : tps;
  return v >= 10 ? '${v.round()}' : _trimmed((v * 10).round() / 10);
}

/// What a pill shows and opens.
class StatPill {
  const StatPill({
    required this.icon,
    required this.label,
    required this.aria,
    this.title,
    this.titleValue,
    this.rows = const [],
  });

  final DshIconData icon;
  final String label;
  final String aria;
  final String? title;
  final String? titleValue;
  final List<(String, String)> rows;
}

/// The activity pill: counts and decode speed; null when the log has no step.
StatPill? activityPill(SessionStats? stats, DshI18n i18n) {
  if (stats == null || stats.steps == 0) return null;
  final speed = stats.decodeMs > 0
      ? _t(i18n, 'message.tokensPerSecond', {
          'tps': _tokensPerSecond(stats.decodeTokens / (stats.decodeMs / 1000)),
        })
      : null;
  final counts = _t(i18n, 'stats.counts', {
    'turns': stats.turns,
    'steps': stats.steps,
  });
  final rows = [
    if (stats.llmMs > 0)
      (_t(i18n, 'stats.dialog.llmTime'), formatDuration(stats.llmMs, i18n)),
    if (stats.toolMs > 0)
      (_t(i18n, 'stats.dialog.toolTime'), formatDuration(stats.toolMs, i18n)),
    if (stats.ttftSteps > 0)
      (
        _t(i18n, 'stats.dialog.ttft'),
        formatDuration(stats.ttftMs / stats.ttftSteps, i18n),
      ),
    if (speed != null) (_t(i18n, 'stats.dialog.speed'), speed),
  ];
  return StatPill(
    icon: DshShellIcons.gauge,
    label: speed == null ? counts : '$counts·$speed',
    aria: speed == null ? counts : '$counts · $speed',
    title: rows.isEmpty ? null : _t(i18n, 'stats.dialog.title'),
    rows: rows,
  );
}

/// The usage pill: the token total and the cache hit; null without billing.
StatPill? usagePill(TokenUsage? usage, DshI18n i18n) {
  if (usage == null || (usage.billedInput == 0 && usage.outputTokens == 0)) {
    return null;
  }
  final hit = formatCacheHitPercent(usage.cacheReadTokens, usage.billedInput);
  final hitText = hit == null
      ? null
      : _t(i18n, 'stats.cacheHit', {'percent': hit});
  final total = usage.billedInput + usage.outputTokens;
  String count(int v) => _t(i18n, 'message.turnUsage.count', {
    'count': formatExactTokens(v, i18n),
  });
  final totalText = _t(i18n, 'message.turnUsage.count', {
    'count': formatTokens(total, i18n),
  });
  return StatPill(
    icon: DshShellIcons.database,
    label: hitText == null ? totalText : '$totalText·$hitText',
    aria: hitText == null ? totalText : '$totalText · $hitText',
    title: _t(i18n, 'stats.dialog.usageTitle'),
    titleValue: count(total),
    rows: [
      if (hit != null) (_t(i18n, 'message.turnUsage.cacheHit'), '$hit%'),
      (_t(i18n, 'message.turnUsage.input'), count(usage.uncachedInputTokens)),
      (_t(i18n, 'message.turnUsage.cacheRead'), count(usage.cacheReadTokens)),
      if (usage.cacheWriteTokens != 0)
        (
          _t(i18n, 'message.turnUsage.cacheWrite'),
          count(usage.cacheWriteTokens),
        ),
      (_t(i18n, 'message.turnUsage.output'), count(usage.outputTokens)),
    ],
  );
}

/// A pill of the composer dock, live on the session's projections.
class StatsPill extends StatefulWidget {
  const StatsPill({
    super.key,
    required this.owner,
    required this.i18n,
    required this.activity,
  });

  final SessionOwner owner;
  final DshI18n i18n;

  /// The activity pill (counts and speed); false for the usage pill.
  final bool activity;

  @override
  State<StatsPill> createState() => _StatsPillState();
}

class _StatsPillState extends State<StatsPill> {
  StreamSubscription<Object?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.owner.session.projections.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.owner.session.projections;
    final pill = widget.activity
        ? activityPill(SessionStats.of(p.get('sessionStats')), widget.i18n)
        : usagePill(TokenUsage.of(p.get('tokenUsage')), widget.i18n);
    if (pill == null) return const SizedBox.shrink();
    return StatPillView(
      key: ValueKey(widget.activity ? 'stat-activity' : 'stat-usage'),
      pill: pill,
    );
  }
}

class StatPillView extends StatefulWidget {
  const StatPillView({super.key, required this.pill});

  final StatPill pill;

  @override
  State<StatPillView> createState() => StatPillViewState();
}

class StatPillViewState extends State<StatPillView> {
  bool _hover = false;
  final _focusNode = FocusNode(debugLabel: 'statistics pill');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final pill = widget.pill;
    final interactive = pill.title != null;
    final delta = SizeScale.tryParse(DshStatsPillRecipe.fontScale)!
        .delta(theme.settings.fontSizes);
    final style = theme
        .fixedTextStyle(
          size: DshStatsPillRecipe.fontBase + delta,
          line: DshStatsPillRecipe.lineBase + delta,
        )
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    Widget content(bool open) {
      final ink = (_hover || open) && interactive
          ? theme.color(DshStatsPillRecipe.activeLabelToken)
          : theme.color(DshStatsPillRecipe.labelToken);
      return DshContainer(
        padding: const EdgeInsets.symmetric(
          horizontal: DshStatsPillRecipe.paddingHorizontal,
          vertical: DshStatsPillRecipe.paddingVertical,
        ),
        decoration: BoxDecoration(
          color: (_hover || open) && interactive
              ? theme.color(DshStatsPillRecipe.activeFillToken)
              : null,
          borderRadius: BorderRadius.circular(
            theme.number(DshStatsPillRecipe.radiusToken),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DshIcon(pill.icon, size: DshStatsPillRecipe.iconSize, color: ink),
            const SizedBox(width: DshStatsPillRecipe.gap),
            Flexible(
              child: _Label(
                text: pill.label,
                style: style.copyWith(color: ink),
              ),
            ),
          ],
        ),
      );
    }

    if (!interactive) return content(false);
    return DshAnchoredPanel(
      side: DshPanelSide.top,
      gap: DshStatPanelRecipe.anchorGap,
      viewportMargin: DshStatPanelRecipe.viewportMargin,
      menuViewport: true,
      domOffsetGeometry: true,
      focusPanel: false,
      exclusiveGroup: StatPillView,
      builder: (context, panel) => ListenableBuilder(
        listenable: panel,
        builder: (context, _) => MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Semantics(
            button: true,
            label: pill.aria,
            expanded: panel.isOpen,
            excludeSemantics: true,
            onTap: panel.toggle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: panel.toggle,
              child: FocusableActionDetector(
                focusNode: _focusNode,
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      panel.toggle();
                      return null;
                    },
                  ),
                },
                child: content(panel.isOpen),
              ),
            ),
          ),
        ),
      ),
      panelBuilder: (context, panel) => DshStatPanel(
        icon: pill.icon,
        title: pill.title!,
        titleValue: pill.titleValue,
        rows: pill.rows,
      ),
    );
  }
}

/// The label with the dim middle dot between its two readings.
class _Label extends StatelessWidget {
  const _Label({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('·');
    return DshChromeBaseline(
      style: style,
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0)
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DshStatsPillRecipe.separatorMargin,
                    ),
                    child: Text(
                      '·',
                      strutStyle: dshStrut(style),
                      style: style.copyWith(
                        // The pinned source references an undefined separator
                        // custom property. CSS then inherits the pill's ink.
                        color:
                            context.dsh.colors[DshStatsPillRecipe
                                .separatorToken] ??
                            style.color,
                      ),
                    ),
                  ),
                ),
              TextSpan(text: parts[i]),
            ],
          ],
        ),
        style: style,
        strutStyle: dshStrut(style),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
