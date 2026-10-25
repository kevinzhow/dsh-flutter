import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

void registerSentReferenceFeature(
  SlotRegistry slots, {
  required UserTextRegistry userText,
  required DshI18n Function() i18n,
  required void Function(SessionOwner session, String path) openFile,
}) {
  userText.register(fileReferenceRule);
  userText.register(folderReferenceRule);
  for (final kind in ['file', 'folder']) {
    slots.register<UserTextNodeOwner, InlineSpan>(
      DshSlots.conversationUserTextNode.typed<UserTextNodeOwner, InlineSpan>(),
      (owner) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: SentPathReference(
          key: ValueKey(owner.identity),
          owner: owner,
          i18n: i18n(),
          open: kind == 'file' && owner.session != null
              ? () =>
                    openFile(owner.session!, owner.node.data['path'] as String)
              : null,
        ),
      ),
      key: kind,
    );
  }
}

/// Navigation failure belongs to the reference that requested it. Its retry
/// keeps the original Session's authority, even if the active Session changes.
class SentPathReference extends StatelessWidget {
  const SentPathReference({
    super.key,
    required this.owner,
    required this.i18n,
    this.open,
  });
  final UserTextNodeOwner owner;
  final DshI18n i18n;
  final VoidCallback? open;
  @override
  Widget build(BuildContext context) => DshReferenceChip(
    appearance: owner.node.id,
    label: owner.node.data['label'] as String,
    title: owner.raw,
    onActivate: !owner.interactive || open == null
        ? null
        : () {
            try {
              open!();
            } on Object {
              unawaited(
                showDshDialog<void>(
                  context,
                  label: i18n.t('reference', 'fileOpen.close'),
                  builder: (_) => _OpenFailure(
                    i18n: i18n,
                    path: owner.node.data['path'] as String,
                    open: open!,
                  ),
                ),
              );
            }
          },
  );
}

class _OpenFailure extends StatefulWidget {
  const _OpenFailure({
    required this.i18n,
    required this.path,
    required this.open,
  });
  final DshI18n i18n;
  final String path;
  final VoidCallback open;
  @override
  State<_OpenFailure> createState() => _OpenFailureState();
}

class _OpenFailureState extends State<_OpenFailure> {
  @override
  Widget build(BuildContext context) {
    String t(String key) =>
        widget.i18n.t('reference', key, params: {'path': widget.path});
    void close() => Navigator.of(context).pop();
    return DshDialogFrame(
      width: 380,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DshChromeText(
                    t('fileOpen.title'),
                    style: context.dsh.textStyle('--dsw-font-base-16'),
                  ),
                ),
                GestureDetector(
                  onTap: close,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox.square(
                    dimension: 28,
                    child: Center(
                      child: DshIcon(
                        DshIcons.close,
                        size: 14,
                        color: context.dsh.labelSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DshChromeText(
              t('fileOpen.failed'),
              style: context.dsh.textStyle('--dsw-font-s-14'),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DshButton(
                  variant: DshButtonVariant.outline,
                  onPressed: close,
                  child: DshChromeText(t('fileOpen.close')),
                ),
                const SizedBox(width: 8),
                DshButton(
                  onPressed: () {
                    try {
                      widget.open();
                      close();
                    } on Object {
                      /* Keep the same path and retry. */
                    }
                  },
                  child: DshChromeText(t('fileOpen.retry')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
