import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// One installed application as the control shows it.
class OpenTargetApplication {
  const OpenTargetApplication({
    required this.id,
    required this.name,
    required this.icon,
  });

  final String id;
  final String name;

  /// The host's icon for it (null result: the arrow glyph stands in).
  final Future<Uint8List?> Function() icon;
}

/// Copy of the control, resolved by the caller.
class OpenTargetLabels {
  const OpenTargetLabels({
    required this.open,
    required this.more,
    required this.defaultOf,
  });

  /// "Open in {app}" for the preferred application.
  final String Function(String app) open;

  /// "More ways to open".
  final String more;

  /// "{app} (default)" for the preferred one in the menu.
  final String Function(String app) defaultOf;
}

/// The directory split button of dsh `OpenTargetButton`: a hairline 24px pill
/// holding the preferred application's icon (opens the directory in it) and a
/// narrow chevron half that lists the other installed applications.
class OpenTargetButton extends StatefulWidget {
  const OpenTargetButton({
    super.key,
    required this.applications,
    required this.preferredId,
    required this.labels,
    required this.busy,
    required this.onOpen,
    this.shortcutKeys,
  });

  final List<OpenTargetApplication> applications;
  final String preferredId;
  final OpenTargetLabels labels;
  final bool busy;

  /// Opens the directory in [id]; [explicit] when picked from the menu (the
  /// choice is remembered then).
  final Future<void> Function(String id, {required bool explicit}) onOpen;
  final List<String>? shortcutKeys;

  @override
  State<OpenTargetButton> createState() => _OpenTargetButtonState();
}

class _OpenTargetButtonState extends State<OpenTargetButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _menu;
  bool _pending = false;
  bool _mainHover = false;
  bool _chevronHover = false;

  OpenTargetApplication get _preferred => widget.applications.firstWhere(
    (a) => a.id == widget.preferredId,
    orElse: () => widget.applications.first,
  );

  bool get _disabled => _pending || widget.busy;

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  void _closeMenu() {
    final open = _menu != null;
    _menu?.remove();
    _menu = null;
    if (open && mounted) setState(() {});
  }

  void _run(String id, {required bool explicit}) {
    if (_pending) return;
    _closeMenu();
    setState(() => _pending = true);
    unawaited(
      widget.onOpen(id, explicit: explicit).whenComplete(() {
        if (mounted) setState(() => _pending = false);
      }),
    );
  }

  void _toggleMenu() {
    if (_menu != null) {
      _closeMenu();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final preferred = _preferred.id;
    _menu = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
              onSecondaryTap: _closeMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: _Menu(
              key: const ValueKey('open-in-app-menu'),
              children: [
                for (final app in widget.applications)
                  _MenuRow(
                    key: ValueKey('open-in-app-menu-${app.id}'),
                    app: app,
                    label: app.id == preferred
                        ? widget.labels.defaultOf(app.name)
                        : app.name,
                    onTap: () => _run(app.id, explicit: true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    overlay.insert(_menu!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final preferred = _preferred;
    final hasMenu = widget.applications.length > 1;
    final open = widget.labels.open(preferred.name);
    final border = theme.color('--dsw-alias-border-l4');
    final hairline = dshHairlineOf(context);
    return CompositedTransformTarget(
      link: _link,
      child: DshContainer(
        key: const ValueKey('open-in-app'),
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(theme.radiusSm),
          border: Border.all(color: border, width: hairline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.radiusSm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DshTooltip(
                label: open,
                shortcutKeys: widget.shortcutKeys,
                side: DshTooltipSide.bottom,
                delay: const Duration(milliseconds: 500),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _mainHover = true),
                  onExit: (_) => setState(() => _mainHover = false),
                  cursor: _disabled
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: Semantics(
                    button: true,
                    enabled: !_disabled,
                    label: open,
                    child: GestureDetector(
                      key: const ValueKey('open-in-app-main'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _disabled
                          ? null
                          : () => _run(preferred.id, explicit: false),
                      child: DshContainer(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _mainHover && !_disabled
                              ? theme.interactiveBgHover
                              : null,
                        ),
                        child: _AppIcon(app: preferred, size: 13),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasMenu)
                MouseRegion(
                  onEnter: (_) => setState(() => _chevronHover = true),
                  onExit: (_) => setState(() => _chevronHover = false),
                  cursor: _disabled
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: Semantics(
                    button: true,
                    enabled: !_disabled,
                    label: widget.labels.more,
                    child: GestureDetector(
                      key: const ValueKey('open-in-app-more'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _disabled ? null : _toggleMenu,
                      child: DshContainer(
                        padding: const EdgeInsets.fromLTRB(3, 3, 4, 3),
                        decoration: BoxDecoration(
                          color: _chevronHover && !_disabled
                              ? theme.interactiveBgHover
                              : null,
                          border: Border(
                            left: BorderSide(color: border, width: hairline),
                          ),
                        ),
                        child: DshIcon(
                          DshShellIcons.chevronDownRegular,
                          size: 10,
                          color: theme.labelSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An application's host icon at [size], with the arrow glyph while it loads
/// and when the host has none (dsh `ApplicationIcon`).
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, required this.size});

  final OpenTargetApplication app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final glyph = DshIcon(
      DshShellIcons.rightUp,
      size: size,
      color: theme.labelPrimary,
    );
    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<Uint8List?>(
        key: ValueKey('open-in-app-icon-${app.id}'),
        future: app.icon(),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) return glyph;
          return ExcludeSemantics(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => glyph,
            ),
          );
        },
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshContainer(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-bg-layer-2'),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l2'),
          width: dshHairlineOf(context),
        ),
        boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    super.key,
    required this.app,
    required this.label,
    required this.onTap,
  });

  final OpenTargetApplication app;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DshContainer(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: _hover ? theme.interactiveBgHover : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AppIcon(app: widget.app, size: 14),
                const SizedBox(width: 8),
                DshChromeText(
                  widget.label,
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(color: theme.labelPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
