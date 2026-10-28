import 'dart:convert';
import 'dart:io';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    var root = Directory.current.absolute;
    while (!File('${root.path}/tool/parity-fonts/manifest.json').existsSync()) {
      if (root.parent.path == root.path) {
        throw StateError('Pinned fonts missing');
      }
      root = root.parent;
    }
    final manifest = jsonDecode(
      File('${root.path}/tool/parity-fonts/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final family in manifest['families'] as List) {
      for (final name in family['names'] as List) {
        final loader = FontLoader(name as String);
        for (final face in family['faces'] as List) {
          final bytes = File('${root.path}/tool/parity-fonts/${face['file']}')
              .readAsBytesSync();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
        }
        await loader.load();
      }
    }
  });

  const whitespace = <String, (String, String)>{
    'en': (
      '  Synthetic   spaces\tand\nline breaks with\u00a0a non-breaking space.  ',
      'Synthetic spaces and line breaks with\u00a0a non-breaking space.',
    ),
    'zh': ('  合成   空格\t与\n换行以及\u00a0不换行空格。  ', '合成 空格 与 换行以及\u00a0不换行空格。'),
  };
  const token =
      'SyntheticUnbrokenToken_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  Future<void> mount(
    WidgetTester t,
    String text, {
    bool warning = false,
    Brightness brightness = Brightness.light,
  }) async {
    await t.pumpWidget(
      dshTestApp(
        DshToastHost(
          child: DshToast(
            text: text,
            icon: warning ? const DshIcon(DshIcons.warning) : null,
            onDone: () {},
          ),
        ),
        brightness: brightness,
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  for (final width in [800.0, 390.0]) {
    for (final density in [1.0, 2.625]) {
      for (final brightness in Brightness.values) {
        for (final entry in whitespace.entries) {
          testWidgets(
            'source normal whitespace ${entry.key}/$width/$density/$brightness',
            (t) async {
              t.view.physicalSize = Size(
                (width * density).ceilToDouble(),
                600 * density,
              );
              t.view.devicePixelRatio = density;
              addTearDown(t.view.reset);
              await mount(t, entry.value.$1, brightness: brightness);
              final chrome = t.widget<DshChromeText>(
                find.byType(DshChromeText),
              );
              expect(chrome.data, entry.value.$2);
              expect(chrome.semanticsLabel, entry.value.$1);
              expect(chrome.data, isNot(contains('\u2060')));
              final lines = width == 390 && entry.key == 'en' ? 2 : 1;
              expect(
                t.getSize(find.byType(DshChromeText)).height,
                DshToastRecipe.lineHeight * lines,
              );
              expect(
                t.widget<DshToast>(find.byType(DshToast)).text,
                entry.value.$1,
              );
              await t.pumpWidget(const SizedBox());
            },
          );
        }
        testWidgets(
          'source unbreakable token overflows one line $width/$density/$brightness',
          (t) async {
            t.view.physicalSize = Size(
              (width * density).ceilToDouble(),
              600 * density,
            );
            t.view.devicePixelRatio = density;
            addTearDown(t.view.reset);
            await mount(t, token, warning: true, brightness: brightness);
            final chrome = t.widget<DshChromeText>(find.byType(DshChromeText));
            expect(chrome.data, token);
            expect(chrome.semanticsLabel, token);
            expect(chrome.softWrap, false);
            expect(chrome.overflow, TextOverflow.visible);
            expect(
              t.getSize(find.byType(DshChromeText)).height,
              DshToastRecipe.lineHeight,
            );
            expect(
              t.getSize(find.byType(DshShadowBox)).height,
              DshToastRecipe.lineHeight + 2 * DshToastRecipe.verticalPadding,
            );
            final text = t.widget<Text>(find.text(token));
            final painter = TextPainter(
              text: TextSpan(text: text.data, style: text.style),
              textDirection: TextDirection.ltr,
            )..layout();
            expect(
              painter.width,
              greaterThan(t.getSize(find.byType(DshChromeText)).width),
            );
            painter.dispose();
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  for (final raw in ['', ' \t\n\r\f ']) {
    testWidgets(
      'source empty/collapsed text creates no line box ${jsonEncode(raw)}',
      (t) async {
        await mount(t, raw);
        expect(t.getSize(find.byType(DshChromeText)), Size.zero);
        expect(
          t.getSize(find.byType(DshShadowBox)).height,
          2 * DshToastRecipe.verticalPadding,
        );
        expect(
          t.widget<DshChromeText>(find.byType(DshChromeText)).semanticsLabel,
          raw,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  for (final raw in ['\u00a0', 'A\u00a0B', 'a\u2003b']) {
    testWidgets(
      'source non-collapsible whitespace remains ${jsonEncode(raw)}',
      (t) async {
        await mount(t, raw);
        expect(t.widget<DshChromeText>(find.byType(DshChromeText)).data, raw);
        expect(
          t.getSize(find.byType(DshChromeText)).height,
          DshToastRecipe.lineHeight,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'ordinary paragraph keeps real breaks without painted measurement markers',
    (t) async {
      const raw =
          'A natural multi-word paragraph with a non-breaking\u00a0space '
          'keeps ordinary source wrapping across a narrow viewport. '
          'No inserted joiner belongs to the displayed or accessible text.';
      t.view.physicalSize = const Size(390, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await mount(t, raw);
      final chrome = t.widget<DshChromeText>(find.byType(DshChromeText));
      expect(chrome.data, raw);
      expect(chrome.data, isNot(contains('\u2060')));
      expect(chrome.semanticsLabel, raw);
      expect(
        t.getSize(find.byType(DshChromeText)).height,
        greaterThan(DshToastRecipe.lineHeight),
      );
      expect(chrome.maxLines, isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('NBSP joins oversized words while Chinese keeps normal breaks', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const joined = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ\u00a0ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    await mount(t, joined);
    expect(t.widget<DshChromeText>(find.byType(DshChromeText)).data, joined);
    expect(
      t.getSize(find.byType(DshChromeText)).height,
      DshToastRecipe.lineHeight,
    );
    await t.pumpWidget(const SizedBox());
    final chinese = List.filled(20, '这是一条故意加长的合成提示。').join();
    await mount(t, chinese);
    final chrome = t.widget<DshChromeText>(find.byType(DshChromeText));
    expect(chrome.data, chinese);
    expect(chrome.data, isNot(contains('\u2060')));
    expect(chrome.softWrap, isNot(false));
    expect(
      t.getSize(find.byType(DshChromeText)).height,
      greaterThan(DshToastRecipe.lineHeight),
    );
    await t.pumpWidget(const SizedBox());
  });
}
