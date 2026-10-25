import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Session-owned queue seat. Transcript/steering echoes must not also appear
/// in the queue while their Host admission is crossing the follow stream.
class QueueDock extends StatelessWidget {
  const QueueDock({
    super.key,
    required this.owner,
    required this.i18n,
    this.slots,
  });
  final SessionOwner owner;
  final DshI18n i18n;
  final SlotRegistry? slots;
  @override
  Widget build(BuildContext context) => DshWatch(
    changes: owner.session.projections.changes,
    builder: (_) => DshWatch(
      changes: owner.session.snapshot.changes,
      builder: (_) {
        final pending = owner.session.snapshot.value.pendingSubmissions;
        final transcript = pending
            .where((p) => p.placement == SubmissionPlacement.transcript)
            .map((p) => p.requestId)
            .toSet();
        final rows = inboxItems(
          owner.session.projections.get('inbox'),
          'next-turn',
        ).where((r) => !transcript.contains(r.requestId)).toList();
        final admitted = rows.map((r) => r.requestId).toSet();
        final local = pending
            .where(
              (p) =>
                  p.placement == SubmissionPlacement.queued &&
                  !admitted.contains(p.requestId),
            )
            .toList();
        if (rows.isEmpty && local.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: QueuePanel(
            key: ValueKey(owner.sessionId),
            rows: rows,
            pending: local,
            running: owner.session.snapshot.value.running,
            mutable: owner.queueMutable,
            i18n: i18n,
            updateQueue: owner.actions.updateQueue,
            loadImage: owner.session.images.load,
            renderText: (text) =>
                slots?.renderSingle(
                  DshSlots.conversationUserText.typed<UserTextOwner, Widget>(),
                  UserTextOwner(
                    text: text,
                    session: owner,
                    ellipsis: true,
                    facts: const {
                      'trimWhitespace': true,
                      'collapseWhitespace': true,
                    },
                  ),
                ) ??
                Text(text.replaceAll(RegExp(r'\s+'), ' ').trim()),
          ),
        );
      },
    ),
  );
}

/// The Web queue's compact panel: one row inline, several behind a count
/// header. Mutations wait for authoritative projections; failure keeps edits.
class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.rows,
    this.pending = const [],
    required this.running,
    this.mutable = true,
    required this.i18n,
    required this.updateQueue,
    this.loadImage,
    this.renderText,
  });
  final List<InboxItem> rows;
  final List<PendingSubmission> pending;
  final bool running, mutable;
  final Widget Function(String original)? renderText;
  final DshI18n i18n;
  final Future<void> Function(String, Map<String, Object?>) updateQueue;
  final Future<Uint8List> Function(ImageRef)? loadImage;
  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final _edit = TextEditingController();
  final _editorFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    _editorFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  bool _collapsed = true;
  String? _editing, _busy, _error;
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('conversation', key, params: params);
  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.mutable || !widget.rows.any((r) => r.id == _editing)) {
      _editing = null;
    }
    if (widget.rows.isEmpty && widget.pending.isEmpty) _collapsed = true;
  }

  @override
  void dispose() {
    _edit.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  Future<void> _apply(
    String id,
    Map<String, Object?> action,
    String failure,
  ) async {
    if (_busy != null || !widget.mutable) return;
    setState(() {
      _busy = id;
      _error = null;
    });
    try {
      await widget.updateQueue(id, action);
      if (mounted && action['kind'] == 'edit' && _editing == id) {
        setState(() => _editing = null);
      }
    } on Object {
      if (mounted) setState(() => _error = t(failure));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _save() {
    final id = _editing;
    if (id == null ||
        _edit.text.trim().isEmpty ||
        _busy != null ||
        (_edit.value.composing.isValid && !_edit.value.composing.isCollapsed)) {
      return;
    }
    unawaited(
      _apply(id, {
        'kind': 'edit',
        'content': [
          {'type': 'text', 'text': _edit.text},
        ],
      }, 'queue.editFailed'),
    );
  }

  Widget _icon(DshIconData icon, [double size = 14]) => DshIcon(
    icon,
    size: size,
    color: context.dsh.color('--dsw-alias-label-tertiary'),
  );
  Widget _button(
    String id,
    String action,
    DshIconData icon,
    VoidCallback? run, {
    String? hint,
  }) => _QueueButton(
    key: ValueKey('queue-$action-$id'),
    label: t('queue.$action'),
    hint: hint,
    icon: icon,
    onPressed: run,
  );

  Widget _preview(String text) => Expanded(
    child: DefaultTextStyle(
      style: context.dsh
          .textStyle('--dsw-font-xs-13')
          .copyWith(
            height: 20 / 13,
            color: context.dsh.color('--dsw-alias-label-primary-dimmed'),
          ),
      child:
          widget.renderText?.call(text) ??
          Text(
            text.replaceAll(RegExp(r'\s+'), ' ').trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
    ),
  );

  Widget _file(String name, int bytes) => DshContainer(
    constraints: const BoxConstraints(maxWidth: 180),
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: context.dsh.bgBase,
      borderRadius: BorderRadius.circular(context.dsh.radiusSm),
      border: Border.all(
        width: dshBorderWidthOf(context, .5),
        color: context.dsh.color('--dsw-alias-border-l1'),
      ),
    ),
    child: LayoutBuilder(
      builder: (_, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (constraints.maxWidth >= 20) ...[
            DshFileTypeIcon(path: name, size: 16),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: DshChromeText(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.dsh
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(
                    color: context.dsh.color(
                      '--dsw-alias-label-primary-dimmed',
                    ),
                  ),
            ),
          ),
          if (constraints.maxWidth >= 64) ...[
            const SizedBox(width: 4),
            DshChromeText(
              dshFileSizeText(bytes),
              style: TextStyle(
                fontSize: 10,
                color: context.dsh.color('--dsw-alias-label-tertiary'),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _thumb({Uint8List? bytes, ImageRef? ref}) => _QueueThumb(
    bytes: bytes,
    ref: ref,
    load: widget.loadImage,
    label: t('queue.image'),
  );
  List<Widget> _attachments(InboxItem row) => [
    for (final block in row.content)
      if (block['type'] == 'image' &&
          ImageRef.tryParse(block['attachment']) != null)
        _thumb(ref: ImageRef.tryParse(block['attachment']))
      else if (block['type'] == 'file')
        if (FileRef.tryParse(block['attachment']) case final file?)
          _file(file.name, file.bytes),
  ];
  Widget _row(
    InboxItem? row,
    PendingSubmission? pending,
    bool single,
    bool separator,
  ) {
    final id = row?.id ?? pending!.requestId;
    final editing = row != null && _editing == id;
    final busy = _busy != null;
    final attachments = row == null
        ? [
            for (final a in pending!.attachments)
              switch (a) {
                OutgoingImage() => _thumb(bytes: a.bytes),
                OutgoingFile() => _file(a.name, a.size),
              },
          ]
        : _attachments(row);
    return DshContainer(
      key: ValueKey('queue-row-$id'),
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.fromLTRB(12, 4, 5, 4),
      decoration: _QueueDecoration(
        borderRadius: BorderRadius.circular(context.dsh.radiusMd),
        border: separator
            ? Border(
                top: BorderSide(
                  width: dshBorderWidthOf(context, 1),
                  color: context.dsh.color('--dsw-alias-border-l1'),
                ),
              )
            : null,
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final status = TextPainter(
            text: TextSpan(
              text: t('queue.sending'),
              style: context.dsh.textStyle('--dsw-font-xs-13'),
            ),
            textDirection: Directionality.of(context),
          )..layout();
          final reserved =
              (single ? 24 : 0) +
              (widget.mutable ? 114 : 0) +
              (pending == null ? 0 : status.width + 10) +
              10;
          status.dispose();
          final attachmentWidth = math.min(
            constraints.maxWidth * .55,
            math.max(0.0, constraints.maxWidth - reserved),
          );
          return Row(
            children: [
              if (single) ...[
                _icon(DshShellIcons.queue),
                const SizedBox(width: 10),
              ],
              if (editing)
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): _save,
                      const SingleActivator(LogicalKeyboardKey.escape): () {
                        if (!busy) setState(() => _editing = null);
                      },
                    },
                    child: DshContainer(
                      constraints: const BoxConstraints(minHeight: 28),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.dsh.bgBase,
                        borderRadius: BorderRadius.circular(
                          context.dsh.radiusSm,
                        ),
                        border: Border.all(
                          width: dshBorderWidthOf(context, .5),
                          color: context.dsh.color(
                            _editorFocus.hasFocus
                                ? '--dsw-alias-state-business-primary'
                                : '--dsw-alias-border-l4',
                          ),
                        ),
                      ),
                      child: Semantics(
                        label: t('queue.edit'),
                        child: TextField(
                          key: ValueKey('queue-editor-$id'),
                          controller: _edit,
                          autofocus: true,
                          focusNode: _editorFocus,
                          enabled: !busy,
                          minLines: 1,
                          maxLines: 6,
                          style: context.dsh
                              .textStyle('--dsw-font-xs-13')
                              .copyWith(
                                color: context.dsh.labelPrimary,
                                height: 20 / 13,
                              ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                if (attachments.isNotEmpty) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: attachmentWidth),
                    child: ClipRect(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < attachments.length; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            Flexible(child: attachments[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                _preview(row?.text ?? pending!.text),
              ],
              if (pending != null) ...[
                const SizedBox(width: 10),
                DshChromeText(
                  t('queue.sending'),
                  style: context.dsh
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(
                        color: context.dsh.color('--dsw-alias-label-tertiary'),
                      ),
                ),
              ],
              if (widget.mutable) ...[
                const SizedBox(width: 10),
                if (editing) ...[
                  _button(
                    id,
                    'save',
                    DshIcons.check,
                    busy || _edit.text.trim().isEmpty ? null : _save,
                  ),
                  const SizedBox(width: 10),
                  _button(
                    id,
                    'cancelEdit',
                    DshIcons.close,
                    busy ? null : () => setState(() => _editing = null),
                  ),
                ] else ...[
                  _button(
                    id,
                    'edit',
                    DshShellIcons.editOutline,
                    busy || row == null || !row.editable
                        ? null
                        : () => setState(() {
                            _editing = id;
                            _edit.text = row.text;
                          }),
                    hint: row == null
                        ? t('queue.sending')
                        : !row.editable
                        ? t('queue.edit.unsupported')
                        : null,
                  ),
                  const SizedBox(width: 10),
                  _button(
                    id,
                    'remove',
                    DshShellIcons.trash,
                    busy || row == null
                        ? null
                        : () => unawaited(
                            _apply(id, {
                              'kind': 'remove',
                            }, 'queue.removeFailed'),
                          ),
                  ),
                  const SizedBox(width: 10),
                  _button(
                    id,
                    'steer',
                    DshShellIcons.sendOutline,
                    busy || row == null || !widget.running
                        ? null
                        : () => unawaited(
                            _apply(id, {'kind': 'steer'}, 'queue.steerFailed'),
                          ),
                    hint: !widget.running ? t('queue.steer.unavailable') : null,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.rows.length + widget.pending.length;
    if (count == 0) return const SizedBox.shrink();
    final theme = context.dsh;
    final interaction = widget.mutable && (_editing != null || _busy != null);
    final expanded = !_collapsed || interaction;
    final show = count == 1 || expanded;
    return DshContainer(
      key: const ValueKey('queue-panel'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: _QueueDecoration(
        color: blendLikeChromium(
          theme.color('--dsw-specific-menu'),
          saturateLikeChromium(theme.bgBase, 1.5),
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(theme.radiusLg),
        ),
        border: Border(
          top: BorderSide(
            width: dshBorderWidthOf(context, .5),
            color: theme.color('--dsw-alias-border-l1'),
          ),
          left: BorderSide(
            width: dshBorderWidthOf(context, .5),
            color: theme.color('--dsw-alias-border-l1'),
          ),
          right: BorderSide(
            width: dshBorderWidthOf(context, .5),
            color: theme.color('--dsw-alias-border-l1'),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 1)
            _QueueHeader(
              expanded: expanded,
              enabled: !interaction,
              label: t('queue.count', {'n': count}),
              status: !show && widget.pending.isNotEmpty
                  ? t('queue.sending')
                  : null,
              onPressed: () => setState(() => _collapsed = !_collapsed),
            ),
          if (show)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.rows.length; i++)
                      _row(widget.rows[i], null, count == 1, i > 0),
                    for (var i = 0; i < widget.pending.length; i++)
                      _row(
                        null,
                        widget.pending[i],
                        count == 1,
                        i + widget.rows.length > 0,
                      ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: DshChromeText(
                  _error!,
                  key: const ValueKey('queue-error'),
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(
                        color: theme.color('--dsw-alias-state-error-primary'),
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueThumb extends StatefulWidget {
  const _QueueThumb({this.bytes, this.ref, this.load, required this.label});
  final Uint8List? bytes;
  final ImageRef? ref;
  final Future<Uint8List> Function(ImageRef)? load;
  final String label;
  @override
  State<_QueueThumb> createState() => _QueueThumbState();
}

class _QueueThumbState extends State<_QueueThumb> {
  Future<Uint8List>? _bytes;
  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_QueueThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref?.attachmentId != widget.ref?.attachmentId) _start();
  }

  void _start() {
    _bytes = widget.ref == null ? null : widget.load?.call(widget.ref!);
  }

  @override
  Widget build(BuildContext context) => DshContainer(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: context.dsh.bgBase,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        width: dshBorderWidthOf(context, .5),
        color: context.dsh.color('--dsw-alias-border-l1'),
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        initialData: widget.bytes,
        builder: (_, snap) => snap.data == null
            ? const SizedBox.shrink()
            : Image.memory(
                snap.data!,
                semanticLabel: widget.label,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
      ),
    ),
  );
}

class _QueueButton extends StatefulWidget {
  const _QueueButton({
    super.key,
    required this.label,
    this.hint,
    required this.icon,
    this.onPressed,
  });
  final String label;
  final String? hint;
  final DshIconData icon;
  final VoidCallback? onPressed;
  @override
  State<_QueueButton> createState() => _QueueButtonState();
}

class _QueueButtonState extends State<_QueueButton> {
  bool _hover = false, _focus = false;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: widget.onPressed != null,
    label: widget.label,
    onTap: widget.onPressed,
    child: ExcludeSemantics(
      child: DshTooltip(
        label: widget.hint ?? widget.label,
        side: DshTooltipSide.bottom,
        delay: const Duration(milliseconds: 500),
        child: FocusableActionDetector(
          enabled: widget.onPressed != null,
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            cursor: widget.onPressed == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPressed,
              child: Opacity(
                opacity: widget.onPressed == null ? .45 : 1,
                child: DshContainer(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hover && widget.onPressed != null
                        ? context.dsh.color('--dsw-alias-interactive-bg-hover')
                        : null,
                    border: _focus
                        ? Border.all(
                            color: context.dsh.color(
                              '--dsw-alias-state-business-primary',
                            ),
                            width: 2,
                          )
                        : null,
                  ),
                  child: Center(
                    child: DshIcon(
                      widget.icon,
                      size: widget.icon == DshShellIcons.sendOutline ? 16 : 14,
                      color: context.dsh.color('--dsw-alias-label-tertiary'),
                    ),
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

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.expanded,
    required this.enabled,
    required this.label,
    this.status,
    required this.onPressed,
  });
  final bool expanded, enabled;
  final String label;
  final String? status;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    expanded: expanded,
    enabled: enabled,
    label: label,
    onTap: enabled ? onPressed : null,
    child: ExcludeSemantics(
      child: FocusableActionDetector(
        enabled: enabled,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: const ValueKey('queue-header'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  DshIcon(
                    DshShellIcons.queue,
                    color: context.dsh.color('--dsw-alias-label-tertiary'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DshChromeText(
                      label,
                      style: context.dsh
                          .textStyle('--dsw-font-xs-13')
                          .copyWith(
                            height: 24 / 13,
                            fontWeight: FontWeight.w500,
                            color: context.dsh.labelPrimary,
                          ),
                    ),
                  ),
                  if (status != null)
                    DshChromeText(
                      status!,
                      style: context.dsh
                          .textStyle('--dsw-font-xs-13')
                          .copyWith(
                            color: context.dsh.color(
                              '--dsw-alias-label-tertiary',
                            ),
                          ),
                    ),
                  const SizedBox(width: 10),
                  DshIcon(
                    expanded ? DshIcons.chevronDown : DshIcons.chevronUp,
                    color: context.dsh.color('--dsw-alias-label-tertiary'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Web paints the panel ring and row separators as overlays; they do not
/// consume layout space or move the editor/actions by a fractional pixel.
class _QueueDecoration extends BoxDecoration {
  const _QueueDecoration({super.color, super.borderRadius, super.border});
  @override
  EdgeInsetsGeometry get padding => EdgeInsets.zero;
}
