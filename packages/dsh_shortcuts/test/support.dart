import 'dart:convert';

import 'package:dsh_shortcuts/dsh_shortcuts.dart';

ShortcutBinding primary(String code) =>
    ShortcutBinding(code, const [ShortcutModifier.primary]);

Map<String, Object?> primaryJson(String code) => {
  'code': code,
  'modifiers': ['primary'],
};

String jsonOf(ShortcutDocument document) => jsonEncode(document.toJson());

/// An in-memory storage whose raw text tests can read, replace and make fail.
class MemoryStorage implements ShortcutStorage {
  MemoryStorage([this.raw]);

  String? raw;
  int writes = 0;
  int reads = 0;
  Object? failNextRead;
  bool failReads = false;
  Object? failNextWrite;
  Future<void> Function()? onWrite;

  @override
  Future<String?> read() async {
    reads++;
    if (failReads) throw StateError('denied');
    final failure = failNextRead;
    if (failure != null) {
      failNextRead = null;
      throw failure;
    }
    return raw;
  }

  @override
  Future<void> write(String next) async {
    final failure = failNextWrite;
    if (failure != null) {
      failNextWrite = null;
      throw failure;
    }
    final hook = onWrite;
    if (hook != null) {
      onWrite = null;
      await hook();
    }
    raw = next;
    writes++;
  }
}
