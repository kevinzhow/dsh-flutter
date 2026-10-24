import 'dart:async';
import 'dart:convert' show base64Encode;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show Icons, InputBorder, InputDecoration, TextField, showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'attachment_text.dart';
import 'composer_text.dart';
import 'shell.dart' show ConversationRegion;

/// The default composer (dsh `ui-conversation` `InputBar`, phone subset): a
/// growing text field, a send button, and a stop button while a turn runs.
/// Sending while a turn runs queues the message behind it (dsh's default
/// `queue` mode). A takeover occupying the `conversation.composer` chain
/// (approval, a question) replaces this widget while it is pending.
class DefaultComposer extends StatefulWidget {
  const DefaultComposer({
    super.key,
    required this.owner,
    required this.i18n,
    this.slots,
    this.placeholder,
    this.hero = false,
  });

  final SessionOwner owner;
  final DshI18n i18n;

  /// The field's hint; the session default when null (the hero says what the
  /// blank conversation is for).
  final String? placeholder;

  /// The blank-session form: the draft keeps a two-line floor.
  final bool hero;

  /// Renders the draft rail through `conversation.input.attachments`.
  final SlotRegistry? slots;

  @override
  State<DefaultComposer> createState() => _DefaultComposerState();
}

/// The attach circle (dsh `.add`): 28px, the selector fill, the plus glyph.
class ComposerAttachButton extends StatefulWidget {
  const ComposerAttachButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<ComposerAttachButton> createState() => _ComposerAttachButtonState();
}

class _ComposerAttachButtonState extends State<ComposerAttachButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          key: const ValueKey('composer-attach'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: DshDecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hover && enabled
                    ? theme.color('--dsw-alias-interactive-bg-hover-solid')
                    : theme.color('--dsw-specific-selector'),
              ),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: DshIcon(
                    DshIcons.plus,
                    size: 16,
                    color: theme.labelPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 34px round primary control (dsh `.primary`): the info fill with a white
/// glyph; empty it is 0.4 opaque.
class ComposerRoundButton extends StatefulWidget {
  const ComposerRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<ComposerRoundButton> createState() => _ComposerRoundButtonState();
}

class _ComposerRoundButtonState extends State<ComposerRoundButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: DshDecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hover && enabled
                    ? theme.color('--dsw-alias-button-info-hover')
                    : theme.color('--dsw-alias-button-info-fill'),
              ),
              child: SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 18,
                    color: theme.color('--dsw-static-neutral-00'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The attach menu of a phone: photo library, camera, files.
class _AttachSheet extends StatelessWidget {
  const _AttachSheet({required this.sources, required this.i18n});

  final List<AttachSource> sources;
  final DshI18n i18n;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DshSpace.sm),
        child: Column(
          key: const ValueKey('attach-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final source in sources)
              GestureDetector(
                key: ValueKey('attach-${source.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(source),
                child: SizedBox(
                  height: DshSpace.touch + 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DshSpace.lg,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          switch (source) {
                            AttachSource.photos => Icons.photo_library_outlined,
                            AttachSource.camera => Icons.photo_camera_outlined,
                            AttachSource.files => Icons.attach_file,
                          },
                          size: 22,
                          color: theme.labelSecondary,
                        ),
                        const SizedBox(width: DshSpace.md),
                        DshChromeText(
                          i18n.t(appNamespace, 'attach.${source.name}'),
                          style: theme
                              .textStyle('--dsw-font-base-16')
                              .copyWith(color: theme.labelPrimary),
                        ),
                      ],
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

class _DefaultComposerState extends State<DefaultComposer> {
  late final ComposerInput _input;
  late final ComposerTextController _text;
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchor = GlobalKey();
  StreamSubscription<SessionSnapshot>? _sub;
  StreamSubscription<DraftSnapshot>? _draftSub;
  StreamSubscription<List<LocalFile>>? _dropSub;
  StreamSubscription<InputSnapshot>? _inputSub;
  StreamSubscription<InputNotice?>? _noticeSub;
  final List<void Function()> _unbind = [];
  bool _sending = false;
  String? _error;
  bool _errorIsNotice = false;

  DraftAttachments? get _drafts => widget.owner.attachments?.drafts;

  @override
  void initState() {
    super.initState();
    _input =
        widget.owner.input ?? ComposerInput(sessionId: widget.owner.sessionId);
    _text = ComposerTextController(_input, onOpenChip: _openChip);
    _sub = widget.owner.session.snapshot.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _draftSub = _drafts?.state.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Files dropped on a desktop window arrive like picked ones.
    _dropSub = widget.owner.attachments?.dropped.listen(_add);
    _inputSub = _input.state.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _noticeSub = _input.notice.changes.listen((n) {
      if (n == null || !mounted) return;
      setState(() {
        _error = n.text;
        _errorIsNotice = !n.error;
      });
    });
    _unbind
      ..add(
        _input.bindFilePicker(
          () => !_sending && widget.owner.attachments?.picker != null,
          () => unawaited(_attach()),
        ),
      )
      ..add(_input.bindFocus(_focus.requestFocus));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portal.show();
    });
  }

  @override
  void dispose() {
    for (final off in _unbind) {
      off();
    }
    unawaited(_sub?.cancel());
    unawaited(_draftSub?.cancel());
    unawaited(_dropSub?.cancel());
    unawaited(_inputSub?.cancel());
    unawaited(_noticeSub?.cancel());
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _a(String key) => widget.i18n.t(appNamespace, key);

  void _openChip(DraftChip chip) =>
      _input.triggers?.openReference(chip.source, chip.ref, chip.appearance);

  ImageLimits? get _limits =>
      ImageLimits.tryParse(widget.owner.session.projections.get('imageLimits'));

  /// Text or an attachment to send, and no upload still running or failed
  /// (dsh holds Send until every picked file is staged).
  bool get _canSend {
    final drafts = _drafts?.value;
    final hasDrafts = drafts != null && !drafts.isEmpty;
    return (_input.clipboardText.trim().isNotEmpty || hasDrafts) &&
        !_sending &&
        !(drafts?.uploadsPending ?? false);
  }

  /// The frozen drafts as a command submission carries them.
  List<SubmitAttachment> _commandAttachments() => [
    for (final a in _drafts?.freeze() ?? const <OutgoingAttachment>[])
      switch (a) {
        OutgoingImage() => {
          'type': 'image',
          'mediaType': a.mediaType,
          'data': base64Encode(a.bytes),
          if (a.name.isNotEmpty) 'name': a.name,
        },
        OutgoingFile() => {'type': 'file', 'receiptId': a.receiptId},
      },
  ];

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final drafts = _drafts?.value;
      final result = await _input.submit(
        attachments: drafts?.items.length ?? 0,
        commandAttachments: _commandAttachments,
        unsupportedAttachments: (token) => widget.i18n.t(
          'command',
          'notice.attachmentsUnsupported',
          params: {
            'command': token.startsWith('/') ? token.substring(1) : token,
          },
        ),
        send: (text) async {
          final attachments = _drafts?.freeze() ?? const <OutgoingAttachment>[];
          await widget.owner.actions.send(text, attachments: attachments);
        },
      );
      if (!mounted) return;
      if (result is SubmitSent || result is SubmitCommandRan) _drafts?.clear();
    } on Object catch (e) {
      if (!mounted) return;
      final reason = attachmentRefusalReason(e);
      setState(() {
        _errorIsNotice = false;
        _error = e is SubmitRefused
            ? e.message
            : reason != null
            ? attachmentErrorText(widget.i18n, reason, _limits)
            : '${_a('session.composer.sendFailed')}: $e';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Add [files] to the drafts (the picker result, or a desktop drop).
  Future<void> _add(List<LocalFile> files) async {
    final drafts = _drafts;
    if (drafts == null || files.isEmpty) return;
    final result = await drafts.add(files);
    if (!mounted) return;
    setState(() {
      _errorIsNotice = false;
      _error = result.refusal == null
          ? null
          : intakeRefusalText(widget.i18n, result);
    });
  }

  Future<void> _pick(AttachSource source) async {
    final picker = widget.owner.attachments?.picker;
    if (picker == null) return;
    try {
      await _add(await picker.pick(source));
    } on Object {
      if (mounted) setState(() => _error = _a('attach.pickFailed'));
    }
  }

  Future<void> _attach() async {
    final picker = widget.owner.attachments?.picker;
    if (picker == null || picker.sources.isEmpty) return;
    if (picker.sources.length == 1) return _pick(picker.sources.single);
    final chosen = await showModalBottomSheet<AttachSource>(
      context: context,
      backgroundColor: context.dsh.color('--dsw-alias-bg-layer-2'),
      builder: (_) => _AttachSheet(sources: picker.sources, i18n: widget.i18n),
    );
    if (chosen != null) await _pick(chosen);
  }

  Future<void> _cancel() async {
    try {
      await widget.owner.actions.cancel();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// The menu's keys while it is open (dsh `registerComposerKeymap`): arrows
  /// move, Enter and Tab settle, Escape and Shift+Tab leave. Without an open
  /// menu every key stays the text field's.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final triggers = _input.triggers;
    if (triggers == null) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ArbitrateKey? key;
    if (k == LogicalKeyboardKey.arrowUp) {
      key = ArbitrateKey.up;
    } else if (k == LogicalKeyboardKey.arrowDown) {
      key = ArbitrateKey.down;
    } else if (k == LogicalKeyboardKey.escape) {
      key = ArbitrateKey.escape;
    } else if (k == LogicalKeyboardKey.tab) {
      key = kb.isShiftPressed ? ArbitrateKey.tabBack : ArbitrateKey.tab;
    } else if ((k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) &&
        !kb.isShiftPressed &&
        !kb.isControlPressed &&
        !kb.isMetaPressed &&
        !kb.isAltPressed) {
      key = ArbitrateKey.enter;
    } else {
      key = null;
    }
    if (key == null) return KeyEventResult.ignored;
    final composing =
        _text.value.composing.isValid && !_text.value.composing.isCollapsed;
    final outcome = triggers.arbitrate(key, composing: composing);
    return outcome == ArbitrateOutcome.pass
        ? KeyEventResult.ignored
        : KeyEventResult.handled;
  }

  /// The seats of the controls row (dsh's composer tool row): the
  /// current-session permission and the model, each only when a feature
  /// occupies its slot.
  ({Widget? permission, Widget? model}) _seats() {
    final slots = widget.slots;
    if (slots == null) return (permission: null, model: null);
    return (
      permission: slots.renderSingle(
        DshSlots.conversationInputPermission.typed<SessionOwner, Widget>(),
        widget.owner,
      ),
      model: slots.renderSingle(
        DshSlots.conversationInputModel.typed<SessionOwner, Widget>(),
        widget.owner,
      ),
    );
  }

  /// The floating entries of `conversation.input.overlay` (the candidate menu,
  /// the command popup) in a column above the card, as dsh anchors them (the
  /// card's top edge, its width) and as raft-flutter anchors its mention
  /// suggestions: a portal in the app overlay that follows the card, so it
  /// rises with the keyboard and never resizes the conversation.
  Widget _overlay(BuildContext context) {
    final slots = widget.slots;
    final box = _anchor.currentContext?.findRenderObject();
    if (slots == null || box is! RenderBox || !box.attached) {
      return const SizedBox.shrink();
    }
    final entries = slots.renderList(
      DshSlots.conversationInputOverlay.typed<SessionOwner, Widget>(),
      widget.owner,
    );
    if (entries.isEmpty) return const SizedBox.shrink();
    final top = box.localToGlobal(Offset.zero).dy;
    // The menu stops below the session header (dsh: the header block plus 8px),
    // so the title row stays whole; without a conversation region it keeps the
    // status bar clear.
    final region = ConversationRegion.topOf(context);
    final ceiling = region != null
        ? region + DshSpace.sm
        : MediaQuery.paddingOf(context).top + DshSpace.sm;
    final available = (top - ceiling - 4).clamp(0.0, double.infinity);
    return Positioned(
      left: 0,
      top: 0,
      width: box.size.width,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // Each entry gets the whole room above the card to cap its own
          // height to (one entry is open at a time; the others draw nothing).
          children: [
            for (final e in entries)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: available),
                child: e,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final running = widget.owner.session.snapshot.value.running;
    final locked =
        _input.snapshot.phase == InputPhase.adjudicating ||
        _input.snapshot.phase == InputPhase.submitting;
    final seats = _seats();
    final draft = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelPrimary, height: 24 / 14);
    final card = ComposerCard(
      key: _anchor,
      hero: widget.hero,
      attachments: widget.slots?.renderSingle(
        DshSlots.conversationInputAttachments.typed<SessionOwner, Widget>(),
        widget.owner,
      ),
      draft: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
        },
        child: Focus(
          onKeyEvent: _onKey,
          child: TextField(
            key: const ValueKey('composer-field'),
            controller: _text,
            focusNode: _focus,
            enabled: !locked,
            minLines: 1,
            // dsh caps the draft at 14 lines.
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: draft,
            cursorColor: theme.color('--dsw-alias-state-business-primary'),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText:
                  widget.placeholder ?? _a('session.composer.placeholder'),
              hintMaxLines: widget.hero ? 2 : 1,
              hintStyle: draft.copyWith(
                color: theme.color('--dsw-alias-label-caption'),
              ),
            ),
          ),
        ),
      ),
      leading: [
        if (widget.owner.attachments?.picker != null)
          ComposerAttachButton(
            label: _a('attach.title'),
            onPressed: _sending ? null : _attach,
          ),
        ?seats.permission,
      ],
      trailing: [
        if (seats.model != null) Flexible(child: seats.model!),
        if (running)
          ComposerRoundButton(
            key: const ValueKey('composer-cancel'),
            icon: Icons.stop_rounded,
            label: widget.i18n.t('conversation', 'input.stop'),
            onPressed: _cancel,
          ),
        if (!running || _canSend)
          ComposerRoundButton(
            key: const ValueKey('composer-send'),
            icon: Icons.arrow_upward_rounded,
            label: widget.i18n.t('conversation', 'input.send'),
            onPressed: _canSend ? _send : null,
          ),
      ],
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: TapRegion(
        groupId: composerTapGroup(widget.owner.sessionId),
        child: Padding(
          // The side clearance of the shared width axis (dsh
          // `--dsh-composer-side-clearance`) and the bottom pad of the bar.
          padding: EdgeInsets.fromLTRB(
            DshSpace.lg,
            0,
            DshSpace.lg,
            widget.hero ? 0 : 4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: DshDecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.color('--dsw-alias-interactive-bg-hover'),
                      borderRadius: BorderRadius.circular(theme.radiusMd),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: DshChromeText(
                        _error!,
                        key: const ValueKey('composer-error'),
                        style: theme
                            .textStyle('--dsw-font-xxs-12')
                            .copyWith(
                              color: _errorIsNotice
                                  ? theme.labelSecondary
                                  : theme.color(
                                      '--dsw-alias-state-error-primary',
                                    ),
                              height: 18 / 12,
                            ),
                      ),
                    ),
                  ),
                ),
              // The overlay entries hang from the card itself.
              CompositedTransformTarget(link: _link, child: card),
            ],
          ),
        ),
      ),
    );
  }
}

/// The composer card (dsh `InputBar`'s `.card`): one rounded box, the draft on
/// top (36px floor, 52px in the hero) and the controls row inside it: the
/// attach circle and permission on the left, the model and the send circle on
/// the right.
class ComposerCard extends StatelessWidget {
  const ComposerCard({
    super.key,
    required this.draft,
    required this.leading,
    required this.trailing,
    this.attachments,
    this.hero = false,
    this.dashed = false,
  });

  final Widget draft;
  final List<Widget> leading;
  final List<Widget> trailing;

  /// The staged-attachment rail, above the draft.
  final Widget? attachments;
  final bool hero;

  /// The inert no-workspace form: a dashed outline instead of the stroke.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final stroke = theme.color(
      dashed ? '--dsw-alias-border-l4' : '--dsw-alias-border-l2',
    );
    final shadows = [
      for (final (i, s) in theme.boxShadow('--dsw-elevation-soft').indexed)
        i == 0
            ? BoxShadow(
                color: dashed ? stroke.withValues(alpha: 0) : stroke,
                spreadRadius: s.spreadRadius,
              )
            : s,
    ];
    final card = DshShadowBox(
      color: theme.color('--dsw-specific-input-major'),
      radius: theme.radiusPanel,
      shadows: shadows,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?attachments,
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: hero ? 52 : 36),
            child: Padding(
              // figma: pl 14, pr 8 + the scrollbar's 4px, pt 4.
              padding: const EdgeInsets.fromLTRB(14, 4, 12, 0),
              child: draft,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: LayoutBuilder(
              builder: (context, constraints) => DshComposerRow(
                compact: constraints.maxWidth < 460,
                child: Row(
                  key: const ValueKey('composer-tools'),
                  children: [
                    for (var i = 0; i < leading.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      leading[i],
                    ],
                    const Spacer(),
                    for (var i = 0; i < trailing.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      trailing[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!dashed) return card;
    return CustomPaint(
      foregroundPainter: _DashedOutline(stroke, theme.radiusPanel),
      child: card,
    );
  }
}

class _DashedOutline extends CustomPainter {
  _DashedOutline(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // `border: 1px dashed`: Chromium's dash is three times the width, gaps equal.
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, at + 3), paint);
        at += 6;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.radius != radius;
}
