import 'dart:async';

import 'package:dsh_client/generated_directory_picker.dart';
import 'package:dsh_conversation/dsh_conversation.dart' show AbortSignal;

/// A host file tree: a directory maps to its child names (a leading dot marks
/// a hidden one).
class FakeFs {
  FakeFs(this.tree);

  /// The tree the tests walk: a home with two projects, a hidden folder and a
  /// few empty ones.
  factory FakeFs.standard() => FakeFs({
    '/': ['home', 'tmp'],
    '/home': ['u'],
    '/home/u': ['code', 'docs', '.config', 'notes'],
    '/home/u/code': ['alpha', 'beta'],
    '/home/u/code/alpha': ['src'],
    '/home/u/code/beta': [],
    '/home/u/code/alpha/src': [],
    '/home/u/docs': [],
    '/home/u/.config': [],
    '/home/u/notes': [],
    '/tmp': [],
  });
  final Map<String, List<String>> tree;
  final String home = '/home/u';
  final List<String> listed = [];
  final List<(String, String)> made = [];
  Object? failList;
  Map<String, Completer<void>> gates = {};
  int abortedScans = 0;

  DirectoryEntry entry(String path) => DirectoryEntry(
    name: path.split('/').last.isEmpty ? '/' : path.split('/').last,
    path: path,
    hidden: path.split('/').last.startsWith('.'),
  );

  Future<DirectoryListing> list(String? path, AbortSignal signal) async {
    var at = path ?? home;
    if (at.length > 1 && at.endsWith('/')) at = at.substring(0, at.length - 1);
    listed.add(at);
    signal.onAbort(() => abortedScans++);
    final gate = gates[at];
    if (gate != null) await gate.future;
    if (failList != null && at == '/denied') throw failList!;
    final children = tree[at];
    if (children == null) throw StateError('unreadable $at');
    final parts = at.split('/').where((p) => p.isNotEmpty).toList();
    final crumbs = [
      const DirectoryEntry(name: '/', path: '/', hidden: false),
      for (var i = 0; i < parts.length; i++)
        entry('/${parts.sublist(0, i + 1).join('/')}'),
    ];
    return DirectoryListing(
      path: at,
      home: home,
      crumbs: crumbs,
      entries: [for (final c in children) entry('${at == '/' ? '' : at}/$c')],
      truncated: false,
    );
  }

  Future<String> create(String path, String name) async {
    made.add((path, name));
    if (name == 'exists') throw StateError('already exists');
    tree[path] = [...?tree[path], name];
    tree['$path/$name'] = [];
    return '$path/$name';
  }
}
