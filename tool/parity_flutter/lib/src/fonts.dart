import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

/// One pinned face (see `tool/parity-fonts/manifest.json`).
class ParityFontFace {
  /// Creates a face record.
  const ParityFontFace({
    required this.family,
    required this.weight,
    required this.path,
    required this.sha256,
  });

  /// CSS/Flutter family name the face is registered under (`Segoe UI`).
  final String family;

  /// CSS weight.
  final int weight;

  /// Absolute file path.
  final String path;

  /// Digest from the manifest; `tool/parity fonts --check` verifies it before a run.
  final String sha256;

  /// Metadata shape shared with the React provider.
  Map<String, dynamic> toJson() => {
    'family': family,
    'weight': weight,
    'style': 'normal',
    'sha256': sha256,
  };
}

bool _loaded = false;

/// Registers every face of the parity fonts manifest with a [FontLoader] under its family name, so
/// the theme's text stack (`-apple-system, BlinkMacSystemFont, 'Segoe UI', ...`) resolves to the
/// same file the React provider serves for `Segoe UI`. Without this flutter_test would draw Ahem.
Future<List<ParityFontFace>> loadParityFonts(String manifestPath) async {
  final manifestFile = File(manifestPath);
  final manifest =
      json.decode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final faces = <ParityFontFace>[];
  for (final family
      in (manifest['families'] as List).cast<Map<String, dynamic>>()) {
    for (final face in (family['faces'] as List).cast<Map<String, dynamic>>()) {
      for (final name in (family['names'] as List).cast<String>()) {
        faces.add(
          ParityFontFace(
            family: name,
            weight: face['weight'] as int,
            path: '${manifestFile.parent.path}/${face['file']}',
            sha256: face['sha256'] as String,
          ),
        );
      }
    }
  }
  if (_loaded) return faces;
  final byFamily = <String, List<ParityFontFace>>{};
  for (final face in faces) {
    byFamily.putIfAbsent(face.family, () => []).add(face);
  }
  for (final entry in byFamily.entries) {
    final loader = FontLoader(entry.key);
    for (final face in entry.value) {
      final bytes = File(face.path).readAsBytesSync();
      loader.addFont(
        Future<ByteData>.value(ByteData.sublistView(Uint8List.fromList(bytes))),
      );
    }
    await loader.load();
  }
  _loaded = true;
  return faces;
}

/// Finds `tool/parity-fonts/manifest.json` from `PARITY_FONTS_MANIFEST` or by walking up from the
/// working directory.
String findParityFontsManifest() {
  final env = Platform.environment['PARITY_FONTS_MANIFEST'];
  if (env != null && env.isNotEmpty) return env;
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = File('${dir.path}/tool/parity-fonts/manifest.json');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError(
    'tool/parity-fonts/manifest.json not found from ${Directory.current.path}',
  );
}
