import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'composer.dart';
import 'hero.dart';
import 'view_selection.dart';
import 'submission_policy.dart';

/// The conversation shell of one session (dsh `ConversationSession`): the
/// view area fed by `conversation.view`, the composer area fed by the
/// `conversation.composer` chain (falling back to [DefaultComposer]), and the
/// open/error states of the session itself.
class ConversationShell extends StatelessWidget {
  const ConversationShell({
    super.key,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.viewSlot,
    required this.composerSlot,
    required this.dockSlot,
    this.workspaces,
    this.preferences,
  });

  final SessionOwner owner;
  final ConversationPreferences? preferences;
  final SlotRegistry slots;
  final DshI18n i18n;
  final Slot<SessionOwner, Widget> viewSlot;
  final Slot<SessionOwner, Widget> composerSlot;
  final Slot<SessionOwner, Widget> dockSlot;

  /// The workspace list and navigation of the blank-session hero.
  final WorkspaceServices? workspaces;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: viewSelectionOf(owner.session),
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = context.dsh;
    return StreamBuilder<SessionSnapshot>(
      stream: owner.session.snapshot.changes,
      initialData: owner.session.snapshot.value,
      builder: (context, snap) {
        final s = snap.data!;
        final entries = slots.entries(viewSlot);
        final chosen = viewSelectionOf(owner.session).value;
        final active = entries.any((e) => e.id == chosen)
            ? chosen
            : (entries.isEmpty ? null : entries.first.id);
        final views = [
          if (active != null) ?slots.renderOnly(viewSlot, active, owner),
        ];
        Widget body;
        if (s.openState == OpenState.error) {
          body = _Notice(
            key: const ValueKey('session-open-failed'),
            title: i18n.t(appNamespace, 'session.openFailed'),
            body: '${s.openError}',
          );
        } else if (s.openState != OpenState.open && views.isEmpty) {
          body = Center(
            key: const ValueKey('session-loading'),
            child: DshChromeText(
              i18n.t(appNamespace, 'session.loading'),
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(color: theme.labelSecondary),
            ),
          );
        } else {
          // While the session opens the view shows its own placeholder (dsh's
          // ChatView owns the loading state); the text above is only for a
          // composition without a view.
          body = views.isEmpty ? const SizedBox.shrink() : views.first;
        }
        // A blank session shows the hero: the headline, the workspace chip and
        // the composer, instead of an empty transcript (dsh's hero phase).
        final hero =
            s.blank &&
            !s.removed &&
            (s.openState == OpenState.open || owner.summaryBlank == true);
        final composer = s.removed
            ? _Notice(title: i18n.t(appNamespace, 'session.removed'), body: '')
            : (slots.renderChain(composerSlot, owner) ??
                  DefaultComposer(
                    owner: owner,
                    preferences: preferences,
                    i18n: i18n,
                    slots: slots,
                    hero: hero,
                    placeholder: hero
                        ? i18n.t('conversation', 'placeholder.hero')
                        : null,
                  ));
        final sidebar =
            MediaQuery.sizeOf(context).width >= sidebarInlineMinWindowWidth &&
                !DshRightbarHost.owned(context)
            ? slots.renderSingle(
                DshSlots.rightbarSession.typed<SessionOwner, Widget>(),
                owner,
              )
            : null;
        final main = ConversationRegion(
          child: Column(
            children: [
              if (s.lastAgentError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DshSpace.lg,
                    DshSpace.sm,
                    DshSpace.lg,
                    0,
                  ),
                  child: DshChromeText(
                    '${i18n.t(appNamespace, 'session.agentError')}: ${s.lastAgentError}',
                    key: const ValueKey('agent-error'),
                    style: theme
                        .textStyle('--dsw-font-xxs-12')
                        .copyWith(
                          color: theme.color('--dsw-alias-state-error-primary'),
                        ),
                  ),
                ),
              if (hero)
                Expanded(
                  child: ConversationHero(
                    key: ValueKey('hero-${owner.sessionId}'),
                    owner: owner,
                    slots: slots,
                    i18n: i18n,
                    workspaces: workspaces,
                    composer: composer,
                    dock: _docks(slots.renderList(dockSlot, owner)),
                  ),
                )
              else ...[
                Expanded(child: body),
                if (!s.removed)
                  for (final dock in slots.renderList(dockSlot, owner))
                    _AxisSeat(child: dock),
                _AxisSeat(child: composer),
                if (!s.removed) ..._composerDock(context),
              ],
            ],
          ),
        );
        // Wide windows show the right sidebar beside the conversation.
        return sidebar == null
            ? main
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: main),
                  sidebar,
                ],
              );
      },
    );
  }
}

Widget? _docks(List<Widget> docks) => docks.isEmpty
    ? null
    : Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: docks,
      );

extension on ConversationShell {
  /// The pills under the composer card (dsh `conversation.composer.dock`),
  /// drawn inside the desktop frame only.
  List<Widget> _composerDock(BuildContext context) {
    if (!DshRightbarHost.owned(context)) return const [];
    final pills = slots.renderList(
      DshSlots.conversationComposerDock.typed<SessionOwner, Widget>(),
      owner,
    );
    if (pills.isEmpty) return const [];
    return [
      _AxisSeat(
        key: const ValueKey('composer-dock'),
        capped: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pills.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                pills[i],
              ],
            ],
          ),
        ),
      ),
    ];
  }
}

/// A seat of the composer stack on dsh's width axis (`InputBar.module.css`
/// `.root` / `.card`, `--dsh-composer-card-max-width`): the input card, the
/// docks and the pills sit on the same centre as the message column, which is
/// the scroll body's box without its margin and scrollbar gutter.
class _AxisSeat extends StatelessWidget {
  const _AxisSeat({super.key, required this.child, this.capped = true});

  final Widget child;

  /// Whether the seat is as wide as the composer area (cards) or only
  /// centred on the axis (the pills row).
  final bool capped;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final axis = DshChatAxis.of(context, constraints.maxWidth);
        return Padding(
          padding: EdgeInsets.only(right: axis.trailing),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: capped
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: axis.composerWidth),
                    child: child,
                  )
                : child,
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DshSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DshChromeText(
              title,
              textAlign: TextAlign.center,
              style: theme
                  .textStyle('--dsw-font-base-strong-16')
                  .copyWith(color: theme.labelPrimary),
            ),
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.sm),
                child: DshChromeText(
                  body,
                  textAlign: TextAlign.center,
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The area below the session header that holds the conversation and its
/// composer. The composer's floating menus never rise above its top edge, as
/// dsh keeps its menus clear of the header (`TOP_MARGIN` of `MenuView`).
class ConversationRegion extends StatefulWidget {
  const ConversationRegion({super.key, required this.child});

  final Widget child;

  /// The region's top edge in global coordinates, or null outside one.
  static double? topOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_RegionScope>()
        ?.regionKey;
    final box = scope?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero).dy;
  }

  @override
  State<ConversationRegion> createState() => _ConversationRegionState();
}

class _ConversationRegionState extends State<ConversationRegion> {
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) => _RegionScope(
    regionKey: _key,
    child: KeyedSubtree(key: _key, child: widget.child),
  );
}

class _RegionScope extends InheritedWidget {
  const _RegionScope({required this.regionKey, required super.child});

  final GlobalKey regionKey;

  @override
  bool updateShouldNotify(_RegionScope old) => old.regionKey != regionKey;
}
