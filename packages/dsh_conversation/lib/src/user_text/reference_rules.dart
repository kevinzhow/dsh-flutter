import 'document.dart';

UserTextRule _pathRule(bool folder) => UserTextRule(
  id: folder ? 'folder' : 'file',
  order: 30,
  match: (text, from, _) {
    final tokens = RegExp(r'(?<!\S)(@"[^"\n]+"|@[^\s]+)', unicode: true);
    for (final token in tokens.allMatches(text, from)) {
      final spelling = token.group(0)!;
      final raw = spelling.startsWith('@"')
          ? spelling
          : spelling.replaceFirst(
              RegExp(r'[.,;:!?，。；：！？]+$', unicode: true),
              '',
            );
      if (raw.length <= 1) continue;
      final path = raw
          .substring(1)
          .replaceAll(RegExp(r'^"|"$', unicode: true), '');
      if (path.endsWith('/') != folder) continue;
      final parts = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
      return UserTextNode(
        folder ? 'folder' : 'file',
        token.start,
        token.start + raw.length,
        {'path': path, 'label': parts.lastOrNull ?? raw.substring(1)},
      );
    }
    return null;
  },
);
final fileReferenceRule = _pathRule(false);
final folderReferenceRule = _pathRule(true);

final sessionReferenceRule = UserTextRule(
  id: 'session',
  order: 10,
  match: (text, from, context) {
    List<String>? labels;
    var readLabels = false;
    final wire = RegExp(
      r'@\[([^\]\n]+)\]\(dsh-session:[^)\s]+\)',
      unicode: true,
    );
    for (
      var start = text.indexOf('@', from);
      start >= 0;
      start = text.indexOf('@', start + 1)
    ) {
      final explicit = wire.matchAsPrefix(text, start);
      if (explicit != null) {
        return UserTextNode('session', start, explicit.end, {
          'label': explicit.group(1)!,
        });
      }
      if (!readLabels) {
        final value = context.read('sessionLabels');
        labels = value is List<String> ? value : null;
        readLabels = true;
      }
      String? best;
      for (final label in labels ?? const <String>[]) {
        if (label.isNotEmpty &&
            text.startsWith(label, start + 1) &&
            (best == null || label.length > best.length)) {
          best = label;
        }
      }
      if (best != null) {
        return UserTextNode('session', start, start + best.length + 1, {
          'label': best,
        });
      }
    }
    return null;
  },
);

UserTextNode _replacement(String text, int start, int end, String display) =>
    UserTextNode('text', start, end, {
      'text': text.substring(start, end),
      'display': display,
    });
final trimWhitespaceRule = UserTextRule(
  id: 'text.trim-whitespace',
  order: 1000,
  match: (text, from, context) {
    if (context.read('trimWhitespace') != true) return null;
    if (from == 0) {
      final leading = RegExp(r'^\s+', unicode: true).firstMatch(text);
      if (leading != null) return _replacement(text, 0, leading.end, '');
    }
    final trailing = RegExp(r'\s+$', unicode: true).firstMatch(text);
    return trailing == null || trailing.start < from
        ? null
        : _replacement(text, trailing.start, text.length, '');
  },
);
final collapseWhitespaceRule = UserTextRule(
  id: 'text.collapse-whitespace',
  order: 1010,
  match: (text, from, context) {
    if (context.read('collapseWhitespace') != true) return null;
    final space = RegExp(r'\s', unicode: true);
    for (final match in RegExp(r'\s+', unicode: true).allMatches(text, from)) {
      if ((match.start > 0 &&
              space.hasMatch(text.substring(match.start - 1, match.start))) ||
          match.group(0) == ' ') {
        continue;
      }
      return _replacement(text, match.start, match.end, ' ');
    }
    return null;
  },
);
