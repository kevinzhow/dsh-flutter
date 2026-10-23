/// Grammars bundled as Flutter assets.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'src/api.dart';

/// Reads `packages/dsh_highlight/assets/grammars/<id>.json` from [bundle]
/// (default: [rootBundle]).
class AssetGrammarSource implements GrammarSource {
  AssetGrammarSource({AssetBundle? bundle, required this.available})
    : _bundle = bundle ?? rootBundle;

  /// Builds a source from the bundled `index.json` (the converted-grammar
  /// list written by tool/highlight/convert.mjs).
  static Future<AssetGrammarSource> create({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final index = jsonDecode(
      await b.loadString('$assetDirectory/index.json'),
    ) as Map<String, dynamic>;
    final grammars = (index['grammars'] as Map<String, dynamic>).keys.toSet();
    return AssetGrammarSource(bundle: b, available: grammars);
  }

  static const String assetDirectory = 'packages/dsh_highlight/assets/grammars';

  final AssetBundle _bundle;

  @override
  final Set<String> available;

  @override
  Future<String> read(String grammarId) =>
      _bundle.loadString('$assetDirectory/$grammarId.json');
}
