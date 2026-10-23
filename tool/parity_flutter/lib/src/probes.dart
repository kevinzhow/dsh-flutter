import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

String hexColor(Color? c) {
  if (c == null) return '';
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final a = argb >> 24;
  return a == 0xFF
      ? '#$rgb'
      : '#$rgb${a.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

/// Text style probes of the paragraphs under [context] (same shape as the React provider's
/// `typography`, so the report can show both).
List<Map<String, dynamic>> typographyProbes(BuildContext? context) {
  final out = <Map<String, dynamic>>[];
  final root = context?.findRenderObject();
  if (root == null) return out;
  void visit(RenderObject node) {
    if (out.length >= 24) return;
    if (node is RenderParagraph) {
      final span = node.text;
      final text = span.toPlainText().trim();
      final style = span.style;
      if (text.isNotEmpty && style != null) {
        final size = style.fontSize ?? 14;
        out.add({
          'selector': 'RenderParagraph[${out.length}]',
          'text': text.length > 60 ? '${text.substring(0, 60)}...' : text,
          'fontFamily': [
            if (style.fontFamily != null) style.fontFamily,
            ...?style.fontFamilyFallback,
          ].join(', '),
          'fontSize': size,
          'fontWeight': (style.fontWeight ?? FontWeight.w400).value,
          'lineHeight': style.height == null
              ? null
              : double.parse((style.height! * size).toStringAsFixed(2)),
          'letterSpacing': style.letterSpacing ?? 0,
          'color': hexColor(style.color),
        });
      }
    }
    node.visitChildren(visit);
  }

  visit(root);
  return out;
}

/// Fill / border / radius probes of decorated boxes under [context].
List<Map<String, dynamic>> styleTokenProbes(BuildContext? context) {
  final out = <Map<String, dynamic>>[];
  final root = context?.findRenderObject();
  if (root == null) return out;
  void visit(RenderObject node) {
    if (out.length >= 16) return;
    if (node is RenderDecoratedBox && node.decoration is BoxDecoration) {
      final d = node.decoration as BoxDecoration;
      final border = d.border;
      final side = border is Border ? border.top : null;
      if (d.color != null || (side != null && side.width > 0)) {
        out.add({
          'selector': 'RenderDecoratedBox[${out.length}]',
          'size':
              '${node.size.width.toStringAsFixed(1)}x${node.size.height.toStringAsFixed(1)}',
          if (d.color != null) 'backgroundColor': hexColor(d.color),
          if (side != null && side.width > 0) ...{
            'borderColor': hexColor(side.color),
            'borderWidth': side.width,
          },
          if (d.borderRadius != null) 'borderRadius': d.borderRadius.toString(),
        });
      }
    }
    node.visitChildren(visit);
  }

  visit(root);
  return out;
}
