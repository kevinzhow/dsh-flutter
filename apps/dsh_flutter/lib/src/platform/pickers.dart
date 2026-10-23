import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// A [LocalFile] over an [XFile] (image picker, camera, a dropped file).
Future<LocalFile> pickedFromXFile(XFile file) async => LocalFile(
  name: file.name,
  size: await file.length(),
  mediaType: file.mimeType,
  open: () => file.openRead(),
  read: () => file.readAsBytes(),
);

/// A [LocalFile] over a file the file picker returned.
Future<LocalFile> pickedFromPlatformFile(PlatformFile file) async => LocalFile(
  name: file.name,
  size: (await file.length()) ?? 0,
  open: () => file.readAsByteStream(),
  read: () async => Uint8List.fromList(await file.readAsBytes()),
);

/// The platform's attach sources: photo library, camera and files on phones,
/// the file dialog on desktop.
class PlatformAttachmentPicker implements AttachmentPicker {
  PlatformAttachmentPicker({ImagePicker? images})
    : _images = images ?? ImagePicker();

  final ImagePicker _images;

  static bool get _phone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  List<AttachSource> get sources => _phone
      ? const [AttachSource.photos, AttachSource.camera, AttachSource.files]
      : const [AttachSource.files];

  @override
  Future<List<LocalFile>> pick(AttachSource source) async {
    switch (source) {
      case AttachSource.photos:
        final picked = await _images.pickMultiImage(requestFullMetadata: false);
        return [for (final f in picked) await pickedFromXFile(f)];
      case AttachSource.camera:
        final photo = await _images.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
        );
        return photo == null ? const [] : [await pickedFromXFile(photo)];
      case AttachSource.files:
        final picked = await FilePicker.pickFiles();
        return [for (final f in picked) await pickedFromPlatformFile(f)];
    }
  }
}
