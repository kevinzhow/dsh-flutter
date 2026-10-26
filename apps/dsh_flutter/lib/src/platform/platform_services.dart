import 'dart:io' show Platform;

import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'file_actions.dart';
import 'pickers.dart';

/// What the platform gives the app beyond Flutter itself: pickers for
/// attachments and file handling. Tests build the app with none.
class PlatformServices {
  const PlatformServices({
    this.picker,
    this.fileActions,
    this.acceptsDrops = false,
    this.touchInput = false,
    this.timeZone = 'UTC',
  });

  /// The real services of the running platform.
  factory PlatformServices.current({String timeZone = 'UTC'}) =>
      PlatformServices(
        timeZone: timeZone,
        picker: PlatformAttachmentPicker(),
        fileActions: PlatformFileActions(),
        acceptsDrops:
            !kIsWeb &&
            (Platform.isLinux || Platform.isMacOS || Platform.isWindows),
        touchInput: !kIsWeb && (Platform.isAndroid || Platform.isIOS),
      );

  final String timeZone;
  final AttachmentPicker? picker;
  final HostFileActions? fileActions;

  /// A desktop window takes dropped files.
  final bool acceptsDrops;

  /// Input is by touch (no hover): controls that reveal on hover stay visible.
  final bool touchInput;
}
