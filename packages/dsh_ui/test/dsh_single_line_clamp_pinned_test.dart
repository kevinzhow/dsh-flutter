import 'dart:io';

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    var root = Directory.current.absolute;
    const relative = 'tool/parity-fonts/files/NotoSans-Regular.ttf';
    while (!File('${root.path}/$relative').existsSync()) {
      if (root.parent.path == root.path) {
        throw StateError('Pinned source font is missing');
      }
      root = root.parent;
    }
    final bytes = File('${root.path}/$relative').readAsBytesSync();
    final loader = FontLoader('SourceClampProbe')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  Widget host(String text, double width) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: DefaultTextStyle(
        style: const TextStyle(),
        child: Center(
          child: SizedBox(
            width: width,
            child: DshSingleLineClamp(
              text,
              style: const TextStyle(
                fontFamily: 'SourceClampProbe',
                fontSize: DshPluginCardRecipe.descriptionFontSize,
                height:
                    DshPluginCardRecipe.descriptionLineHeight /
                    DshPluginCardRecipe.descriptionFontSize,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('source Noto single run clips; adding a later word clamps', (
    t,
  ) async {
    const word = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    await t.pumpWidget(host(word, 100));
    expect(find.text(word), findsOneWidget);
    await t.pumpWidget(host('$word tail', 100));
    expect(find.text('abcdefghijklm\u2026'), findsOneWidget);
  });

  testWidgets('source Noto retains the original first line', (t) async {
    const text =
        'A deliberately long synthetic description that must retain the source single-line clamp while the title and tags wrap naturally.';
    await t.pumpWidget(host(text, 228));
    expect(find.text('A deliberately long synthetic\u2026'), findsOneWidget);
    expect(t.widget<Text>(find.byType(Text)).semanticsLabel, text);
  });

  testWidgets('source Noto shortens an existing accented word', (t) async {
    await t.pumpWidget(host('Alpha éclair résumé naïve', 76));
    expect(find.text('Alpha écla\u2026'), findsOneWidget);
  });
}
