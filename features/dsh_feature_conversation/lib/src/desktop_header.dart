import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'view_selection.dart';
import 'breadcrumbs.dart';

/// The Session header at desktop widths (dsh `ConversationSessionHeader`): the
/// title crumb with the `actions` cluster, the `utilities` row and the `corner`
/// seat, then the view tabs, over a hairline. A Session that has not started
/// keeps only the corner. Header seats read the same [SessionOwner] the phone
/// header does.
class DesktopSessionHeader extends StatefulWidget {
  const DesktopSessionHeader({
    super.key,
    required this.owner,
    required this.i18n,
    required this.slots,
  });

  final SessionOwner owner;
  final DshI18n i18n;
  final SlotRegistry slots;

  @override
  State<DesktopSessionHeader> createState() => _DesktopSessionHeaderState();
}

class _DesktopSessionHeaderState extends State<DesktopSessionHeader> {
  StreamSubscription<Object?>? _projections;
  StreamSubscription<Object?>? _session;
  StreamSubscription<String>? _slotChanges;

  @override
  void initState() {
    super.initState();
    _projections = widget.owner.session.projections.changes.listen(_changed);
    _session = widget.owner.session.snapshot.changes.listen(_changed);
    _slotChanges = widget.slots.changes.listen((_) => _changed(null));
  }

  void _changed(Object? _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_projections?.cancel());
    unawaited(_session?.cancel());
    unawaited(_slotChanges?.cancel());
    super.dispose();
  }

  List<Widget> _list(Slot<SessionOwner, Widget> slot) =>
      widget.slots.renderList(slot, widget.owner);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final owner = widget.owner;
    final i18n = widget.i18n;
    final title =
        (owner.session.projections.get('title') as String?)?.trim() ?? '';
    final blank = owner.session.snapshot.value.blank && title.isEmpty;
    final actions = _list(
      DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
    );
    final utilities = _list(
      DshSlots.conversationSessionHeaderUtilities.typed<SessionOwner, Widget>(),
    );
    final corner = widget.slots.renderSingle(
      DshSlots.conversationSessionHeaderCorner.typed<SessionOwner, Widget>(),
      owner,
    );
    final viewSlot = DshSlots.conversationView.typed<SessionOwner, Widget>();
    final views = widget.slots.entries(viewSlot);
    final selection = viewSelectionOf(owner.session);
    final showTabs = !blank && views.length > 1;
    final clearance = FrameInsetsScope.of(context).leadingClearance;
    final hairline = dshHairlineOf(context);
    final phone = PhoneChrome.maybeOf(context);
    if (phone != null) {
      return _phoneHeader(
        context,
        phone,
        title: blank
            ? ''
            : (title.isEmpty ? browserTitleFallback(i18n) : title),
        showTabs: showTabs,
        views: views,
        selection: selection,
        utilities: blank ? const [] : utilities,
        corner: corner,
        hairline: hairline,
        border: blank ? null : theme.color('--dsw-alias-border-l3'),
      );
    }
    final cornerSeat = corner == null
        ? null
        : Padding(padding: const EdgeInsets.only(left: 8), child: corner);
    final titleRow = Padding(
      padding: EdgeInsets.only(
        left: clearance > 20 ? clearance - 20 : 0,
        right: corner == null ? 0 : 0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Row(
          children: [
            if (!blank)
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: SessionBreadcrumbs(
                        owner: owner,
                        slots: widget.slots,
                        i18n: i18n,
                        fallback: _Crumb(
                          key: const ValueKey('session-title'),
                          text: title.isEmpty
                              ? browserTitleFallback(i18n)
                              : title,
                        ),
                      ),
                    ),
                    for (final a in actions) ...[const SizedBox(width: 10), a],
                  ],
                ),
              )
            else
              const Spacer(),
            if (!blank && utilities.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < utilities.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      utilities[i],
                    ],
                  ],
                ),
              ),
            if (cornerSeat != null) cornerSeat,
          ],
        ),
      ),
    );
    return DshContainer(
      key: const ValueKey('desktop-session-header'),
      constraints: BoxConstraints(minHeight: showTabs ? 76 : 0),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        corner == null ? 28 : 12,
        showTabs ? 0 : (blank ? 0 : 10),
      ),
      decoration: BoxDecoration(
        border: blank
            ? null
            : Border(
                bottom: BorderSide(
                  color: theme.color('--dsw-alias-border-l3'),
                  width: hairline,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          titleRow,
          if (showTabs)
            ValueListenableBuilder<String?>(
              valueListenable: selection,
              builder: (context, chosen, _) {
                final active = views.any((v) => v.id == chosen)
                    ? chosen
                    : views.first.id;
                return Padding(
                  padding: const EdgeInsets.only(top: 10, left: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < views.length; i++) ...[
                        if (i > 0) const SizedBox(width: 36),
                        _Tab(
                          key: ValueKey('view-tab-${views[i].id}'),
                          label: views[i].label ?? views[i].id,
                          active: views[i].id == active,
                          onTap: () => selection.value = views[i].id,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

extension on _DesktopSessionHeaderState {
  /// The phone header: the top bar (menu, title, new Session) over the view
  /// tabs, with the utilities and the corner seat at the tabs' trailing end.
  Widget _phoneHeader(
    BuildContext context,
    PhoneChrome phone, {
    required String title,
    required bool showTabs,
    required List<SlotEntryInfo> views,
    required ValueNotifier<String?> selection,
    required List<Widget> utilities,
    required Widget? corner,
    required double hairline,
    required Color? border,
  }) {
    return DshContainer(
      key: const ValueKey('phone-session-header'),
      decoration: BoxDecoration(
        border: border == null
            ? null
            : Border(
                bottom: BorderSide(color: border, width: hairline),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PhoneTopBar(
            title: title,
            chrome: phone,
            titleWidget:
                title.isEmpty || !widget.owner.lineage.any((c) => c.subagent)
                ? null
                : SessionBreadcrumbs(
                    owner: widget.owner,
                    slots: widget.slots,
                    i18n: widget.i18n,
                    fallback: DshChromeText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          if (showTabs)
            ValueListenableBuilder<String?>(
              valueListenable: selection,
              builder: (context, chosen, _) {
                final active = views.any((v) => v.id == chosen)
                    ? chosen
                    : views.first.id;
                return Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < views.length; i++) ...[
                        if (i > 0) const SizedBox(width: 36),
                        _Tab(
                          key: ValueKey('view-tab-${views[i].id}'),
                          label: views[i].label ?? views[i].id,
                          active: views[i].id == active,
                          onTap: () => selection.value = views[i].id,
                        ),
                      ],
                      const Spacer(),
                      for (final u in utilities) ...[
                        u,
                        const SizedBox(width: 8),
                      ],
                      ?corner,
                    ],
                  ),
                );
              },
            )
          else if (utilities.isNotEmpty || corner != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final u in utilities) ...[u, const SizedBox(width: 8)],
                  ?corner,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The untitled label of a Session that has begun (`workspace` copy).
String browserTitleFallback(DshI18n i18n) =>
    i18n.t('workspace', 'session.untitled');

class _Crumb extends StatelessWidget {
  const _Crumb({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: DshContainer(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(),
        child: DshChromeText(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme
              .textStyle('--dsw-font-s-strong-14')
              .copyWith(color: theme.labelPrimary, height: 20 / 14),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final blue = theme.color('--dsw-alias-state-business-primary');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: DshChromeText(
                  label,
                  maxLines: 1,
                  style: theme
                      .textStyle('--dsw-font-xs-strong-13')
                      .copyWith(
                        color: active
                            ? blue
                            : theme.color('--dsw-alias-label-tertiary'),
                        height: 16 / 13,
                      ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: -1,
                height: 2,
                child: DshDecoratedBox(
                  decoration: BoxDecoration(
                    color: active ? blue : null,
                    borderRadius: BorderRadius.circular(2),
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
