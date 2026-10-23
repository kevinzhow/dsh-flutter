import 'dart:convert';
import 'dart:typed_data';

import 'remote_caller.dart';

/// Decode a binary unary result: dsh's Connection answers a successful call
/// whose result holds `Uint8Array` fields with `multipart/form-data` (docs:
/// connection README, "Unary RPC requests use JSON ... Host handler may return
/// byte attachments"). Part `metadata` is the JSON `server-response` envelope
/// with `null` placeholders plus an `attachments` table `{path, codec: 'bytes',
/// part}`; every other part carries the raw bytes of one attachment.
///
/// Returns the envelope map with each placeholder replaced by a [Uint8List].
/// Throws [RemoteException] (`transport/bad-envelope`) on anything malformed,
/// like the web client's `parseBinaryResponse`.
Map<String, Object?> decodeBinaryResponse(String contentType, Uint8List body) {
  final boundary = multipartBoundary(contentType);
  if (boundary == null) {
    throw _bad('multipart response without a boundary');
  }
  final parts = <String, Uint8List>{};
  for (final part in parseMultipart(body, boundary)) {
    if (parts.containsKey(part.name)) {
      throw _bad('duplicate part "${part.name}"');
    }
    parts[part.name] = part.data;
  }
  final metadata = parts.remove('metadata');
  if (metadata == null) {
    throw _bad('missing metadata part');
  }
  final Object? envelope;
  try {
    envelope = jsonDecode(utf8.decode(metadata));
  } on FormatException {
    throw _bad('metadata is not JSON');
  }
  if (envelope is! Map<String, Object?>) {
    throw _bad('metadata is not an object');
  }
  final attachments = envelope['attachments'];
  final result = envelope['result'];
  if (result is! Map<String, Object?> ||
      result['ok'] != true ||
      attachments is! List ||
      attachments.isEmpty) {
    throw _bad('metadata is not a successful binary result');
  }
  final root = <String, Object?>{'value': result['value']};
  for (final a in attachments) {
    if (a is! Map<String, Object?> ||
        a['codec'] != 'bytes' ||
        a['part'] is! String ||
        a['path'] is! List) {
      throw _bad('invalid attachment entry');
    }
    final data = parts.remove(a['part']);
    if (data == null) {
      throw _bad('missing attachment part');
    }
    _place(root, (a['path'] as List).cast<Object?>(), data);
  }
  if (parts.isNotEmpty) {
    throw _bad('unreferenced parts');
  }
  return {
    ...envelope,
    'result': {...result, 'value': root['value']},
  };
}

/// Put [data] where the `null` placeholder at [path] (below `value`) is.
void _place(Map<String, Object?> root, List<Object?> path, Uint8List data) {
  Object? parent = root;
  Object key = 'value';
  for (final segment in path) {
    final value = _child(parent, key);
    if (value is List) {
      if (segment is! int || segment < 0 || segment >= value.length) {
        throw _bad('attachment path leaves the result');
      }
    } else if (value is Map<String, Object?>) {
      if (segment is! String || !value.containsKey(segment)) {
        throw _bad('attachment path leaves the result');
      }
    } else {
      throw _bad('attachment path leaves the result');
    }
    parent = value;
    key = segment as Object;
  }
  if (_child(parent, key) != null) {
    throw _bad('attachment placeholder is not null');
  }
  if (parent is List) {
    parent[key as int] = data;
  } else {
    (parent as Map<String, Object?>)[key as String] = data;
  }
}

Object? _child(Object? parent, Object key) {
  if (parent is Map<String, Object?> && key is String) {
    return parent[key];
  }
  if (parent is List && key is int) {
    return key < parent.length ? parent[key] : null;
  }
  return null;
}

RemoteException _bad(String why) =>
    RemoteException('transport/bad-envelope', 'binary result: $why');

/// The `boundary` parameter of a `multipart/form-data` content type.
String? multipartBoundary(String contentType) {
  for (final piece in contentType.split(';').skip(1)) {
    final p = piece.trim();
    if (p.toLowerCase().startsWith('boundary=')) {
      var value = p.substring('boundary='.length).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

/// One form-data part: `name` from its Content-Disposition, raw bytes.
class MultipartPart {
  const MultipartPart(this.name, this.data);
  final String name;
  final Uint8List data;
}

/// Split a `multipart/form-data` [body] on [boundary] (binary safe). Parts
/// without a `name` are rejected.
List<MultipartPart> parseMultipart(Uint8List body, String boundary) {
  final delimiter = ascii.encode('--$boundary');
  final out = <MultipartPart>[];
  var pos = _indexOf(body, delimiter, 0);
  if (pos < 0) {
    throw _bad('no boundary in body');
  }
  while (true) {
    pos += delimiter.length;
    // `--` after a delimiter closes the body.
    if (pos + 1 < body.length && body[pos] == 0x2d && body[pos + 1] == 0x2d) {
      return out;
    }
    // Skip the rest of the delimiter line (CRLF).
    if (pos + 1 < body.length && body[pos] == 0x0d && body[pos + 1] == 0x0a) {
      pos += 2;
    } else {
      throw _bad('malformed boundary line');
    }
    final headerEnd = _indexOf(body, const [0x0d, 0x0a, 0x0d, 0x0a], pos);
    if (headerEnd < 0) {
      throw _bad('unterminated part headers');
    }
    final headers = latin1.decode(body.sublist(pos, headerEnd));
    final name = _dispositionName(headers);
    if (name == null) {
      throw _bad('part without a name');
    }
    final dataStart = headerEnd + 4;
    final next = _indexOf(body, [0x0d, 0x0a, ...delimiter], dataStart);
    if (next < 0) {
      throw _bad('unterminated part');
    }
    out.add(MultipartPart(name, Uint8List.sublistView(body, dataStart, next)));
    pos = next + 2;
  }
}

String? _dispositionName(String headers) {
  for (final line in headers.split('\r\n')) {
    if (!line.toLowerCase().startsWith('content-disposition:')) continue;
    final m = RegExp(r'[;\s]name="((?:[^"\\]|\\.)*)"').firstMatch(line);
    if (m != null) {
      return m.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (x) => x.group(1)!);
    }
  }
  return null;
}

int _indexOf(Uint8List haystack, List<int> needle, int start) {
  final first = needle[0];
  final last = haystack.length - needle.length;
  for (var i = start; i <= last; i++) {
    if (haystack[i] != first) continue;
    var j = 1;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) {
      return i;
    }
  }
  return -1;
}
