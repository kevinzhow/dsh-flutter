import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The labels of an image surface from dsh's `conversation` dictionary.
DshImageLabels imageLabels(DshI18n i18n) => DshImageLabels(
  open: i18n.t('conversation', 'image.openOriginal'),
  openNamed: (label) => i18n.t(
    'conversation',
    'image.openOriginalLabel',
    params: {'label': label},
  ),
  loading: i18n.t('conversation', 'image.loading'),
  loadFailed: i18n.t('conversation', 'image.loadFailed'),
  image: i18n.t('conversation', 'image.label'),
  lightbox: i18n.t('conversation', 'image.preview'),
  closeLightbox: i18n.t('conversation', 'image.closePreview'),
);

DshLightboxLabels lightboxLabels(DshI18n i18n) => DshLightboxLabels(
  dialog: i18n.t('conversation', 'image.preview'),
  close: i18n.t('conversation', 'image.closePreview'),
  loadFailed: i18n.t('conversation', 'image.loadFailed'),
  position: (index, total) => i18n.t(
    appNamespace,
    'attachment.position',
    params: {'index': index, 'total': total},
  ),
);

/// The lightbox item of one gallery image: durable images load through the
/// session's cache when opened.
DshLightboxImage lightboxItem(
  GalleryImage image,
  SessionOwner session,
  DshImageLabels labels,
) => switch (image) {
  PreviewGalleryImage() => DshLightboxImage(
    label: image.name == null || image.name!.isEmpty
        ? labels.image
        : image.name!,
    bytes: image.bytes,
  ),
  DurableGalleryImage() => DshLightboxImage(
    label: image.label ?? image.image.name ?? labels.image,
    bytes: session.session.images.peek(image.image.attachmentId),
    load: () => session.session.images.load(image.image),
  ),
};

/// An image group in a message, an assistant message or a tool result (dsh
/// `ImageGallery` through the `*.images` slots). Durable images load through
/// the session's cached `session/attachment` read with a retry control; a
/// message that is still being admitted shows its local preview bytes.
class MessageImagesView extends StatelessWidget {
  const MessageImagesView({super.key, required this.owner, required this.i18n});

  final ImageGalleryOwner owner;
  final DshI18n i18n;

  DshImageVariant get _variant => owner.thumbnail
      ? DshImageVariant.thumbnail
      : owner.compact || owner.images.length > 1
      ? DshImageVariant.tile
      : DshImageVariant.single;

  @override
  Widget build(BuildContext context) {
    if (owner.images.isEmpty) return const SizedBox.shrink();
    final labels = imageLabels(i18n);
    final group = owner.group ?? owner.images;
    final base = owner.group == null ? 0 : owner.groupIndex;
    void open(int offset) {
      final items = [
        for (final g in group) lightboxItem(g, owner.session, labels),
      ];
      unawaited(
        showDshLightbox(
          context,
          images: items,
          labels: lightboxLabels(i18n),
          initialIndex: base + offset,
        ),
      );
    }

    return DshImageGroup(
      alignEnd: owner.alignEnd,
      children: [
        for (var i = 0; i < owner.images.length; i++)
          _GalleryImage(
            key: ValueKey('gallery-image-$i'),
            image: owner.images[i],
            session: owner.session,
            variant: _variant,
            labels: labels,
            onOpen: () => open(i),
          ),
      ],
    );
  }
}

class _GalleryImage extends StatefulWidget {
  const _GalleryImage({
    super.key,
    required this.image,
    required this.session,
    required this.variant,
    required this.labels,
    required this.onOpen,
  });

  final GalleryImage image;
  final SessionOwner session;
  final DshImageVariant variant;
  final DshImageLabels labels;
  final VoidCallback onOpen;

  @override
  State<_GalleryImage> createState() => _GalleryImageState();
}

class _GalleryImageState extends State<_GalleryImage> {
  Uint8List? _bytes;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_GalleryImage old) {
    super.didUpdateWidget(old);
    final a = old.image;
    final b = widget.image;
    final same = switch ((a, b)) {
      (
        DurableGalleryImage(image: final x),
        DurableGalleryImage(image: final y),
      ) =>
        x.attachmentId == y.attachmentId,
      (
        PreviewGalleryImage(bytes: final x),
        PreviewGalleryImage(bytes: final y),
      ) =>
        identical(x, y),
      _ => false,
    };
    if (!same) _start();
  }

  void _start() {
    final image = widget.image;
    final attempt = ++_attempt;
    switch (image) {
      case PreviewGalleryImage():
        _bytes = image.bytes;
        _failed = false;
      case DurableGalleryImage():
        final images = widget.session.session.images;
        _bytes = images.peek(image.image.attachmentId);
        _failed = false;
        if (_bytes == null) {
          unawaited(
            images
                .load(image.image)
                .then(
                  (bytes) {
                    if (mounted && attempt == _attempt) {
                      setState(() => _bytes = bytes);
                    }
                  },
                  onError: (Object _) {
                    if (mounted && attempt == _attempt) {
                      setState(() => _failed = true);
                    }
                  },
                ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final (name, width, height) = switch (image) {
      DurableGalleryImage() => (
        image.label ?? image.image.name,
        image.image.width,
        image.image.height,
      ),
      PreviewGalleryImage() => (image.name, image.width, image.height),
    };
    return DshImageFrame(
      variant: widget.variant,
      labels: widget.labels,
      bytes: _bytes,
      failed: _failed,
      name: name,
      width: width,
      height: height,
      onOpen: widget.onOpen,
      onRetry: () => setState(_start),
    );
  }
}
