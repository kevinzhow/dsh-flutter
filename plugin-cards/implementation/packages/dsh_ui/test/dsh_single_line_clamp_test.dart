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
    expect(find.text('Alpha bet\u2026'), findsOneWidget);
    await t.pumpWidget(host(text, 200));
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('CSS normal whitespace collapses before line wrapping', (
    t,
  ) async {
    const text = 'Alpha  beta\tgamma\ndelta';
    await t.pumpWidget(host(text, 115));
    expect(find.text('Alpha beta\u2026'), findsOneWidget);
    expect(t.widget<Text>(find.byType(Text)).semanticsLabel, text);
    await t.pumpWidget(host(text, 400));
    expect(find.text('Alpha beta gamma delta'), findsOneWidget);
  });

  testWidgets('one unbreakable run clips without inventing an ellipsis', (
    t,
  ) async {
    const text = 'abcdefghijklmnopqrstuvwxyz';
    await t.pumpWidget(host(text, 45));
    expect(find.text(text), findsOneWidget);
    expect(t.widget<Text>(find.byType(Text)).softWrap, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('collapsed whitespace has no line box; NBSP retains one', (
    t,
  ) async {
    await t.pumpWidget(host(' \t\n ', 100));
    expect(t.getSize(find.byType(DshSingleLineClamp)).height, 0);
    await t.pumpWidget(host('\u00a0', 100));
    expect(find.text('\u00a0'), findsOneWidget);
    expect(t.getSize(find.byType(DshSingleLineClamp)).height, greaterThan(0));
  });

  testWidgets('oversized first word with a later line is ellipsized', (
    t,
  ) async {
    await t.pumpWidget(host('abcdefghijk tail', 45));
    expect(find.text('abc\u2026'), findsOneWidget);
  });

  testWidgets('ellipsis may shorten the existing accented word', (t) async {
    await t.pumpWidget(host('Alpha éclair résumé', 125));
    expect(find.text('Alpha éclai\u2026'), findsOneWidget);
  });

  testWidgets('CJK, emoji and narrow constraints stay bounded', (t) async {
    for (final text in ['你好世界你好世界', '👩‍💻👩‍💻👩‍💻']) {
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
