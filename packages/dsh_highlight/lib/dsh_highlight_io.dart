/// A [GrammarSource] reading grammar JSON files from a directory.
library;

import 'dart:io';

import 'src/api.dart';

class FileGrammarSource implements GrammarSource {
  /// [directory] holds `<id>.json` files (the package's `assets/grammars`).
  FileGrammarSource(this.directory)
    : available = {
        for (final f in Directory(directory).listSync())
          if (f is File && f.path.endsWith('.json'))
            if (_id(f.path) != 'index') _id(f.path),
      };

  final String directory;

  @override
  final Set<String> available;

  static String _id(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.substring(0, name.length - '.json'.length);
  }

  @override
  Future<String> read(String grammarId) =>
      File('$directory${Platform.pathSeparator}$grammarId.json').readAsString();
}
