import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';

class HtmlPackedAsset {
  const HtmlPackedAsset(this.kind, this.reference, this.text);
  final String kind, reference, text;
}

class HtmlPackedDocument {
  const HtmlPackedDocument(this.text, this.assets);
  final String text;
  final List<HtmlPackedAsset> assets;
}

String decodeHtmlBytes(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: false);

/// Finite HTML-declared classic .js/.css only. The supplied reader is bound to
/// the original Session and base file; no browser message can request files.
Future<HtmlPackedDocument> packHtmlDocument(
  Uint8List data,
  Future<Uint8List> Function(String relative) read, {
  void Function()? checkCancelled,
}) async {
  checkCancelled?.call();
  var total = data.length;
  if (total > 32 * 1024 * 1024) {
    throw const FormatException('HTML package exceeds total byte limit');
  }
  final text = decodeHtmlBytes(data);
  final parsed = html.parseFragment(text, container: 'template');
  final assets = <HtmlPackedAsset>[];
  if (parsed.querySelector('base[href]') != null) {
    return HtmlPackedDocument(text, assets);
  }
  final seen = <String>{};
  for (final element in parsed.querySelectorAll('script[src],link[href]')) {
    final script = element.localName == 'script';
    final type = (element.attributes['type'] ?? '').trim().toLowerCase();
    if (script &&
        !['', 'text/javascript', 'application/javascript'].contains(type)) {
      continue;
    }
    if (!script &&
        !(element.attributes['rel'] ?? '')
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .contains('stylesheet')) {
      continue;
    }
    final reference = element.attributes[script ? 'src' : 'href']!;
    final suffix = reference.indexOf(RegExp(r'[?#]'));
    final path = suffix < 0 ? reference : reference.substring(0, suffix);
    if (reference.isEmpty ||
        RegExp(
          r'^(?:[a-z][a-z\d+.-]*:|[/\\#?])',
          caseSensitive: false,
        ).hasMatch(reference) ||
        reference.contains('\x00')) {
      continue;
    }
    if (!RegExp(
      script ? r'\.js$' : r'\.css$',
      caseSensitive: false,
    ).hasMatch(path)) {
      continue;
    }
    final kind = script ? 'script' : 'stylesheet', key = '$kind:$reference';
    if (seen.contains(key)) continue;
    if (assets.length >= 64) {
      throw const FormatException('HTML package exceeds asset count limit');
    }
    checkCancelled?.call();
    final bytes = await read(reference);
    checkCancelled?.call();
    if (bytes.length > 4 * 1024 * 1024) {
      throw const FormatException('HTML asset exceeds byte limit');
    }
    total += bytes.length;
    if (total > 32 * 1024 * 1024) {
      throw const FormatException('HTML package exceeds total byte limit');
    }
    assets.add(HtmlPackedAsset(kind, reference, decodeHtmlBytes(bytes)));
    seen.add(key);
  }
  return HtmlPackedDocument(text, assets);
}

String htmlRelativeFile(String reference) {
  final suffix = reference.indexOf(RegExp(r'[?#]'));
  final path = Uri.decodeComponent(
    suffix < 0 ? reference : reference.substring(0, suffix),
  );
  if (path.isEmpty ||
      RegExp(
        r'^(?:[a-z][a-z\d+.-]*:|[/\\])',
        caseSensitive: false,
      ).hasMatch(path) ||
      path.contains('\x00') ||
      path.contains('\\')) {
    throw const FormatException(
      'HTML dependency must use a relative file path',
    );
  }
  return path;
}

String createBasicHtmlDocument(Uint8List data) {
  final document = html.parse(decodeHtmlBytes(data));
  const forbidden = {
    'script',
    'noscript',
    'base',
    'link',
    'meta',
    'iframe',
    'frame',
    'object',
    'embed',
    'set',
    'animate',
    'animatemotion',
    'animatetransform',
  };
  for (final element in document.querySelectorAll('*').toList()) {
    if (forbidden.contains(element.localName)) {
      element.remove();
      continue;
    }
    element.attributes.removeWhere(
      (key, value) =>
          key.toString().toLowerCase().startsWith('on') ||
          const {
            'href',
            'xlink:href',
            'srcdoc',
          }.contains(key.toString().toLowerCase()),
    );
  }
  final policy = Element.tag('meta')
    ..attributes['http-equiv'] = 'Content-Security-Policy'
    ..attributes['content'] =
        "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; media-src data:; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'";
  document.head!.nodes.insert(0, policy);
  return '<!doctype html>${document.documentElement!.outerHtml}';
}

String createInteractiveHtmlDocument(HtmlPackedDocument document) {
  final payload = base64Encode(
    utf8.encode(
      jsonEncode({
        'html': document.text,
        'assets': [
          for (final asset in document.assets)
            {
              'kind': asset.kind,
              'reference': asset.reference,
              'text': asset.text,
            },
        ],
      }),
    ),
  );
  // This fixed bootstrap runs inside the opaque child, never the application.
  return '''<!doctype html><meta charset="utf-8"><script>(()=>{
const text=data=>new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(data),c=>c.charCodeAt(0)));
const bundle=JSON.parse(text("$payload"));let html=bundle.html;
if(bundle.assets.length){const parsed=new DOMParser().parseFromString(html,'text/html');
for(const asset of bundle.assets){const script=asset.kind==='script';
const url=URL.createObjectURL(new Blob([asset.text],{type:script?'application/javascript':'text/css'}));
const attribute=script?'src':'href';for(const element of parsed.querySelectorAll(script?'script[src]':'link[rel~="stylesheet" i][href]')){
if(element.getAttribute(attribute)===asset.reference)element.setAttribute(attribute,url);}}
html='<!doctype html>'+parsed.documentElement.outerHTML;}
document.open();document.write(html);document.close();})()</script>''';
}

/// The native browser gets a trusted outer document containing one sandboxed
/// srcdoc. No allow-same-origin, native JS handler or Host credential is added.
String sandboxedHtmlDocument(String content, {required bool interactive}) {
  final escaped = const HtmlEscape(HtmlEscapeMode.attribute).convert(content);
  final sandbox = interactive ? 'allow-scripts' : '';
  return '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}iframe{width:100%;height:100%;border:0;display:block}</style></head><body><iframe sandbox="$sandbox" srcdoc="$escaped"></iframe></body></html>';
}
