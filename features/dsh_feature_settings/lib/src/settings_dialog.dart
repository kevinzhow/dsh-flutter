/// The settings panel of the desktop shell (dsh `ui-settings-general`
/// `SettingsRoot.tsx`): a centred modal, 800 wide, with the section navigation
/// on the left (188px) and the selected section on the right under a header
/// that holds the `settings.action` seats and the close button.
library;

import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Slot<SettingsOwner, Widget> _sectionSlot = DshSlots.settingsSection
    .typed<SettingsOwner, Widget>();

DshIconData _navIcon(String id) => switch (id) {
  'plugins' => DshIcons.personalizationMedium,
  _ => DshIcons.settingsMedium,
};

/// The panel inside its mask. [overlayTop] is the inset the frame keeps clear
/// above dialogs (the caption plus 20px on desktop chrome).
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.slots,
    required this.i18n,
    required this.onClose,
    this.initialSection,
    this.overlayTop = 24,
  });

  final SlotRegistry slots;
  final DshI18n Function() i18n;
  final VoidCallback onClose;
  final String? initialSection;
  final double overlayTop;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  String? _active;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _active = widget.initialSection;
    _sub = widget.slots.changes.listen((name) {
      if (name.startsWith('settings.') && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final size = MediaQuery.sizeOf(context);
    final entries = widget.slots.entries(_sectionSlot);
    final active = entries.any((e) => e.id == _active)
        ? _active
        : entries.firstOrNull?.id;
    final margin = widget.overlayTop > 24 ? widget.overlayTop : 24.0;
    final height = (size.height - 2 * margin).clamp(0.0, 800.0);
    final width = (size.width - 48).clamp(0.0, 800.0);
    final i18n = widget.i18n();
    final title =
        widget.slots.renderSingle(
          DshShellSlots.settingsHeader.typed<SettingsHeaderOwner, Widget>(),
          const SettingsHeaderOwner(),
        ) ??
        DshChromeText(i18n.t('settings', 'title'));
    final actions = widget.slots.renderList(
      DshShellSlots.settingsAction.typed<SettingsHeaderOwner, Widget>(),
      const SettingsHeaderOwner(),
    );
    final closeLabel = widget.slots.renderSingle(
      DshShellSlots.settingsClose.typed<SettingsHeaderOwner, Widget>(),
      const SettingsHeaderOwner(),
    );
    return Center(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: i18n.t('settings', 'title'),
        child: DshDecoratedBox(
          key: const ValueKey('settings-panel'),
          decoration: BoxDecoration(
            color: theme.color('--dsw-alias-bg-layer-2'),
            borderRadius: BorderRadius.circular(
              theme.number('--dsw-radius-panel'),
            ),
            boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              theme.number('--dsw-radius-panel'),
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 188,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 22, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: DefaultTextStyle.merge(
                              style: theme
                                  .textStyle('--dsw-font-base-strong-16')
                                  .copyWith(color: theme.labelPrimary),
                              child: KeyedSubtree(
                                key: const ValueKey('settings-title'),
                                child: title,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                for (final e in entries)
                                  _NavCell(
                                    entry: e,
                                    selected: e.id == active,
                                    onTap: () => setState(() => _active = e.id),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 54,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 20, 14, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Spacer(),
                                for (final a in actions) ...[
                                  a,
                                  const SizedBox(width: 8),
                                ],
                                _CloseButton(
                                  key: const ValueKey('settings-close'),
                                  label: i18n.t('settings', 'close'),
                                  hiddenLabel: closeLabel,
                                  onPressed: widget.onClose,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 0),
                            child: active == null
                                ? const SizedBox.shrink()
                                : widget.slots.renderOnly(
                                        _sectionSlot,
                                        active,
                                        const SettingsOwner(),
                                      ) ??
                                      const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatefulWidget {
  const _NavCell({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final SlotEntryInfo entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavCell> createState() => _NavCellState();
}

class _NavCellState extends State<_NavCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final fill = widget.selected
        ? theme.color('--dsw-specific-sidebar-nav-item-active')
        : _hover
        ? theme.color('--dsw-specific-sidebar-nav-item-hover')
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: widget.entry.label,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('settings-nav-${widget.entry.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: DshContainer(
              height: 40,
              padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
              decoration: theme.cornerDecoration(theme.radiusMd, color: fill),
              child: Row(
                children: [
                  DshIcon(
                    _navIcon(widget.entry.id),
                    size: 16,
                    color: theme.labelPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DshChromeText(
                      widget.entry.label ?? widget.entry.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .textStyle('--dsw-font-s-14')
                          .copyWith(color: theme.labelPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({
    super.key,
    required this.label,
    required this.hiddenLabel,
    required this.onPressed,
  });

  final String label;
  final Widget? hiddenLabel;
  final VoidCallback onPressed;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
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
          onTap: widget.onPressed,
          child: DshContainer(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? theme.interactiveBgHover : null,
              borderRadius: BorderRadius.circular(theme.radiusSm),
            ),
            child: DshIcon(DshIcons.close, size: 14, color: theme.labelPrimary),
          ),
        ),
      ),
    );
  }
}
