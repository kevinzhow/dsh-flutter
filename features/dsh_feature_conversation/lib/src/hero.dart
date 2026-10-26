import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart' show DshThemeData;
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'composer.dart';

/// The conversation area of a blank session (dsh `ui-conversation`
/// `EmptyHero` + the hero form of `ConversationContent`): the
/// headline with the Preview badge, the workspace chip, and the composer.
///
/// The whole stack is centered in the area, as dsh web draws it at every width;
/// above a keyboard the area is what is left, so the stack simply rises.
///
/// With no [owner] (nothing is open yet: the New session screen before a
/// workspace is chosen) the composer is inert and the chip reads "Choose
/// workspace".
class ConversationHero extends StatefulWidget {
  const ConversationHero({
    super.key,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.workspaces,
    this.composer,
    this.dock,
  });

  final SessionOwner? owner;
  final SlotRegistry slots;
  final DshI18n i18n;

  /// The workspace list and navigation; null where the app has none (the chip
  /// then only echoes the session's folder).
  final WorkspaceServices? workspaces;

  /// The composer card; with no [owner] the hero draws the inert one itself.
  final Widget? composer;

  /// What the input dock holds (the todo list), above the composer.
  final Widget? dock;

  @override
  State<ConversationHero> createState() => _ConversationHeroState();
}

class _ConversationHeroState extends State<ConversationHero> {
  final LayerLink _chip = LayerLink();
  bool _open = false;
  String? _pending;
  String? _error;
  StreamSubscription<WorkspaceSnapshot>? _sub;

  Slot<HeroWorkspaceOwner, Widget> get _picker =>
      DshSlots.conversationHeroWorkspace.typed<HeroWorkspaceOwner, Widget>();

  @override
  void initState() {
    super.initState();
    _sub = widget.workspaces?.workspaces.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  String _c(String key) => widget.i18n.t('conversation', key);

  /// The chip label, resolved top-down as dsh does: a just-picked workspace,
  /// then (with a session) its workspace, then the session folder while the
  /// list is still loading, else nothing (the "Choose workspace" call to
  /// action).
  String? _chipTitle() {
    final snapshot = widget.workspaces?.workspaces.value;
    final owner = widget.owner;
    final pending = _pending == null ? null : snapshot?.byId(_pending!);
    final sessionWorkspace = owner == null
        ? null
        : snapshot?.ofSession(owner.sessionId);
    String? stored = pending?.title;
    if (stored == null && owner != null) {
      final cwd = owner.cwd;
      stored =
          sessionWorkspace?.title ??
          (snapshot?.phase == WorkspacePhase.ready || cwd == null || cwd.isEmpty
              ? null
              : _folderLabel(cwd));
    }
    return stored == null
        ? null
        : workspaceDisplayTitle(stored, _c('workspace.defaultName'));
  }

  static String _folderLabel(String cwd) {
    final base = workspaceTitleOf(cwd);
    return base.isNotEmpty ? base : cwd;
  }

  Future<void> _select(String workspaceId) async {
    final workspaces = widget.workspaces;
    if (workspaces == null) return;
    setState(() {
      _open = false;
      _pending = workspaceId;
      _error = null;
    });
    try {
      await workspaces.openWorkspace(
        workspaceId,
        from: widget.owner?.sessionId,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        if (_pending == workspaceId) _pending = null;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final snapshot = widget.workspaces?.workspaces.value;
    final owner = widget.owner;
    final sessionWorkspace = owner == null
        ? null
        : snapshot?.ofSession(owner.sessionId);
    // A pick clears once the session lands in it, or the workspace vanished
    // from a ready list.
    if (_pending != null &&
        (sessionWorkspace?.workspaceId == _pending ||
            (snapshot?.phase == WorkspacePhase.ready &&
                snapshot?.byId(_pending!) == null))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pending = null);
      });
    }
    final title = _chipTitle();
    final chip = WorkspaceChip(
      link: _chip,
      label: title,
      placeholder: _c('hero.chooseWorkspace'),
      open: _open,
      enabled: widget.workspaces != null,
      onPressed: () => setState(() => _open = !_open),
    );
    final picker = widget.slots.renderSingle(
      _picker,
      HeroWorkspaceOwner(
        open: _open,
        selectedId: _pending ?? sessionWorkspace?.workspaceId,
        anchor: _chip,
        onPick: (id) => unawaited(_select(id)),
        onClose: () {
          if (mounted && _open) setState(() => _open = false);
        },
      ),
    );
    final chipRow = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
      child: Row(
        children: [
          Flexible(flex: 0, child: chip),
          ?widget.slots.renderSingle(
            DshSlots.conversationHeroAgentPreset.typed<SessionOwner?, Widget>(),
            widget.owner,
          ),
          // The picker draws nothing in place: its menu, sheet and dialogs
          // are overlays and routes.
          ?picker,
        ],
      ),
    );
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
            child: DshChromeText(
              '${widget.i18n.t('app', 'sessions.createFailed')}: $_error',
              key: const ValueKey('hero-error'),
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(
                    color: theme.color('--dsw-alias-state-error-primary'),
                  ),
            ),
          );
    final headline = HeroHeadline(i18n: widget.i18n);
    final stack = <Widget>[
      if (widget.dock != null) widget.dock!,
      widget.composer ??
          InertComposer(
            i18n: widget.i18n,
            onPressed: widget.workspaces == null
                ? null
                : () => setState(() => _open = !_open),
          ),
    ];
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DshSpace.readableWidth),
            child: Column(
              key: const ValueKey('hero'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: headline,
                ),
                const SizedBox(height: 16),
                chipRow,
                ?error,
                const SizedBox(height: 8),
                ...stack,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The headline and the Preview badge (dsh `HeroShell`). dsh leads the line
/// with the DeepSeek fish through its `conversation.hero.brand.mark` slot;
/// Whalee leads it with its own mark, the whale emoji, in the same 34px box.
class HeroHeadline extends StatelessWidget {
  const HeroHeadline({super.key, required this.i18n});

  final DshI18n i18n;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final base = theme.textStyle('--dsw-font-xl-24');
    // 26/32, weight 500: the figma headline, a size between dsh's tokens.
    final title = base
        .apply(fontSizeFactor: 26 / 24)
        .copyWith(
          color: theme.labelPrimary,
          fontWeight: FontWeight.w500,
          height: 32 / 26,
        );
    final badge = theme
        .textStyle('--dsw-font-markdown-code')
        .copyWith(
          color: theme.color('--dsw-alias-label-primary-bluish'),
          fontWeight: FontWeight.w500,
          height: 18 / 12,
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 12,
      children: [
        // dsh leads the line with its brand mark (34px); Whalee's is the whale
        // emoji.
        const DshWhaleMark(size: 34),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 7,
          runSpacing: 4,
          children: [
            DshChromeText(
              i18n.t('conversation', 'hero.headline'),
              key: const ValueKey('hero-headline'),
              style: title,
            ),
            // A superscript riding the title's top-right.
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DshDecoratedBox(
                decoration: BoxDecoration(
                  color: theme.color('--dsw-alias-state-business-tertiary'),
                  border: Border.all(
                    color: theme.color('--dsw-alias-interactive-bg-hover'),
                    width: dshHairlineOf(context),
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(7, 1, 7, 0),
                  child: DshChromeText(
                    i18n.t('conversation', 'hero.preview'),
                    key: const ValueKey('hero-preview'),
                    style: badge,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The workspace chip (dsh `WorkspaceChip`): folder, label and chevron, always
/// interactive. Without a [label] it is the "Choose workspace" call to action
/// with the closed folder.
class WorkspaceChip extends StatefulWidget {
  const WorkspaceChip({
    super.key,
    required this.link,
    required this.label,
    required this.placeholder,
    required this.open,
    required this.enabled,
    required this.onPressed,
  });

  final LayerLink link;
  final String? label;
  final String placeholder;
  final bool open;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<WorkspaceChip> createState() => _WorkspaceChipState();
}

class _WorkspaceChipState extends State<WorkspaceChip> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final lit = (_hover && widget.enabled) || widget.open;
    final label = widget.label ?? widget.placeholder;
    return TapRegion(
      groupId: widget.link,
      child: CompositedTransformTarget(
        link: widget.link,
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          expanded: widget.open,
          label: widget.placeholder,
          value: widget.label,
          excludeSemantics: true,
          onTap: widget.enabled ? widget.onPressed : null,
          child: FocusableActionDetector(
            enabled: widget.enabled,
            mouseCursor: widget.enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onShowHoverHighlight: (v) => setState(() => _hover = v),
            onShowFocusHighlight: (v) => setState(() => _focus = v),
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onPressed();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              key: const ValueKey('hero-workspace-chip'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? widget.onPressed : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 360, minHeight: 28),
                child: DshDecoratedBox(
                  decoration: BoxDecoration(
                    color: lit
                        ? theme.color('--dsw-alias-interactive-bg-hover')
                        : null,
                    borderRadius: BorderRadius.circular(theme.radiusSm),
                    border: _focus
                        ? Border.all(
                            color: theme.color(
                              '--dsw-alias-state-business-primary',
                            ),
                            width: theme.number('--dsw-focus-ring-width'),
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DshIcon(
                          widget.label == null
                              ? DshIcons.folderClose
                              : DshIcons.folderOpen,
                          size: 16,
                          color: theme.labelPrimary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: DshChromeText(
                            label,
                            key: const ValueKey('hero-workspace-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _labelStyle(theme),
                          ),
                        ),
                        const SizedBox(width: 4),
                        DshIcon(
                          DshIcons.chevronDown,
                          size: 12,
                          color: theme.color('--dsw-alias-label-caption'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _labelStyle(DshThemeData theme) => theme
      .textStyle('--dsw-font-xs-13')
      .copyWith(
        color: theme.labelPrimary,
        fontWeight: FontWeight.w500,
        height: 20 / 13,
      );
}

/// The composer card before any workspace is chosen (dsh's inert input bar):
/// the same card with a dashed outline, its controls disabled and the draft a
/// hint that says what to do first. The whole card is the pick target.
class InertComposer extends StatelessWidget {
  const InertComposer({super.key, required this.i18n, this.onPressed});

  final DshI18n i18n;

  /// Raise the workspace picker.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      key: const ValueKey('inert-composer'),
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.lg),
      child: Semantics(
        button: true,
        label: i18n.t('conversation', 'placeholder.workspace'),
        excludeSemantics: true,
        onTap: onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: ComposerCard(
            hero: true,
            dashed: true,
            draft: DshChromeText(
              i18n.t('conversation', 'placeholder.workspace'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(
                    color: theme.color('--dsw-alias-label-caption'),
                    height: 24 / 14,
                  ),
            ),
            leading: [
              ComposerAttachButton(
                label: i18n.t('app', 'attach.title'),
                onPressed: null,
              ),
            ],
            trailing: [
              ComposerRoundButton(
                icon: DshShellIcons.send,
                label: i18n.t('conversation', 'input.send'),
                onPressed: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
