import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart' show DshThemeData;
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'candidate_icons.dart';

/// Design cap of the list (fits the two headings and eight built-in rows).
const double triggerMenuMaxHeight = 400;

/// The candidate menu overlay entry (dsh `MenuView`): renders one session's
/// menu store above the composer. Closed it is nothing. The composer keeps the
/// keyboard (combobox pattern): a row is picked by tap and never takes focus,
/// and a press outside both the menu and the composer dismisses it.
class TriggerMenuOverlay extends StatefulWidget {
  const TriggerMenuOverlay({
    super.key,
    required this.sessionId,
    required this.controller,
    required this.i18n,
  });

  final String sessionId;

  /// The session's trigger pipeline whose menu store this draws.
  final InputTriggerController controller;
  final DshI18n i18n;

  @override
  State<TriggerMenuOverlay> createState() => _TriggerMenuOverlayState();
}

class _TriggerMenuOverlayState extends State<TriggerMenuOverlay> {
  InputTriggerController get _controller => widget.controller;
  StreamSubscription<MenuState>? _menuSub;
  StreamSubscription<Map<String, List<InputTriggerCrumb>>>? _crumbSub;
  final Map<String, GlobalKey> _rowKeys = {};
  MenuHighlight? _scrolled;

  @override
  void initState() {
    super.initState();
    _menuSub = _controller.menu.changes.listen((_) => _changed());
    _crumbSub = _controller.headers.changes.listen((_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_menuSub?.cancel());
    unawaited(_crumbSub?.cancel());
    super.dispose();
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('slash.menu', key, params: params);

  GlobalKey _key(String source, int index) =>
      _rowKeys.putIfAbsent('$source/$index', GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final state = _controller.menu.value;
    if (!state.open) return const SizedBox.shrink();
    final theme = context.dsh;
    final crumbs = _controller.headers.value;
    final highlight = state.highlight;
    if (highlight != null && highlight != _scrolled) {
      _scrolled = highlight;
      // The composer keeps focus, so the list never scrolls the active row
      // into view by itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx =
            _rowKeys['${highlight.source}/${highlight.index}']?.currentContext;
        if (ctx != null && ctx.mounted) {
          unawaited(
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.5,
              duration: Duration.zero,
            ),
          );
        }
      });
    }
    final groups = state.groups
        .where((g) => !(g.ready && g.items.isEmpty))
        .toList();
    return TapRegion(
      groupId: composerTapGroup(widget.sessionId),
      onTapOutside: (_) => _controller.dismiss(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cap = constraints.hasBoundedHeight
              ? constraints.maxHeight.clamp(0.0, triggerMenuMaxHeight)
              : triggerMenuMaxHeight;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: cap),
            child: DshMenuSurface(
              key: const ValueKey('trigger-menu-surface'),
              child: Column(
                key: const ValueKey('trigger-menu'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in state.groups)
                    if (crumbs[g.source] case final trail?)
                      _Crumbs(
                        source: g.source,
                        trail: trail,
                        label: _t('crumbs.aria'),
                        onPick: _controller.pickCrumb,
                      ),
                  Flexible(
                    child: Semantics(
                      label: _t('suggestions.aria'),
                      child: SingleChildScrollView(
                        key: const ValueKey('trigger-menu-list'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final g in groups)
                              ..._group(context, theme, g, highlight),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _group(
    BuildContext context,
    DshThemeData theme,
    MenuGroup group,
    MenuHighlight? highlight,
  ) {
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final out = <Widget>[];
    final sectioned = group.items.any((i) => i.section != null);
    if (group.showGroupTitle && !sectioned) {
      out.add(
        Padding(
          key: ValueKey('trigger-group-${group.source}'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: DshChromeText(
            _t(group.source),
            style: theme
                .textStyle('--dsw-font-xxxs-11')
                .copyWith(color: tertiary, height: 15 / 11),
          ),
        ),
      );
    }
    if (!group.ready && group.items.isEmpty) {
      out.add(
        Semantics(
          label: _t('loading'),
          child: Column(
            key: ValueKey('trigger-loading-${group.source}'),
            children: [
              for (final w in const [0.32, 0.48]) _SkeletonRow(widthFactor: w),
            ],
          ),
        ),
      );
      return out;
    }
    for (var i = 0; i < group.items.length; i++) {
      final item = group.items[i];
      final prevSection = i == 0 ? null : group.items[i - 1].section;
      if (item.section != null && item.section != prevSection) {
        // dsh's `.sectionTitle` is `min-height: 23px` plus 7px of padding
        // (content-box), with 3px of margin above every heading but the first.
        out.add(
          Padding(
            padding: EdgeInsets.only(top: out.isEmpty ? 0 : 3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 2),
                child: DshChromeText(
                  item.section!,
                  style: theme
                      .textStyle('--dsw-font-xxxs-strong-11')
                      .copyWith(
                        color: tertiary,
                        height: 16 / 11,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
          ),
        );
      }
      final active =
          highlight != null &&
          highlight.source == group.source &&
          highlight.index == i;
      out.add(
        _Row(
          key: _key(group.source, i),
          item: item,
          active: active,
          drillHint: _t('drill.hint'),
          drillKey: _t('drill.key'),
          drillLabel: _t('drill.aria'),
          onPick: () => _controller.pick(group.source, i),
          onDrill: () => _controller.pick(group.source, i, PickAction.drill),
          onHover: () => _controller.hover(group.source, i),
        ),
      );
    }
    return out;
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.item,
    required this.active,
    required this.drillHint,
    required this.drillKey,
    required this.drillLabel,
    required this.onPick,
    required this.onDrill,
    required this.onHover,
  });

  final InputTriggerCandidate item;
  final bool active;
  final String drillHint;
  final String drillKey;
  final String drillLabel;
  final VoidCallback onPick;
  final VoidCallback onDrill;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final icon = candidateIcon(item.icon);
    final title = item.label ?? item.name;
    final showAlias =
        item.label != null &&
        item.label!.toLowerCase() != item.name.toLowerCase();
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final small = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: tertiary, height: 18 / 12);
    return Semantics(
      button: true,
      selected: active,
      label: title,
      excludeSemantics: true,
      child: MouseRegion(
        onHover: active ? null : (_) => onHover(),
        child: GestureDetector(
          key: ValueKey('trigger-row-${item.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: onPick,
          child: DshDecoratedBox(
            decoration: BoxDecoration(
              color: active
                  ? theme.color('--dsw-alias-interactive-bg-hover')
                  : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: ConstrainedBox(
              // dsh rows are 34px, at every width.
              constraints: BoxConstraints(minHeight: 34),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      DshIcon(
                        icon,
                        size: 14,
                        color: theme.color('--dsw-alias-menu-icon'),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                        ),
                        child: DshChromeText(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme
                              .textStyle('--dsw-font-xs-13')
                              .copyWith(
                                color: theme.labelPrimary,
                                height: 20 / 13,
                              ),
                        ),
                      ),
                    ),
                    if (showAlias) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        flex: 0,
                        child: DshChromeText(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Expanded(
                      child: item.description == null
                          ? const SizedBox.shrink()
                          : DshChromeText(
                              item.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: small,
                            ),
                    ),
                    if (item.drill) ...[
                      if (active) ...[
                        const SizedBox(width: 3),
                        DshChromeText(
                          drillHint,
                          style: theme
                              .textStyle('--dsw-font-xxxs-11')
                              // dsh's 10px caption (`.drillHintText`), one step below the ladder.
                              .apply(fontSizeFactor: 10 / 11)
                              .copyWith(
                                color: theme.color('--dsw-alias-label-caption'),
                                height: 16 / 10,
                              ),
                        ),
                        const SizedBox(width: 3),
                        DshDecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.color(
                              '--dsw-alias-interactive-bg-hover',
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: DshChromeText(
                              drillKey,
                              style: theme
                                  .textStyle('--dsw-font-xxxs-11')
                                  .apply(fontSizeFactor: 10 / 11)
                                  .copyWith(
                                    color: theme.color(
                                      '--dsw-alias-label-caption',
                                    ),
                                    height: 16 / 10,
                                  ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 3),
                      Semantics(
                        button: true,
                        label: drillLabel,
                        child: GestureDetector(
                          key: ValueKey('trigger-drill-${item.name}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onDrill,
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: Center(
                              child: DshIcon(
                                DshIcons.chevronRight,
                                size: 12,
                                color: theme.color('--dsw-alias-menu-icon'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Crumbs extends StatelessWidget {
  const _Crumbs({
    required this.source,
    required this.trail,
    required this.label,
    required this.onPick,
  });

  final String source;
  final List<InputTriggerCrumb> trail;
  final String label;
  final void Function(String source, int index) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-xxxs-11')
        .copyWith(height: 16 / 11);
    return Semantics(
      label: label,
      container: true,
      // `.crumbs { padding: 3px 3px 5px; margin-bottom: 2px; border-bottom: .5px }`.
      child: DshContainer(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.color('--dsw-alias-border-l1'),
              width: dshHairlineOf(context),
            ),
          ),
        ),
        child: Padding(
          key: ValueKey('trigger-crumbs-$source'),
          padding: const EdgeInsets.fromLTRB(3, 3, 3, 5),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              for (final (i, crumb) in trail.indexed) ...[
                if (i > 0)
                  DshIcon(
                    DshIcons.chevronRight,
                    size: 12,
                    color: theme.color('--dsw-alias-menu-icon'),
                  ),
                GestureDetector(
                  key: ValueKey('trigger-crumb-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: crumb.current ? null : () => onPick(source, i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: DshChromeText(
                      crumb.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        color: crumb.current
                            ? theme.labelPrimary
                            : theme.color('--dsw-alias-label-tertiary'),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 34),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: DshDecoratedBox(
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-bg-skeleton'),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox(height: 18),
            ),
          ),
        ),
      ),
    );
  }
}
