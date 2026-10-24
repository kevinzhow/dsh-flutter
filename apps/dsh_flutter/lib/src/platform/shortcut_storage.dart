import 'dart:io';

import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:path_provider/path_provider.dart';

/// The preference document on disk (dsh Desktop keeps `userData/keybindings.json`
/// beside the window, independent of the Harness home and of any host): read
/// whole, replaced whole through a temporary file and a rename.
class FileShortcutStorage implements ShortcutStorage {
  FileShortcutStorage(this.file);

  final File file;

  /// `keybindings.json` in the application support directory.
  static Future<FileShortcutStorage> inSupportDirectory() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return FileShortcutStorage(File('${dir.path}/keybindings.json'));
  }

  @override
  Future<String?> read() async =>
      await file.exists() ? file.readAsString() : null;

  @override
  Future<void> write(String raw) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(raw, flush: true);
    await tmp.rename(file.path);
  }
}

/// The shortcut platform of the running OS.
ShortcutPlatform currentShortcutPlatform() => Platform.isMacOS
    ? ShortcutPlatform.macos
    : Platform.isWindows
    ? ShortcutPlatform.windows
    : ShortcutPlatform.linux;
