import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Slot<PluginItemOwner, Widget> _itemSlot = DshSlots.pluginsItem
    .typed<PluginItemOwner, Widget>();

/// The Plugins section: dsh draws the official plugins' configuration on its
/// Plugins page (`ui-plugin-manager`), one card per `plugins.item` occupant
/// that opens the plugin's own page. This is that surface, scoped to those
/// cards (installing and managing bundles is not ported). The cards follow the
/// slot's registrations, so a plugin whose namespace the host stops serving
/// disappears from the list, and a page open on it closes.
///
/// A phone and a wide window drive it the same way: the section's content is
/// the card list, or, once a card is opened, that plugin's page under a crumb
/// back to the list. The system back gesture closes the page first.
class PluginsSection extends StatefulWidget {
  const PluginsSection({super.key, required this.slots, required this.i18n});

  final SlotRegistry slots;
  final DshI18n Function() i18n;

  @override
  State<PluginsSection> createState() => _PluginsSectionState();
}

class _PluginsSectionState extends State<PluginsSection> {
  String? _open;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.slots.changes.listen((name) {
      if (name == _itemSlot.name && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  String _t(String key, {Map<String, Object?> params = const {}}) =>
      widget.i18n().t('pluginManager', key, params: params);

  Widget _summary(String id) =>
      widget.slots.renderOnly(
        _itemSlot,
        id,
        const PluginItemOwner(view: PluginItemView.summary),
      ) ??
      const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final entries = widget.slots.entries(_itemSlot);
    // The entry can withdraw underneath an open page.
    SlotEntryInfo? open;
    for (final e in entries) {
      if (e.id == _open) open = e;
    }
    return PopScope(
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _open = null);
      },
      child: open == null
          ? _List(
              key: const ValueKey('plugins-list'),
              title: _t('basicTitle'),
              entries: entries,
              openLabel: (name) => _t('openDetail', params: {'name': name}),
              summary: _summary,
              onOpen: (id) => setState(() => _open = id),
            )
          : _Detail(
              key: ValueKey('plugin-detail-${open.id}'),
              entry: open,
              crumb: _t('crumbRoot'),
              backLabel: _t('backToList'),
              summary: _summary(open.id),
              page:
                  widget.slots.renderOnly(
                    _itemSlot,
                    open.id,
                    const PluginItemOwner(view: PluginItemView.page),
                  ) ??
                  const SizedBox.shrink(),
              onBack: () => setState(() => _open = null),
            ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    super.key,
    required this.title,
    required this.entries,
    required this.openLabel,
    required this.summary,
    required this.onOpen,
  });

  final String title;
  final List<SlotEntryInfo> entries;
  final String Function(String name) openLabel;
  final Widget Function(String id) summary;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return SingleChildScrollView(
      // The cards reach 8px past their content on both sides, as dsh's do.
      padding: const EdgeInsets.fromLTRB(
        DshSpace.lg,
        0,
        DshSpace.lg,
        DshSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: DshLineText(
              title,
              style: theme
                  .textStyle('--dsw-font-s-strong-14')
                  .copyWith(color: theme.labelPrimary),
            ),
          ),
          for (final e in entries)
            _Card(
              entry: e,
              openLabel: openLabel(e.label ?? e.id),
              summary: summary(e.id),
              onTap: () => onOpen(e.id),
            ),
        ],
      ),
    );
  }
}

/// One official plugin as a card that opens its page (dsh `ItemCard`): a
/// framed icon, the title, and the one-liner the occupant renders in its
/// summary view.
class _Card extends StatefulWidget {
  const _Card({
    required this.entry,
    required this.openLabel,
    required this.summary,
    required this.onTap,
  });

  final SlotEntryInfo entry;
  final String openLabel;
  final Widget summary;
  final VoidCallback onTap;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      button: true,
      label: widget.openLabel,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey('plugin-item-${widget.entry.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: theme.cornerDecoration(
              theme.number('--dsw-radius-xl'),
              color: _hovered ? theme.interactiveBgHover : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: theme.cornerDecoration(
                    theme.radiusLg,
                    borderColor: theme.borderL3,
                    borderWidth: dshHairline,
                  ),
                  child: DshIcon(
                    DshIcons.cordisPlugin,
                    size: 24,
                    color: theme.labelSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DshLineText(
                        widget.entry.label ?? widget.entry.id,
                        maxLines: 1,
                        style: theme
                            .textStyle('--dsw-font-s-strong-14')
                            .copyWith(color: theme.labelPrimary),
                      ),
                      DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(
                              color: theme.color('--dsw-alias-label-tertiary'),
                            ),
                        child: widget.summary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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

/// One plugin's page (dsh `ItemDetail`): the crumb back to the cards, the
/// title over the one-liner, and the form the occupant renders.
class _Detail extends StatelessWidget {
  const _Detail({
    super.key,
    required this.entry,
    required this.crumb,
    required this.backLabel,
    required this.summary,
    required this.page,
    required this.onBack,
  });

  final SlotEntryInfo entry;
  final String crumb;
  final String backLabel;
  final Widget summary;
  final Widget page;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.lg + 8,
        0,
        DshSpace.lg + 8,
        DshSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: backLabel,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('plugin-detail-back'),
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.rotate(
                        angle: 3.14159265,
                        child: DshIcon(
                          DshIcons.chevronRight,
                          color: theme.color('--dsw-alias-label-tertiary'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      DshLineText(
                        crumb,
                        style: theme
                            .textStyle('--dsw-font-xxs-12')
                            .copyWith(
                              color: theme.color('--dsw-alias-label-tertiary'),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DshLineText(
            entry.label ?? entry.id,
            key: const ValueKey('plugin-detail-title'),
            style: theme
                .textStyle('--dsw-font-l-20')
                .copyWith(
                  color: theme.labelPrimary,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelSecondary),
            child: summary,
          ),
          const SizedBox(height: 32),
          KeyedSubtree(key: const ValueKey('plugin-detail-page'), child: page),
        ],
      ),
    );
  }
}
