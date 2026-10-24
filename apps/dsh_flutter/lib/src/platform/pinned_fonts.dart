import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

/// Registers the parity fonts when `WHALEE_PIN_FONTS` names their manifest
/// (`tool/parity-fonts/manifest.json`): the text stack's leading names
/// (`-apple-system`, `Segoe UI`, `SF Mono`, `PingFang SC`) then resolve to the
/// same Noto files the visual parity tool serves to dsh web, so a capture of
/// the running app compares layout, not which system font each side picked.
/// Nothing happens without the variable; the app never reads it in normal use.
Future<void> loadPinnedFontsFromEnvironment() async {
  final path = Platform.environment['WHALEE_PIN_FONTS'];
  if (path == null || path.isEmpty) return;
  final manifest = File(path);
  if (!manifest.existsSync()) return;
  final data = json.decode(manifest.readAsStringSync()) as Map<String, Object?>;
  final byName = <String, List<File>>{};
  for (final family
      in (data['families']! as List).cast<Map<String, Object?>>()) {
    for (final name in (family['names']! as List).cast<String>()) {
      for (final face
          in (family['faces']! as List).cast<Map<String, Object?>>()) {
        byName
            .putIfAbsent(name, () => [])
            .add(File('${manifest.parent.path}/${face['file']}'));
      }
    }
  }
  for (final entry in byName.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      final bytes = file.readAsBytesSync();
      loader.addFont(
        Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(bytes))),
      );
    }
    await loader.load();
  }
}
