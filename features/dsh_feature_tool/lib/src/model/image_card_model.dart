import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';

import 'raw_call.dart';

/// The image-card material one settled `read_image` call contributes (dsh
/// `ImageCardModel`): the read path plus the durable references the gallery
/// renders. The bytes are not here: the attachment id is opaque and resolves
/// to bytes through the session at render time.
class ImageCardModel {
  const ImageCardModel({
    required this.path,
    required this.images,
    required this.extraText,
    required this.originalSizes,
  });

  /// The resolved path as recorded, unshortened.
  final String path;
  final List<ImageRef> images;

  /// Text blocks other than the model-facing envelope, joined; null if none.
  final String? extraText;

  /// The pre-downscale size per image, where normalization reduced it.
  final List<({int width, int height})?> originalSizes;
}

final RegExp _envelope = RegExp(
  r'^<path>[^\n]*</path>\n<type>image</type>\n<content>\n[\s\S]*\n</content>$',
);

/// dsh `imageCardModel`: a settled card after validating the call head, the
/// persisted path (or, for a nested call, the argument), and the envelope.
/// Anything malformed declines (null) to the generic card, which shows the
/// flattened content rather than a partial gallery.
ImageCardModel? imageCardModel(ToolCall call) {
  if (call is! ToolResult || call.isError) return null;
  final parsed = parsedCall(call);
  if (parsed?.name != 'read_image') return null;
  final filePath = parsed!.args['file_path'];
  if (filePath is! String || filePath.trim().isEmpty) return null;
  final meta = call.meta;
  final metaPath =
      meta is Map &&
          meta['path'] is String &&
          (meta['path'] as String).isNotEmpty
      ? meta['path'] as String
      : null;
  // A root call with missing or malformed metadata declines; a nested one
  // (run_code) persists none and uses its own argument.
  final path = metaPath ?? (call.parentCallId != null ? filePath : null);
  if (path == null) return null;
  // Only text and image blocks are rendered; any other block declines.
  for (final part in call.content) {
    if (part is! Map) return null;
    final type = part['type'];
    if (!(type == 'image' || (type == 'text' && part['text'] is String))) {
      return null;
    }
  }
  final refs = <ImageRef>[];
  final originals = <({int width, int height})?>[];
  for (final part in call.content) {
    if (part is! Map || part['type'] != 'image') continue;
    final ref = ImageRef.tryParse(part['attachment']);
    if (ref == null) return null;
    final original = (part['attachment'] as Map)['originalDimensions'];
    if (original != null) {
      if (original is! Map ||
          original['width'] is! int ||
          (original['width'] as int) <= 0 ||
          original['height'] is! int ||
          (original['height'] as int) <= 0) {
        return null;
      }
      originals.add((
        width: original['width'] as int,
        height: original['height'] as int,
      ));
    } else {
      originals.add(null);
    }
    refs.add(ref);
  }
  if (refs.isEmpty) return null;
  final texts = [
    for (final part in call.content)
      if (part is Map && part['type'] == 'text') part['text'] as String,
  ];
  if (!texts.any(_envelope.hasMatch)) return null;
  final extra = texts.where((t) => !_envelope.hasMatch(t)).toList();
  return ImageCardModel(
    path: path,
    images: refs,
    extraText: extra.isEmpty ? null : extra.join('\n'),
    originalSizes: originals,
  );
}
