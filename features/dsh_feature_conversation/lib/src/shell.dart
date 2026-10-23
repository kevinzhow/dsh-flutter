import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'composer.dart';

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
  });

  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n i18n;
  final Slot<SessionOwner, Widget> viewSlot;
  final Slot<SessionOwner, Widget> composerSlot;
  final Slot<SessionOwner, Widget> dockSlot;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return StreamBuilder<SessionSnapshot>(
      stream: owner.session.snapshot.changes,
      initialData: owner.session.snapshot.value,
      builder: (context, snap) {
        final s = snap.data!;
        final views = slots.renderList(viewSlot, owner);
        Widget body;
        if (s.openState == OpenState.error) {
          body = _Notice(
            key: const ValueKey('session-open-failed'),
            title: i18n.t(appNamespace, 'session.openFailed'),
            body: '${s.openError}',
          );
        } else if (s.openState != OpenState.open) {
          body = Center(
            key: const ValueKey('session-loading'),
            child: Text(
              i18n.t(appNamespace, 'session.loading'),
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(color: theme.labelSecondary),
            ),
          );
        } else {
          body = views.isEmpty ? const SizedBox.shrink() : views.first;
        }
        final composer = s.removed
            ? _Notice(title: i18n.t(appNamespace, 'session.removed'), body: '')
            : (slots.renderChain(composerSlot, owner) ??
                  DefaultComposer(owner: owner, i18n: i18n, slots: slots));
        final sidebar =
            MediaQuery.sizeOf(context).width >= sidebarInlineMinWindowWidth
            ? slots.renderSingle(
                DshSlots.rightbarSession.typed<SessionOwner, Widget>(),
                owner,
              )
            : null;
        final main = Column(
          children: [
            if (s.lastAgentError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DshSpace.lg,
                  DshSpace.sm,
                  DshSpace.lg,
                  0,
                ),
                child: Text(
                  '${i18n.t(appNamespace, 'session.agentError')}: ${s.lastAgentError}',
                  key: const ValueKey('agent-error'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: theme.color('--dsw-alias-state-error-primary'),
                      ),
                ),
              ),
            Expanded(child: body),
            if (!s.removed)
              for (final dock in slots.renderList(dockSlot, owner))
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DshSpace.readableWidth,
                    ),
                    child: dock,
                  ),
                ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DshSpace.readableWidth,
                ),
                child: composer,
              ),
            ),
          ],
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
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme
                  .textStyle('--dsw-font-base-strong-16')
                  .copyWith(color: theme.labelPrimary),
            ),
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.sm),
                child: Text(
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
