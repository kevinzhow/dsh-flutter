import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(String text, double width) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Ahem', fontSize: 10),
      child: Center(
        child: SizedBox(
          width: width,
          child: DshSingleLineClamp(text, style: const TextStyle()),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('wraps Latin words and retains full accessible description', (
    t,
  ) async {
    const text = 'Alpha beta gamma';
    await t.pumpWidget(host(text, 115));
    expect(find.text('Alpha beta\u2026'), findsOneWidget);
    expect(t.widget<Text>(find.byType(Text)).semanticsLabel, text);
    await t.pumpWidget(host(text, 100));
    expect(find.text('Alpha\u2026'), findsOneWidget);
    await t.pumpWidget(host(text, 200));
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('unbroken words, CJK and narrow constraints stay bounded', (
    t,
  ) async {
    for (final text in ['abcdefghijk', '你好世界你好世界', '👩‍💻👩‍💻👩‍💻']) {
      await t.pumpWidget(host(text, 45));
      final visible = t.widget<Text>(find.byType(Text)).data!;
      expect(visible.endsWith('\u2026'), isTrue);
      expect(visible.endsWith('\u200d\u2026'), isFalse);
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(host('Alpha beta', 1));
    expect(t.takeException(), isNull);
  });
}
