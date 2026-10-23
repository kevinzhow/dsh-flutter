import 'package:dsh_ui/dsh_ui.dart';

/// How a renderer gets its content (dsh `DocumentLoadMode`).
enum DocumentLoad { textPages, bytesComplete }

/// One registered way to show a file (dsh `DocumentPreviewDefinition`).
class DocumentRenderer {
  const DocumentRenderer({
    required this.id,
    required this.titleNamespace,
    required this.titleKey,
    required this.extensions,
    required this.loading,
    this.binaryExtensions = const [],
    this.wrap = false,
  });

  final String id;

  /// Where the viewer's name lives in dsh's dictionaries.
  final String titleNamespace;
  final String titleKey;

  /// Suffixes without a leading dot.
  final List<String> extensions;

  /// Suffixes among [extensions] whose bytes are not readable text: a file
  /// matching one loses the plain-text fallback among its viewer choices.
  final List<String> binaryExtensions;
  final DocumentLoad loading;

  /// Whether the renderer takes the document toolbar's wrap preference.
  final bool wrap;
}

const String imageRendererId = 'image';
const String markdownRendererId = 'markdown';
const String codeRendererId = 'code';
const String plainRendererId = 'text';

/// The renderers of this client, in registration order (dsh registers
/// image, markdown, code and the plain fallback; PDF, spreadsheet, Office and
/// HTML viewers are not ported: those files offer open and save instead).
final List<DocumentRenderer> documentRenderers = [
  const DocumentRenderer(
    id: imageRendererId,
    titleNamespace: 'sidebarImage',
    titleKey: 'title',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'svg'],
    binaryExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico'],
    loading: DocumentLoad.bytesComplete,
  ),
  const DocumentRenderer(
    id: markdownRendererId,
    titleNamespace: 'documentMarkdown',
    titleKey: 'viewer.label',
    extensions: ['md', 'markdown'],
    loading: DocumentLoad.textPages,
  ),
  DocumentRenderer(
    id: codeRendererId,
    titleNamespace: 'sidebarCodePreview',
    titleKey: 'title',
    extensions: dshCodeLanguageExtensions,
    loading: DocumentLoad.textPages,
    wrap: true,
  ),
];

/// The plain-text fallback every readable file can use.
const DocumentRenderer plainRenderer = DocumentRenderer(
  id: plainRendererId,
  titleNamespace: 'sidebarDocumentPreview',
  titleKey: 'viewer.text',
  extensions: [],
  loading: DocumentLoad.textPages,
  wrap: true,
);

/// Known binary container suffixes with no renderer (dsh
/// `UNVIEWABLE_BINARY_EXTENSIONS`, plus the formats its PDF, spreadsheet and
/// Office viewers claim, which this client does not draw). They get the
/// unsupported empty state instead of the plain-text fallback.
const List<String> unviewableBinaryExtensions = [
  'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv', 'm4v', //
  'mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'wma', 'opus',
  'zip', 'gz', 'tgz', 'bz2', 'xz', 'zst', '7z', 'rar', 'tar', 'jar',
  'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'pages',
  'numbers',
  'exe', 'dll', 'so', 'dylib', 'bin', 'o', 'class', 'pyc', 'wasm',
  'ttf', 'otf', 'woff', 'woff2', 'eot',
  'dmg', 'iso', 'img', 'sqlite', 'db',
  'psd', 'ai', 'sketch', 'tiff', 'tif', 'heic', 'heif', 'avif',
  'pdf',
];

/// The lower-cased final path segment (dsh `documentFileName`).
String documentFileName(String path) {
  final normalized = path.replaceAll(r'\', '/').toLowerCase();
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

int _matchedLength(String name, List<String> extensions) {
  var best = 0;
  for (final raw in extensions) {
    final e = raw.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (name.endsWith('.$e') && e.length > best) best = e.length;
  }
  return best;
}

/// Whether the suffix is a known binary container no renderer shows.
bool unviewableBinaryPath(String path) =>
    _matchedLength(documentFileName(path), unviewableBinaryExtensions) > 0;

/// The renderers that can show [path], best first (dsh `matchingDocumentPreviews`
/// and the candidate rule of `TextPreview`): longest matching suffix, then
/// registration order; the plain fallback last unless the file is binary.
/// Empty for a known binary suffix nothing renders.
List<DocumentRenderer> rendererCandidates(String path) {
  final name = documentFileName(path);
  final matched = <({DocumentRenderer renderer, int order, int length})>[];
  for (var i = 0; i < documentRenderers.length; i++) {
    final length = _matchedLength(name, documentRenderers[i].extensions);
    if (length > 0) {
      matched.add((renderer: documentRenderers[i], order: i, length: length));
    }
  }
  matched.sort(
    (a, b) => b.length != a.length
        ? b.length.compareTo(a.length)
        : a.order.compareTo(b.order),
  );
  final list = [for (final m in matched) m.renderer];
  final binary = documentRenderers.any(
    (r) => _matchedLength(name, r.binaryExtensions) > 0,
  );
  if (list.isNotEmpty && binary) return list;
  if (list.isEmpty && unviewableBinaryPath(path)) return list;
  return [...list, plainRenderer];
}
