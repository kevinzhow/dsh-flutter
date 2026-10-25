import 'dart:math' as math;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'stream/message_actions.dart';

String _chat(
  DshI18n i18n,
  String key, {
  Map<String, Object?> params = const {},
}) => i18n.t('chat', key, params: params);

TextStyle _caption(BuildContext context) {
  final theme = context.dsh;
  return theme
      .textStyle('--dsw-font-xxs-12')
      .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
}

/// The code card toolbar strings of dsh's `conversation` dictionary.
DshCodeToolbarLabels codeLabels(DshI18n i18n) => DshCodeToolbarLabels(
  codeLabel: i18n.t('conversation', 'codeBlock.title'),
  wrapLabel: i18n.t('conversation', 'codeBlock.wrap'),
  unwrapLabel: i18n.t('conversation', 'codeBlock.unwrap'),
  copy: i18n.t('conversation', 'copy'),
  copied: i18n.t('conversation', 'copied'),
);

/// One attachment of a user message as the chat shows it: an image (durable,
/// or the local preview of a message still being admitted) or a file.
sealed class UserAttachmentView {
  const UserAttachmentView();
}

final class UserImageView extends UserAttachmentView {
  const UserImageView(this.image);
  final GalleryImage image;
}

final class UserFileView extends UserAttachmentView {
  const UserFileView({required this.name, required this.bytes});
  final String name;
  final int bytes;
}

/// The attachments of a durable message, in content order.
List<UserAttachmentView> attachmentViews(List<MessageAttachment> attachments) =>
    [
      for (final a in attachments)
        switch (a) {
          MessageImage() => UserImageView(DurableGalleryImage(a.image)),
          MessageFile() => UserFileView(name: a.file.name, bytes: a.file.bytes),
        },
    ];

/// The attachments of a local echo, in pick order.
List<UserAttachmentView> echoAttachmentViews(
  List<OutgoingAttachment> attachments,
) => [
  for (final a in attachments)
    switch (a) {
      OutgoingImage() => UserImageView(
        PreviewGalleryImage(
          a.bytes,
          name: a.name.isEmpty ? null : a.name,
          width: a.width,
          height: a.height,
        ),
      ),
      OutgoingFile() => UserFileView(name: a.name, bytes: a.size),
    },
];

/// A person's message: its attachments (image groups through the
/// `conversation.chat.user.images` slot, file cards) above a right-aligned
/// bubble on `--dsw-specific-bubble` (dsh ui-chat `UserContent`; the bubble is
/// only there for text). [pending] dims a local echo that the host has not yet
/// admitted.
class UserBubble extends StatelessWidget {
  const UserBubble({
    super.key,
    required this.text,
    required this.i18n,
    this.steering = false,
    this.pending = false,
    this.attachments = const [],
    this.owner,
    this.slots,
    this.time,
    this.actions = true,
    this.latest = false,
    this.referenceLabels = const [],
  });

  final String text;
  final DshI18n i18n;
  final bool steering;
  final bool pending;

  /// The message's event time, for the clock of its actions row.
  final num? time;

  /// Show the copy action (and clock) under the bubble.
  final bool actions;

  /// The newest user message keeps its actions visible on pointer platforms;
  /// earlier ones show them on hover (dsh `data-actions-reveal`).
  final bool latest;
  final List<UserAttachmentView> attachments;
  final List<String> referenceLabels;

  /// Needed to render image groups (the session loads durable images).
  final SessionOwner? owner;
  final SlotRegistry? slots;

  Widget _attachments() {
    final images = [
      for (final a in attachments)
        if (a is UserImageView) a.image,
    ];
    final compact = attachments.length > 1;
    var imageIndex = 0;
    return Wrap(
      key: const ValueKey('message-attachments'),
      alignment: WrapAlignment.end,
      spacing: DshSpace.sm,
      runSpacing: DshSpace.sm,
      children: [
        for (final a in attachments)
          switch (a) {
            UserFileView() => DshMessageFileCard(name: a.name, bytes: a.bytes),
            UserImageView() => Builder(
              builder: (_) {
                final index = imageIndex++;
                final view = owner == null || slots == null
                    ? null
                    : slots!.renderSingle(
                        DshSlots.conversationChatUserImages
                            .typed<ImageGalleryOwner, Widget>(),
                        ImageGalleryOwner(
                          session: owner!,
                          images: [a.image],
                          alignEnd: true,
                          compact: compact,
                          group: images,
                          groupIndex: index,
                        ),
                      );
                return view ?? const SizedBox.shrink();
              },
            ),
          },
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final showBubble = text.isNotEmpty || attachments.isEmpty;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          // `.userStack { max-width: min(content width * 0.702, 82%) }`
          constraints: BoxConstraints(
            maxWidth: math.min(
              DshChatContent.of(context) * 0.702,
              constraints.maxWidth * 0.82,
            ),
          ),
          child: Opacity(
            opacity: pending ? 0.6 : 1,
            child: HoverReveal(
              always: latest || pending,
              builder: (context, revealed) => Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (steering)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DshSpace.xs),
                      child: DshChromeText(
                        i18n.t('conversation', 'settings.enter.steer'),
                        style: _caption(context),
                      ),
                    ),
                  if (attachments.isNotEmpty) _attachments(),
                  if (attachments.isNotEmpty && showBubble)
                    const SizedBox(height: DshSpace.sm),
                  if (showBubble)
                    DshDecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.color('--dsw-specific-bubble'),
                        borderRadius: BorderRadius.circular(theme.radiusXl),
                      ),
                      child: Padding(
                        // `.bubble { padding: 10px 16px }`, 14/22 text.
                        padding: const EdgeInsets.symmetric(
                          horizontal: DshSpace.lg,
                          vertical: 10,
                        ),
                        child: DefaultTextStyle(
                          style: theme
                              .textStyle('--dsw-font-s-14')
                              .copyWith(color: theme.labelPrimary),
                          child:
                              slots?.renderSingle(
                                DshSlots.conversationUserText
                                    .typed<UserTextOwner, Widget>(),
                                UserTextOwner(
                                  text: text,
                                  facts: {
                                    if (referenceLabels.isNotEmpty)
                                      'sessionLabels': referenceLabels,
                                  },
                                  session: owner,
                                  interactive: !pending,
                                ),
                              ) ??
                              Text(text),
                        ),
                      ),
                    ),
                  // `.userRow { gap: 6px }` between the stack and the actions.
                  if (actions && text.isNotEmpty) const SizedBox(height: 6),
                  if (actions && text.isNotEmpty)
                    MessageActions(
                      text: text,
                      time: time,
                      i18n: i18n,
                      revealed: revealed,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One streamed or settled assistant step: collapsible reasoning rows and the
/// markdown answer text; a stopped marker when the step was interrupted.
class AssistantStepView extends StatelessWidget {
  const AssistantStepView({
    super.key,
    required this.data,
    required this.nodeKey,
    required this.i18n,
    this.owner,
    this.slots,
    this.host,
    this.groupPart,
    this.reasoningPreview = true,
  });

  final AssistantData data;
  final String nodeKey;
  final DshI18n i18n;
  final String? groupPart;
  final bool reasoningPreview;

  /// What a tapped link may open (browser, workspace file preview).
  final ToolHostActions? host;

  /// Needed to render image blocks through `conversation.chat.message.images`.
  final SessionOwner? owner;
  final SlotRegistry? slots;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final children = <Widget>[];
    for (var i = 0; i < data.blocks.length; i++) {
      final block = data.blocks[i];
      switch (block) {
        case ReasoningBlock(:final text)
            when text.trim().isNotEmpty && groupPart != 'response':
          final last = i == data.blocks.length - 1;
          children.add(
            _ReasoningRow(
              key: ValueKey('reasoning-$nodeKey-$i'),
              text: text,
              streaming: data.status == 'running' && last,
              i18n: i18n,
              preview: reasoningPreview,
            ),
          );
        case TextBlock(:final text)
            when text.trim().isNotEmpty && groupPart != 'reasoning':
          children.add(
            DshMarkdown(
              text,
              key: ValueKey('text-$nodeKey-$i'),
              codeLabels: codeLabels(i18n),
              streaming: data.status == 'running',
              onOpenUrl: host?.openUrl,
              onOpenFile: host?.openFile,
            ),
          );
        case ImageBlock(:final attachment) when groupPart != 'reasoning':
          final ref = ImageRef.tryParse(attachment);
          final gallery = ref == null || owner == null || slots == null
              ? null
              : slots!.renderSingle(
                  DshSlots.conversationChatMessageImages
                      .typed<ImageGalleryOwner, Widget>(),
                  ImageGalleryOwner(
                    session: owner!,
                    images: [DurableGalleryImage(ref)],
                  ),
                );
          children.add(
            gallery ??
                DshChromeText(
                  i18n.t('conversation', 'image.label'),
                  style: _caption(context),
                ),
          );
        case _:
          break;
      }
    }
    if (data.status == 'interrupted' && groupPart != 'reasoning') {
      children.add(
        DshChromeText(
          _chat(i18n, 'message.stopped'),
          key: const ValueKey('assistant-stopped'),
          style: _caption(context)
              .copyWith(color: theme.color('--dsw-alias-label-secondary')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: DshSpace.sm),
          children[i],
        ],
      ],
    );
  }
}

/// Reasoning is open while it streams and folds away once it is done, unless
/// the reader opened or closed it by hand (dsh's "collapse on completion").
class _ReasoningRow extends StatefulWidget {
  const _ReasoningRow({
    super.key,
    required this.text,
    required this.streaming,
    required this.i18n,
    this.preview = true,
  });

  final String text;
  final bool streaming;
  final DshI18n i18n;
  final bool preview;

  @override
  State<_ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<_ReasoningRow> {
  bool? _byHand;

  /// The reader's choice survives the row scrolling out of the built range
  /// (the list is lazy): it is kept in the enclosing [PageStorage] by row key.
  Object get _storeKey => (widget.key ?? 'reasoning', _resetVersion ?? 0);
  int? _resetVersion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DshDisclosureReset.of(context);
    if (_resetVersion != null && _resetVersion != next) _byHand = false;
    _resetVersion = next;
    _byHand ??= PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _storeKey) as bool?;
  }

  void _toggle(bool open) {
    DshDisclosureChange(open, context).dispatch(context);
    setState(() => _byHand = open);
    PageStorage.maybeOf(context)
        ?.writeState(context, open, identifier: _storeKey);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final streaming = widget.streaming;
    final i18n = widget.i18n;
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelSecondary);
    final open = _byHand ?? false;
    var summary = text.split('\n').first;
    if (streaming) {
      summary = '';
      final paragraphs = text.split(RegExp(r'\r?\n(?:[\t ]*\r?\n)+'));
      for (final paragraph in paragraphs) {
        final newline = paragraph.indexOf('\n');
        if (newline >= 0 && paragraph.substring(0, newline).trim().isNotEmpty) {
          summary = paragraph.substring(0, newline).trim();
        }
      }
    }
    summary = summary.replaceAll('**', '');
    final preview =
        !open && summary.isNotEmpty && (streaming || widget.preview);
    return DshDisclosureRow(
      icon: DshShellIcons.think,
      title: _chat(i18n, 'message.think'),
      running: streaming,
      open: open,
      expandable: true,
      onToggle: () => _toggle(!open),
      collapsedContent: preview
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    width: 2,
                    height: 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.color('--dsw-alias-label-caption'),
                    ),
                  ),
                ),
                Flexible(
                  child: DshChromeText(
                    summary,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
      children: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 0, 4),
        child: DshMarkdown(
          text,
          codeLabels: codeLabels(i18n),
          streaming: streaming,
        ),
      ),
    );
  }
}

/// The closing row of a finished turn (dsh `TurnTailNodeView`): the copy
/// action for the closing answer and the turn's clock. The newest turn keeps
/// them visible; earlier turns show them on hover on pointer platforms.
class TurnTailView extends StatelessWidget {
  const TurnTailView({
    super.key,
    required this.data,
    required this.i18n,
    this.latest = false,
    this.onBranch,
    this.branchUnavailable = false,
  });

  final TurnTailData data;
  final DshI18n i18n;
  final bool latest;
  final Future<void> Function()? onBranch;
  final bool branchUnavailable;

  String? get _text {
    final closing = data.closing;
    if (closing == null) return null;
    return [
      for (final b in closing.blocks)
        if (b is TextBlock) b.text,
    ].join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: HoverReveal(
        always: latest,
        builder: (context, revealed) => MessageActions(
          key: const ValueKey('turn-copy'),
          onBranch: onBranch,
          branchUnavailable: branchUnavailable || data.branchUnavailable,
          text: text,
          time: data.closing?.time ?? data.time,
          i18n: i18n,
          clockFirst: false,
          revealed: revealed,
        ),
      ),
    );
  }
}

/// A terminal turn failure.
class TurnErrorView extends StatelessWidget {
  const TurnErrorView({super.key, required this.data, required this.i18n});

  final TurnErrorData data;
  final DshI18n i18n;

  String get _text => switch (data.code) {
    'AUTH' => _chat(i18n, 'message.failure.auth'),
    'ACCOUNT_SIGNED_OUT' => i18n.t(appNamespace, 'session.turn.signedOut'),
    'INTERRUPTED' => i18n.t(appNamespace, 'session.turn.interrupted'),
    _ => data.message,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final detail = _text;
    return DshCard(
      key: const ValueKey('turn-error'),
      tint: theme
          .color('--dsw-alias-state-error-secondary')
          .withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: DshSpace.xs),
            child: DshStatusDot(DshStatus.error),
          ),
          const SizedBox(width: DshSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DshChromeText(
                  i18n.t(appNamespace, 'session.turn.failed'),
                  style: theme
                      .textStyle('--dsw-font-s-strong-14')
                      .copyWith(color: theme.labelPrimary),
                ),
                if (detail.isNotEmpty)
                  DshChromeText(
                    detail,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A caption row used for small turn notices (max tokens, triggers, unknown
/// events).
class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.text, this.status});

  final String text;
  final DshStatus? status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (status != null) ...[
        DshStatusDot(status!),
        const SizedBox(width: DshSpace.sm),
      ],
      Flexible(child: DshChromeText(text, style: _caption(context))),
    ],
  );
}
