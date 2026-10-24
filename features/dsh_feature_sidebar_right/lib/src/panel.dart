import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'guide.dart';
import 'state.dart';

/// The body slot as this feature uses it.
final Slot<SidebarTabOwner, Widget> paneTabSlot = DshSlots.sidebarRightPaneTab
    .typed<SidebarTabOwner, Widget>();

/// A tab's title as its chip shows it (a live terminal name).
final Slot<SidebarTabOwner, Widget> paneTabTitleSlot = DshSlots
    .sidebarRightPaneTabTitle
    .typed<SidebarTabOwner, Widget>();

/// One provider's card on the guide page.
final Slot<SidebarGuideOwner, Widget> guideEntrySlot = DshSlots
    .sidebarRightTabGuideEntry
    .typed<SidebarGuideOwner, Widget>();

/// The panel: the tab strip with the collapse control, over the bodies of the
/// open tabs. Bodies stay mounted while another tab is in front, so what a
/// person scrolled or expanded is still there when they come back.
class SidebarPanel extends StatelessWidget {
  const SidebarPanel({
    super.key,
    required this.state,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.onCollapse,
    this.bordered = false,
  });

  final SidebarState state;
  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n i18n;
  final VoidCallback onCollapse;

  /// A hairline on the left edge (the inline column).
  final bool bordered;

  String _title(SidebarTab tab) {
    if (tab.kind == filesTabKind) return i18n.t('sidebarFiles', 'type.label');
    if (tab.kind == guideTabKind) {
      return i18n.t('sidebarRight', 'tab.guide.title');
    }
    final address = parseSessionFileAddress(tab.contentId);
    return address == null ? tab.contentId : pathPartsOf(address.path).name;
  }

  SidebarTabOwner _tabOwner(SidebarTab tab) => SidebarTabOwner(
    session: owner,
    id: tab.id,
    kind: tab.kind,
    contentId: tab.contentId,
    actions: state,
    params: tab.params,
    line: tab.line,
    revision: tab.revision,
    visible: tab.id == state.activeId,
  );

  /// The chip's label: the type's own title when it registered one (a terminal
  /// shows its live name), else the tab's text.
  Widget? _titleWidget(SidebarTab tab) =>
      slots.renderKeyed(paneTabTitleSlot, tab.kind, _tabOwner(tab));

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final tabs = state.tabs;
        final activeIndex = tabs.indexWhere((t) => t.id == state.activeId);
        return DshDecoratedBox(
          key: const ValueKey('sidebar-panel'),
          decoration: BoxDecoration(
            color: theme.bgBase,
            border: bordered
                ? Border(
                    left: BorderSide(
                      color: theme.color('--dsw-alias-border-l4'),
                      width: dshHairlineOf(context),
                    ),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Strip(
                tabs: tabs,
                activeId: state.activeId,
                title: _title,
                titleWidget: _titleWidget,
                closeLabel: i18n.t('sidebarRight', 'dock.closeTab'),
                collapseLabel: i18n.t('sidebarRight', 'chrome.collapseAria'),
                addLabel: i18n.t('sidebarRight', 'dock.addTab'),
                onAdd: state.canAddTab
                    ? () => state.openTab(guideTabKind)
                    : null,
                onSelect: state.select,
                onClose: state.close,
                onCollapse: onCollapse,
              ),
              Expanded(
                child: IndexedStack(
                  index: activeIndex < 0 ? 0 : activeIndex,
                  children: [
                    for (final tab in tabs)
                      KeyedSubtree(
                        key: ValueKey('sidebar-tab-${tab.id}'),
                        child: tab.kind == guideTabKind
                            ? GuideBody(
                                key: const ValueKey('sidebar-guide'),
                                state: state,
                                tabId: tab.id,
                                owner: owner,
                                slots: slots,
                              )
                            : slots.renderKeyed(
                                    paneTabSlot,
                                    tab.kind,
                                    _tabOwner(tab),
                                  ) ??
                                  Center(
                                    child: DshChromeText(
                                      i18n.t('sidebarRight', 'tab.unavailable'),
                                      style: theme
                                          .textStyle('--dsw-font-s-14')
                                          .copyWith(
                                            color: theme.labelSecondary,
                                          ),
                                    ),
                                  ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.tabs,
    required this.activeId,
    required this.title,
    required this.titleWidget,
    required this.closeLabel,
    required this.collapseLabel,
    required this.addLabel,
    required this.onAdd,
    required this.onSelect,
    required this.onClose,
    required this.onCollapse,
  });

  final List<SidebarTab> tabs;
  final String activeId;
  final String Function(SidebarTab) title;
  final Widget? Function(SidebarTab) titleWidget;
  final String closeLabel;
  final String collapseLabel;
  final String addLabel;

  /// Opens the guide; null while one is open.
  final VoidCallback? onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshDecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.color('--dsw-alias-border-l4'),
            width: dshHairlineOf(context),
          ),
        ),
      ),
      child: SizedBox(
        height: DshSpace.touch,
        child: Row(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('sidebar-tabs'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: DshSpace.sm),
                children: [
                  for (final tab in tabs)
                    _TabChip(
                      key: ValueKey('chip-${tab.id}'),
                      label: title(tab),
                      content: titleWidget(tab),
                      closeKeyName: titleWidget(tab) == null
                          ? title(tab)
                          : tab.id,
                      selected: tab.id == activeId,
                      closeLabel: tab.kind == filesTabKind ? null : closeLabel,
                      onTap: () => onSelect(tab.id),
                      onClose: () => onClose(tab.id),
                    ),
                  if (onAdd != null)
                    Semantics(
                      button: true,
                      label: addLabel,
                      child: GestureDetector(
                        key: const ValueKey('sidebar-add'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onAdd,
                        child: SizedBox(
                          width: DshSpace.touch,
                          height: DshSpace.touch,
                          child: Center(
                            child: DshIcon(
                              DshIcons.plus,
                              size: 16,
                              color: theme.labelSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: collapseLabel,
              child: GestureDetector(
                key: const ValueKey('sidebar-collapse'),
                behavior: HitTestBehavior.opaque,
                onTap: onCollapse,
                child: SizedBox(
                  width: DshSpace.touch,
                  height: DshSpace.touch,
                  child: Center(
                    child: DshIcon(
                      DshIcons.close,
                      size: 16,
                      color: theme.labelSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.label,
    required this.content,
    required this.closeKeyName,
    required this.selected,
    required this.closeLabel,
    required this.onTap,
    required this.onClose,
  });

  final String label;

  /// The type's own title, drawn instead of [label] when it has one.
  final Widget? content;

  /// What the close control's key is built from (the label, or the tab's id when the type draws its own title).
  final String closeKeyName;
  final bool selected;
  final String? closeLabel;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final color = selected ? theme.labelPrimary : theme.labelSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DshContainer(
          constraints: const BoxConstraints(maxWidth: 180),
          padding: const EdgeInsets.only(left: DshSpace.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? theme.color('--dsw-alias-brand-primary')
                    : theme.bgBase,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: content == null
                    ? DshChromeText(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(color: color),
                      )
                    : DefaultTextStyle(
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(color: color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: IconTheme(
                          data: IconThemeData(color: color),
                          child: content!,
                        ),
                      ),
              ),
              if (closeLabel != null)
                Semantics(
                  button: true,
                  label: closeLabel,
                  child: GestureDetector(
                    key: ValueKey('close-$closeKeyName'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: SizedBox(
                      width: 32,
                      height: DshSpace.touch,
                      child: Center(
                        child: DshIcon(
                          DshIcons.close,
                          size: 12,
                          color: theme.color('--dsw-alias-label-tertiary'),
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: DshSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}
