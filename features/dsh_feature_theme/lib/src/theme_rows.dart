import 'dart:math' as math;

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'theme_service.dart';

const String _ns = 'settings.theme';

String _t(DshI18n i18n, String key) => i18n.t(_ns, key);

/// The Appearance row (dsh `AppearanceRow`): a title and three preference
/// cubes, light, dark, system. Selection follows the persisted preference,
/// never the resolved colour scheme.
class AppearanceRow extends StatelessWidget {
  const AppearanceRow({super.key, required this.service, required this.i18n});

  final ThemeSettingsService service;
  final DshI18n i18n;

  static const _cubes = <(ThemePreference, String, DshIconData)>[
    (ThemePreference.light, 'appearance.light', DshIcons.lightMedium),
    (ThemePreference.dark, 'appearance.dark', DshIcons.darkMedium),
    (ThemePreference.system, 'appearance.system', DshIcons.followSystemMedium),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshWatch(
      changes: service.settings.changes,
      builder: (context) {
        final preference = service.current.preference;
        final separator = !DshColumnEnd.of(context);
        // A Container: the border takes room below the padding, as CSS's does.
        return DshContainer(
          key: const ValueKey('appearance-row'),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: separator
                ? Border(
                    bottom: BorderSide(
                      color: DshSurface.paint(
                        context,
                        theme.color('--dsw-alias-border-l2'),
                      ),
                      width: dshHairlineOf(context),
                    ),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DshLineText(
                _t(i18n, 'appearance.title'),
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(color: theme.labelPrimary),
              ),
              const SizedBox(height: 8),
              _Cubes(
                cubes: (compact) => [
                  for (final (pref, key, icon) in _cubes)
                    _Cube(
                      key: ValueKey<String>('cube-${pref.name}'),
                      icon: icon,
                      label: _t(i18n, key),
                      selected: preference == pref,
                      compact: compact,
                      onPressed: service.writable || !service.available
                          ? () => service.setPreference(pref)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// dsh's `.cubeRow`: `display: flex; flex-wrap: wrap; gap: 8px` over cubes of
/// `flex: 1 1 180px`: as many per line as fit, each line shared equally.
class _Cubes extends StatelessWidget {
  const _Cubes({required this.cubes});

  final List<Widget> Function(bool compact) cubes;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final children = cubes(width < dshSettingsRowWide);
        // dsh's basis is 180px; on a phone the three cubes share one line.
        final basis = width < dshSettingsRowWide ? 96.0 : 180.0;
        final perLine = math.max(1, ((width + _gap) / (basis + _gap)).floor());
        final lines = <List<Widget>>[
          for (var i = 0; i < children.length; i += perLine)
            children.sublist(i, math.min(i + perLine, children.length)),
        ];
        return Column(
          children: [
            for (var l = 0; l < lines.length; l++) ...[
              if (l > 0) const SizedBox(height: _gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < lines[l].length; c++) ...[
                      if (c > 0) const SizedBox(width: _gap),
                      Expanded(child: lines[l][c]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Cube extends StatefulWidget {
  const _Cube({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.compact = false,
  });

  /// Phone width: less side padding so three cubes share a line.
  final bool compact;

  final DshIconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  State<_Cube> createState() => _CubeState();
}

class _CubeState extends State<_Cube> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final under = DshSurface.of(context);
    final fill = widget.selected
        ? theme.color('--dsw-alias-bg-module-platform')
        : (_hovered
              ? blendLikeChromium(theme.interactiveBgHover, under)
              : null);
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.onPressed != null,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DshContainer(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 8 : 32,
              vertical: 20,
            ),
            decoration: theme.cornerDecoration(
              theme.radiusXl,
              color: fill,
              borderColor: widget.selected
                  ? theme.color('--dsw-static-neutral-bluish-400')
                  : blendLikeChromium(
                      theme.color('--dsw-alias-border-l4'),
                      fill ?? under,
                    ),
              borderWidth: dshHairlineOf(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DshIcon(widget.icon, color: theme.labelPrimary),
                const SizedBox(height: 4),
                DshLineText(
                  widget.label,
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelPrimary),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The text font-size row and, behind its disclosure button, the font rows of
/// every role and the code and terminal size rows (dsh `FontSettingsGroup`).
/// The region starts collapsed on every mount.
class FontSettingsGroup extends StatefulWidget {
  const FontSettingsGroup({
    super.key,
    required this.service,
    required this.i18n,
    this.touch = false,
  });

  final ThemeSettingsService service;
  final DshI18n i18n;

  /// Whether input is by touch: the stepper arrows stay visible without hover.
  final bool touch;

  @override
  State<FontSettingsGroup> createState() => _FontSettingsGroupState();
}

class _FontSettingsGroupState extends State<FontSettingsGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return DshWatch(
      changes: service.settings.changes,
      builder: (context) {
        final rows = <Widget Function(bool separator)>[
          (sep) => _sizeRow(FontRole.text, sep, expander: true),
          if (_open) ...[
            (sep) => _familyRow(FontRole.text, sep),
            (sep) => _familyRow(FontRole.code, sep),
            (sep) => _sizeRow(FontRole.code, sep),
            (sep) => _familyRow(FontRole.terminal, sep),
            (sep) => _sizeRow(FontRole.terminal, sep),
          ],
        ];
        // When the group ends the column, its last visible row drops the
        // separator (dsh `FontSettingsGroup.module.css`).
        final endsColumn = DshColumnEnd.of(context);
        return Column(
          key: ValueKey<String>(_open ? 'font-group-open' : 'font-group'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++)
              rows[i](!(endsColumn && i == rows.length - 1)),
          ],
        );
      },
    );
  }

  Widget _sizeRow(FontRole role, bool separator, {bool expander = false}) {
    final service = widget.service;
    final i18n = widget.i18n;
    final spec = fontSizeSpecs[role]!;
    final size = service.current.fontSizes[role];
    final writable = service.writable || !service.available;
    return DshSettingsRow(
      separator: separator,
      title: _t(i18n, 'fontSize.${role.name}.title'),
      description: _t(i18n, 'fontSize.${role.name}.description'),
      control: DshStepper(
        value: size,
        unit: _t(i18n, 'fontSize.unit'),
        alwaysShowArrows: widget.touch,
        increaseLabel: _t(i18n, 'fontSize.${role.name}.increase'),
        decreaseLabel: _t(i18n, 'fontSize.${role.name}.decrease'),
        upKey: ValueKey<String>('font-${role.name}-up'),
        downKey: ValueKey<String>('font-${role.name}-down'),
        onIncrease: size >= spec.max || !writable
            ? null
            : () => widget.service.setFontSize(role, size + 1),
        onDecrease: size <= spec.min || !writable
            ? null
            : () => widget.service.setFontSize(role, size - 1),
        trailing: expander ? _expander(i18n) : null,
      ),
    );
  }

  Widget _familyRow(FontRole role, bool separator) {
    final service = widget.service;
    final i18n = widget.i18n;
    final title = _t(i18n, 'fontFamily.${role.name}.title');
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= dshSettingsRowWide;
        final input = DshInput(
          key: ValueKey<String>('font-${role.name}-family'),
          value: service.current.fontFamilies[role],
          placeholder: _t(i18n, 'fontFamily.placeholder'),
          semanticLabel: title,
          maxLength: 200,
          enabled: service.writable || !service.available,
          onCommit: (text) => service.setFontFamily(role, text),
        );
        return DshSettingsRow(
          separator: separator,
          stackedControl: true,
          title: title,
          description: _t(i18n, 'fontFamily.${role.name}.description'),
          // `flex: 0 1 240px` beside the text column.
          // The 240px basis is the content box: 256 with the wrapper's padding
          // plus both borders (258 in the emulated capture, 257 at 2x).
          control: wide
              ? SizedBox(width: 256 + 2 * dshHairlineOf(context), child: input)
              : input,
        );
      },
    );
  }

  Widget _expander(DshI18n i18n) {
    final label = _t(i18n, 'fontSize.more');
    return _Expander(
      label: label,
      open: _open,
      onTap: () => setState(() => _open = !_open),
    );
  }
}

class _Expander extends StatefulWidget {
  const _Expander({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  State<_Expander> createState() => _ExpanderState();
}

class _ExpanderState extends State<_Expander> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      button: true,
      expanded: widget.open,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const ValueKey<String>('font-expander'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DshContainer(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: theme.cornerDecoration(
              theme.number('--dsw-radius-xs'),
              color: _hovered
                  ? blendLikeChromium(
                      theme.interactiveBgHover,
                      DshSurface.of(context),
                    )
                  : null,
            ),
            child: Transform.rotate(
              angle: widget.open ? math.pi : 0,
              child: DshIcon(
                DshIcons.chevronDown,
                size: 12,
                color: theme.color('--dsw-alias-label-tertiary'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
