import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons, showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'attachment_text.dart';

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
  });

  final SessionOwner owner;
  final DshI18n i18n;

  /// Renders the draft rail through `conversation.input.attachments`.
  final SlotRegistry? slots;

  @override
  State<DefaultComposer> createState() => _DefaultComposerState();
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: GestureDetector(
        key: const ValueKey('composer-attach'),
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: DshSpace.touch - 8,
          height: DshSpace.touch,
          child: Center(
            child: Opacity(
              opacity: onPressed == null ? 0.4 : 1,
              child: DshIcon(
                DshIcons.plus,
                size: 20,
                color: theme.labelPrimary,
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
                        Text(
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
  final TextEditingController _text = TextEditingController();
  StreamSubscription<SessionSnapshot>? _sub;
  StreamSubscription<DraftSnapshot>? _draftSub;
  StreamSubscription<List<LocalFile>>? _dropSub;
  bool _sending = false;
  String? _error;

  DraftAttachments? get _drafts => widget.owner.attachments?.drafts;

  @override
  void initState() {
    super.initState();
    _sub = widget.owner.session.snapshot.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _draftSub = _drafts?.state.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Files dropped on a desktop window arrive like picked ones.
    _dropSub = widget.owner.attachments?.dropped.listen(_add);
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_draftSub?.cancel());
    unawaited(_dropSub?.cancel());
    _text.dispose();
    super.dispose();
  }

  String _a(String key) => widget.i18n.t(appNamespace, key);

  ImageLimits? get _limits =>
      ImageLimits.tryParse(widget.owner.session.projections.get('imageLimits'));

  /// Text or an attachment to send, and no upload still running or failed
  /// (dsh holds Send until every picked file is staged).
  bool get _canSend {
    final drafts = _drafts?.value;
    final hasDrafts = drafts != null && !drafts.isEmpty;
    return (_text.text.trim().isNotEmpty || hasDrafts) &&
        !_sending &&
        !(drafts?.uploadsPending ?? false);
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final text = _text.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final attachments = _drafts?.freeze() ?? const <OutgoingAttachment>[];
      await widget.owner.actions.send(text, attachments: attachments);
      if (!mounted) return;
      _text.clear();
      _drafts?.clear();
    } on Object catch (e) {
      if (!mounted) return;
      final reason = attachmentRefusalReason(e);
      setState(
        () => _error = reason != null
            ? attachmentErrorText(widget.i18n, reason, _limits)
            : '${_a('session.composer.sendFailed')}: $e',
      );
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
    setState(
      () => _error = result.refusal == null
          ? null
          : intakeRefusalText(widget.i18n, result),
    );
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

  /// The controls above the field (dsh's composer tool row): the
  /// current-session permission and the model, each only when a feature
  /// occupies its slot.
  List<Widget> _toolRow() {
    final slots = widget.slots;
    if (slots == null) return const [];
    final permission = slots.renderSingle(
      DshSlots.conversationInputPermission.typed<SessionOwner, Widget>(),
      widget.owner,
    );
    final model = slots.renderSingle(
      DshSlots.conversationInputModel.typed<SessionOwner, Widget>(),
      widget.owner,
    );
    if (permission == null && model == null) return const [];
    return [
      LayoutBuilder(
        builder: (context, constraints) => DshComposerRow(
          compact: constraints.maxWidth < 460,
          child: Padding(
            key: const ValueKey('composer-tools'),
            padding: const EdgeInsets.only(bottom: DshSpace.xs),
            child: Row(
              children: [
                ?permission,
                if (permission != null && model != null)
                  const SizedBox(width: DshSpace.xs),
                if (model != null) Flexible(child: model),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final running = widget.owner.session.snapshot.value.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.lg,
        DshSpace.sm,
        DshSpace.sm,
        DshSpace.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: DshSpace.xs),
              child: Text(
                _error!,
                key: const ValueKey('composer-error'),
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                    ),
              ),
            ),
          if (widget.slots != null)
            widget.slots!.renderSingle(
                  DshSlots.conversationInputAttachments
                      .typed<SessionOwner, Widget>(),
                  widget.owner,
                ) ??
                const SizedBox.shrink(),
          ..._toolRow(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.owner.attachments?.picker != null)
                _AttachButton(
                  label: _a('attach.title'),
                  onPressed: _sending ? null : _attach,
                ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): _send,
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _send,
                  },
                  child: DshTextField(
                    controller: _text,
                    placeholder: _a('session.composer.placeholder'),
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
              if (running)
                DshIconButton(
                  key: const ValueKey('composer-cancel'),
                  icon: Icons.stop_rounded,
                  semanticLabel: widget.i18n.t('conversation', 'input.stop'),
                  onPressed: _cancel,
                ),
              if (!running || _canSend)
                DshIconButton(
                  key: const ValueKey('composer-send'),
                  icon: Icons.arrow_upward_rounded,
                  semanticLabel: widget.i18n.t('conversation', 'input.send'),
                  filled: true,
                  onPressed: _canSend ? _send : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
