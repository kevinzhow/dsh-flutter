import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'message_images.dart';

/// The composer's draft rail (dsh `ComposerAttachments`): images and files in
/// pick order on one horizontal rail, each 64 high. An image is a 64 square
/// thumbnail that opens the original; a file is a 240 wide card that shows its
/// upload progress, offers retry when the upload failed, and both have a
/// remove badge.
class ComposerAttachmentsView extends StatefulWidget {
  const ComposerAttachmentsView({
    super.key,
    required this.owner,
    required this.i18n,
  });

  final SessionOwner owner;
  final DshI18n i18n;

  @override
  State<ComposerAttachmentsView> createState() =>
      _ComposerAttachmentsViewState();
}

class _ComposerAttachmentsViewState extends State<ComposerAttachmentsView> {
  StreamSubscription<DraftSnapshot>? _sub;
  DraftAttachments? _drafts;
  final ScrollController _scroll = ScrollController();
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(ComposerAttachmentsView old) {
    super.didUpdateWidget(old);
    if (!identical(
      old.owner.attachments?.drafts,
      widget.owner.attachments?.drafts,
    )) {
      _bind();
    }
  }

  void _bind() {
    unawaited(_sub?.cancel());
    _drafts = widget.owner.attachments?.drafts;
    _seen = _drafts?.value.items.length ?? 0;
    _sub = _drafts?.state.changes.listen((s) {
      if (!mounted) return;
      // A newly added item is revealed at the rail's end.
      if (s.items.length > _seen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            unawaited(
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
              ),
            );
          }
        });
      }
      _seen = s.items.length;
      setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  String _c(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('conversation', key, params: params);

  @override
  Widget build(BuildContext context) {
    final drafts = _drafts;
    if (drafts == null) return const SizedBox.shrink();
    final snapshot = drafts.value;
    if (snapshot.items.isEmpty) return const SizedBox.shrink();
    final images = snapshot.items.whereType<DraftImage>().toList();
    final lightbox = lightboxLabels(widget.i18n);
    void openImage(DraftImage image) {
      unawaited(
        showDshLightbox(
          context,
          images: [
            for (final i in images)
              DshLightboxImage(
                label: i.name.isEmpty ? _c('image.original') : i.name,
                bytes: i.bytes,
              ),
          ],
          labels: lightbox,
          initialIndex: images.indexOf(image),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.sm),
      child: Semantics(
        container: true,
        label: _c('attachment.pending'),
        child: SizedBox(
          key: const ValueKey('composer-attachments'),
          height: 64,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: snapshot.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final item = snapshot.items[i];
              switch (item) {
                case DraftImage():
                  return DshDraftImage(
                    key: ValueKey('draft-${item.id}'),
                    bytes: item.bytes,
                    name: item.name,
                    openLabel: _c('image.openOriginal'),
                    removeLabel: _c('image.remove', {'name': item.name}),
                    onOpen: () => openImage(item),
                    onRemove: () => drafts.remove(item.id),
                  );
                case DraftFile():
                  final upload = snapshot.uploads[item.id];
                  final name = item.name.isEmpty ? _c('file.label') : item.name;
                  return DshFileCard(
                    key: ValueKey('draft-${item.id}'),
                    name: name,
                    bytes: item.size,
                    state: switch (upload) {
                      null || FileUploading() => DshFileCardState.uploading,
                      FileReady() => DshFileCardState.ready,
                      FileFailed() => DshFileCardState.error,
                    },
                    progress: upload is FileUploading ? upload.fraction : null,
                    labels: DshFileCardLabels(
                      label: _c('file.pending'),
                      remove: _c('file.remove', {'name': name}),
                      uploading: _c('file.uploading'),
                      failed: _c('file.uploadFailed'),
                      retry: _c('file.retry', {'name': name}),
                    ),
                    onRemove: () => drafts.remove(item.id),
                    onRetry: () => drafts.retry(item.id),
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}
