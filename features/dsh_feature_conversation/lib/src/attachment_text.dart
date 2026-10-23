import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';

/// dsh `imageSizeText`: bytes as megabytes (`10MB`, `2.5MB`).
String imageSizeText(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb == mb.truncateToDouble() ? mb.toInt().toString() : mb.toStringAsFixed(1)}MB';
}

/// Product copy for a host attachment refusal (dsh `attachmentErrorText`):
/// reasons a person can act on name the limit and the way out, the rest fold
/// into one send-failed line carrying the reason code.
String attachmentErrorText(DshI18n i18n, String reason, ImageLimits? limits) {
  String c(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('conversation', key, params: params);
  switch (reason) {
    case 'MODEL_DOES_NOT_SUPPORT_IMAGES':
      return c('image.modelUnsupported');
    case 'FILE_NOT_STAGED':
      return c('file.notStaged');
    case 'IMAGE_TOO_MANY_PIXELS':
      return c('image.tooManyPixels');
    case 'IMAGE_DIMENSION_TOO_LARGE':
      if (limits != null) {
        return c('image.dimensionTooLarge', {'size': limits.maxImageDimension});
      }
    case 'INVALID_IMAGE' || 'IMAGE_TYPE_MISMATCH':
      return c('image.unsupportedType');
    case 'TOO_MANY_IMAGES':
      if (limits != null) {
        return c('image.tooMany', {'count': limits.maxImagesPerMessage});
      }
    case 'IMAGE_TOO_LARGE':
      if (limits != null) {
        return c('image.fileTooLarge', {
          'size': imageSizeText(limits.maxImageBytes),
        });
      }
    case 'IMAGES_TOO_LARGE':
      if (limits != null) {
        return c('image.totalTooLarge', {
          'size': imageSizeText(limits.maxMessageImageBytes),
        });
      }
  }
  return c('image.sendFailed', {'reason': reason});
}

/// The copy for an intake refusal (the pre-check before any draft exists).
String intakeRefusalText(DshI18n i18n, IntakeResult result) {
  String c(String key, Map<String, Object?> params) =>
      i18n.t('conversation', key, params: params);
  return switch (result.refusal!) {
    IntakeRefusal.tooManyImages => c('image.tooMany', {'count': result.limit}),
    IntakeRefusal.imageTooLarge => c('image.fileTooLarge', {
      'size': imageSizeText(result.limit!),
    }),
    IntakeRefusal.imagesTooLarge => c('image.totalTooLarge', {
      'size': imageSizeText(result.limit!),
    }),
  };
}

/// The copy for a failed upload (dsh shows `file.uploadFailed`; a refusal with
/// a reason the person can act on names it).
String uploadFailureText(DshI18n i18n, Object error, ImageLimits? limits) {
  final reason = attachmentRefusalReason(error);
  if (reason != null && reason.isNotEmpty) {
    return attachmentErrorText(i18n, reason, limits);
  }
  return i18n.t('conversation', 'file.uploadFailed');
}
