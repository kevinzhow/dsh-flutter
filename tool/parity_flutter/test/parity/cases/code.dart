// dsh's code surfaces (ui-primitives CodeBlock and ReadBlock) with DshCodeBlock and DshReadBlock, highlighted by the real
// DshSyntaxHighlighter (package dsh_highlight) over the grammars the app bundles, labelled from the real conversation
// dictionary. Props are the React host's (tool/parity-ext/build-code.py):
//   code.block  {layout, blocks: [{id, code, lang?, lineNumbers?, wrap?}]}
//   code.read   {layout, block: {label?, lang?, lines: [{number, text}], totalLines, maxLines?}}
import 'dart:async';
import 'dart:io';

import 'package:dsh_highlight/dsh_highlight.dart';
import 'package:dsh_highlight/dsh_highlight_io.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The highlighter the surfaces see. Its real counterpart is created and loaded in the real zone (a grammar read started
/// inside the widget test's fake-async zone would never complete), and the proxy tells the surfaces when it is ready.
class _ParityHighlighter implements DshCodeHighlighter {
  DshSyntaxHighlighter? real;
  final StreamController<void> _loaded = StreamController<void>.broadcast();

  @override
  List<List<DshCodeSpan>>? highlight(String code, String? lang) =>
      real?.highlight(code, lang);

  @override
  void prepare(String? lang) {}

  @override
  Stream<void> get loaded => _loaded.stream;
}

final _ParityHighlighter _shared = _ParityHighlighter();

/// Loads the grammars of [langs] (outside the fake clock) into the shared highlighter, then rebuilds the surfaces.
Future<void> _settleHighlight(
  WidgetTester tester,
  Iterable<String?> langs,
) async {
  final ids = {for (final lang in langs) DshSyntaxHighlighter.grammarOf(lang)}
      .whereType<String>();
  await tester.runAsync(() async {
    // tool/parity-fonts/manifest.json sits three levels below the repository root.
    final root = File(findParityFontsManifest()).parent.parent.parent.path;
    final real = _shared.real ??= DshSyntaxHighlighter(
      HighlightEngine(
        FileGrammarSource('$root/packages/dsh_highlight/assets/grammars'),
      ),
    );
    for (final id in ids) {
      await real.engine.load(id);
    }
    // The boot grammars (typescript, shell, json) start loading with the highlighter.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!real.engine.isLoaded('typescript')) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('boot grammars did not load');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  _shared._loaded.add(null);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

DshI18n _i18n(ParityContext ctx) => DshI18n(DshLocale.fromTag(ctx.locale));

String _c(DshI18n i18n, String key, [Map<String, Object?> params = const {}]) =>
    i18n.t('conversation', key, params: params);

DshCodeToolbarLabels _toolbar(DshI18n i18n) => DshCodeToolbarLabels(
  codeLabel: _c(i18n, 'codeBlock.title'),
  wrapLabel: _c(i18n, 'codeBlock.wrap'),
  unwrapLabel: _c(i18n, 'codeBlock.unwrap'),
  copy: _c(i18n, 'copy'),
  copied: _c(i18n, 'copied'),
);

final Map<String, ParityCase> codeCases = {
  'code.block': ParityCase(
    widgets: const ['dsh_ui:DshCodeBlock', 'dsh_ui:DshSyntaxHighlighter'],
    interact: (tester, ctx) => _settleHighlight(tester, [
      for (final b
          in (ctx.props['blocks'] as List).cast<Map<String, dynamic>>())
        b['lang'] as String?,
    ]),
    build: (ctx) {
      final i18n = _i18n(ctx);
      return DshCodeHighlighting(
        highlighter: _shared,
        child: ParityStack(
          layout: ctx.layout,
          children: [
            for (final b
                in (ctx.props['blocks'] as List).cast<Map<String, dynamic>>())
              DshCodeBlock(
                code: b['code'] as String,
                lang: b['lang'] as String?,
                lineNumbers: b['lineNumbers'] == true,
                wrap: b['wrap'] as bool?,
                labels: _toolbar(i18n),
              ),
          ],
        ),
      );
    },
  ),
  'code.read': ParityCase(
    widgets: const ['dsh_ui:DshReadBlock', 'dsh_ui:DshSyntaxHighlighter'],
    interact: (tester, ctx) => _settleHighlight(tester, [
      (ctx.props['block'] as Map<String, dynamic>)['lang'] as String?,
    ]),
    build: (ctx) {
      final i18n = _i18n(ctx);
      final b = (ctx.props['block'] as Map).cast<String, dynamic>();
      return DshCodeHighlighting(
        highlighter: _shared,
        child: ParityStack(
          layout: ctx.layout,
          children: [
            DshReadBlock(
              label: b['label'] as String?,
              lang: b['lang'] as String?,
              totalLines: (b['totalLines'] as num).toInt(),
              maxLines: (b['maxLines'] as num?)?.toInt() ?? defaultReadMaxLines,
              lines: [
                for (final l
                    in (b['lines'] as List).cast<Map<String, dynamic>>())
                  DshReadLine(
                    (l['number'] as num).toInt(),
                    l['text'] as String,
                  ),
              ],
              labels: DshReadLabels(
                toolbar: _toolbar(i18n),
                fold: DshFoldLabels(
                  collapse: _c(i18n, 'collapse'),
                  expand: (n) => _c(i18n, 'read.expandRest', {'count': n}),
                ),
                window: (shown, total) =>
                    _c(i18n, 'read.window', {'shown': shown, 'total': total}),
              ),
            ),
          ],
        ),
      );
    },
  ),
};
