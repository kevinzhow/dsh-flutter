import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// Width from which the page shows dsh's two-column panel (navigation rail
/// and content) instead of the phone's list-then-page.
const double settingsTwoColumnWidth = 720;

final Slot<SettingsOwner, Widget> _sectionSlot = DshSlots.settingsSection
    .typed<SettingsOwner, Widget>();

DshIconData _navIcon(String id) => switch (id) {
  'plugins' => DshIcons.personalizationMedium,
  _ => DshIcons.settingsMedium,
};

/// The settings page (dsh `ui-settings-general` `SettingsRoot`): the
/// navigation is a projection of the `settings.section` ledger, the content is
/// the selected section's occupant. dsh floats an 800x800 panel; a phone gets
/// the same two levels as pages, the section list and then one section, and a
/// wide window the panel's rail beside the content.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.slots,
    required this.i18n,
    required this.onClose,
    this.initialSection,
  });

  final SlotRegistry slots;
  final DshI18n i18n;

  /// Leaves the settings.
  final VoidCallback onClose;

  /// The section to open on (null: the first, or the list on a phone).
  final String? initialSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _active;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _active = widget.initialSection;
    // The ledger tick keeps the navigation fresh: registrants come and go with
    // the connection and re-register with fresh text on a locale change.
    _sub = widget.slots.changes.listen((name) {
      if (name == _sectionSlot.name && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  String _t(String key) => widget.i18n.t('settings', key);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final entries = widget.slots.entries(_sectionSlot);
    // Entries can unregister underneath the requested id.
    final active = entries.any((e) => e.id == _active) ? _active : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= settingsTwoColumnWidth;
        final selected = wide ? (active ?? entries.firstOrNull?.id) : active;
        return ColoredBox(
          color: theme.color('--dsw-alias-bg-layer-2'),
          child: SafeArea(
            key: const ValueKey('settings-page'),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 188,
                        child: _Nav(
                          title: _t('title'),
                          entries: entries,
                          active: selected,
                          onSelect: (id) => setState(() => _active = id),
                          onBack: widget.onClose,
                          backLabel: widget.i18n.t('common', 'back'),
                        ),
                      ),
                      Expanded(child: _content(selected, entries, wide: true)),
                    ],
                  )
                : (selected == null
                      ? _Nav(
                          title: _t('title'),
                          entries: entries,
                          active: null,
                          onSelect: (id) => setState(() => _active = id),
                          onBack: widget.onClose,
                          backLabel: widget.i18n.t('common', 'back'),
                          phone: true,
                        )
                      : _content(selected, entries, wide: false)),
          ),
        );
      },
    );
  }

  Widget _content(
    String? id,
    List<SlotEntryInfo> entries, {
    required bool wide,
  }) {
    final theme = context.dsh;
    SlotEntryInfo? entry;
    for (final e in entries) {
      if (e.id == id) entry = e;
    }
    final body = id == null
        ? null
        : widget.slots.renderOnly(_sectionSlot, id, const SettingsOwner());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DshSpace.sm,
            DshSpace.sm,
            DshSpace.sm,
            0,
          ),
          child: Row(
            children: [
              if (!wide)
                _IconTap(
                  key: const ValueKey('settings-section-back'),
                  label: widget.i18n.t('common', 'back'),
                  onTap: () => setState(() => _active = null),
                  child: Transform.rotate(
                    angle: 3.14159265,
                    child: DshIcon(
                      DshIcons.chevronRight,
                      color: theme.labelPrimary,
                    ),
                  ),
                )
              else
                const SizedBox(width: DshSpace.sm),
              Expanded(
                child: Text(
                  entry?.label ?? '',
                  key: const ValueKey('settings-section-title'),
                  style: theme
                      .textStyle('--dsw-font-base-strong-16')
                      .copyWith(color: theme.labelPrimary),
                ),
              ),
              if (wide)
                _IconTap(
                  key: const ValueKey('settings-close'),
                  label: _t('close'),
                  onTap: widget.onClose,
                  child: DshIcon(
                    DshIcons.close,
                    size: 14,
                    color: theme.labelPrimary,
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: body ?? const SizedBox.shrink()),
      ],
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Center(child: child)),
    ),
  );
}

/// The navigation: the title and one cell per section (dsh `.nav`).
class _Nav extends StatelessWidget {
  const _Nav({
    required this.title,
    required this.entries,
    required this.active,
    required this.onSelect,
    required this.onBack,
    required this.backLabel,
    this.phone = false,
  });

  final String title;
  final List<SlotEntryInfo> entries;
  final String? active;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;
  final String backLabel;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        phone ? DshSpace.sm : 12,
        phone ? DshSpace.sm : 22,
        phone ? DshSpace.sm : 12,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconTap(
                key: const ValueKey('settings-back'),
                label: backLabel,
                onTap: onBack,
                child: Transform.rotate(
                  angle: 3.14159265,
                  child: DshIcon(
                    DshIcons.chevronRight,
                    color: theme.labelPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  key: const ValueKey('settings-title'),
                  style: theme
                      .textStyle('--dsw-font-base-strong-16')
                      .copyWith(color: theme.labelPrimary),
                ),
              ),
            ],
          ),
          SizedBox(height: phone ? DshSpace.sm : 18),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final e in entries)
                  _Cell(
                    entry: e,
                    selected: e.id == active,
                    onTap: () => onSelect(e.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final SlotEntryInfo entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: entry.label,
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('settings-nav-${entry.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
            decoration: theme.cornerDecoration(
              theme.radiusMd,
              color: selected
                  ? theme.color('--dsw-specific-sidebar-nav-item-active')
                  : null,
            ),
            child: Row(
              children: [
                DshIcon(
                  _navIcon(entry.id),
                  size: 16,
                  color: theme.labelPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.label ?? entry.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelPrimary),
                  ),
                ),
                DshIcon(
                  DshIcons.chevronRight,
                  color: theme.color('--dsw-alias-label-caption'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
