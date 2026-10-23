import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dsh_slots/dsh_slots.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// A file name safe to create in a temporary directory.
String safeFileName(String name) {
  final leaf = name.split(RegExp(r'[/\\]')).last.trim();
  final cleaned = leaf.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_');
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
      ? 'file'
      : cleaned;
}

/// Downloads to the app's temporary directory, then opens with the system's
/// viewer (`open_filex`) or saves a copy through the platform's save dialog.
class PlatformFileActions implements HostFileActions {
  PlatformFileActions({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  @override
  bool get canOpen => true;

  @override
  bool get canSave => true;

  @override
  Future<HostFileSink> begin(String name) async {
    final base = _directory ?? await getTemporaryDirectory();
    final dir = await Directory(
      '${base.path}/whalee-download-${Random.secure().nextInt(1 << 32)}',
    ).create(recursive: true);
    final file = File('${dir.path}/${safeFileName(name)}');
    return _FileSink(file, dir, safeFileName(name));
  }
}

class _FileSink implements HostFileSink {
  _FileSink(this.file, this.dir, this.name) : _out = file.openWrite();

  final File file;
  final Directory dir;
  final String name;
  final IOSink _out;

  @override
  Future<void> add(Uint8List bytes) async {
    _out.add(bytes);
  }

  @override
  Future<void> finish() => _out.close();

  @override
  Future<bool> open() async {
    final result = await OpenFilex.open(file.path);
    return result.type == ResultType.done;
  }

  @override
  Future<bool> save() async {
    final bytes = await file.readAsBytes();
    final saved = await FilePicker.saveFile(fileName: name, bytes: bytes);
    return saved != null;
  }

  @override
  Future<void> discard() async {
    try {
      await _out.close();
    } on Object {
      // already closed
    }
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // best effort
    }
  }
}
