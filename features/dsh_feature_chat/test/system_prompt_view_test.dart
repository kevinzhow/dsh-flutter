import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(
  Widget child, {
  double width = 480,
  Brightness brightness = Brightness.light,
}) => dshTestApp(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: child),
  ),
  brightness: brightness,
);
const en = DshI18n(DshLocale.en);

void main() {
  testWidgets(
    'collapsed by default, expands literal text with original line breaks',
    (t) async {
      const text = 'You are helpful.\n<private> **literal** </private>';
      await t.pumpWidget(app(const SystemPromptView(text: text, i18n: en)));
      expect(find.text(text), findsNothing);
      await t.tap(find.text(en.t('chat', 'message.systemPrompt')));
      await t.pump();
      expect(find.text(text), findsOneWidget);
      expect(
        t.getSize(find.byKey(const ValueKey('system-prompt-body'))).height,
        54,
      );
    },
  );

  testWidgets('long prompts scroll inside the 141px body at a narrow width', (
    t,
  ) async {
    final text = List.generate(100, (i) => 'line $i').join('\n');
    await t.pumpWidget(
      app(
        SystemPromptView(text: text, i18n: en, initiallyOpen: true),
        width: 200,
      ),
    );
    expect(
      t.getSize(find.byKey(const ValueKey('system-prompt-body'))).height,
      141,
    );
    final state = t.state<ScrollableState>(find.byType(Scrollable));
    expect(state.position.maxScrollExtent, greaterThan(0));
    await t.drag(
      find.byKey(const ValueKey('system-prompt-body')),
      const Offset(0, -150),
    );
    await t.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
    expect(t.takeException(), isNull);
  });

  testWidgets('display truncation is localized and keeps the original length', (
    t,
  ) async {
    const zh = DshI18n(DshLocale.zh);
    final text = 'x' * 20003;
    final marker = zh.t(
      'chat',
      'json.truncated',
      params: {'total': text.length},
    );
    await t.pumpWidget(
      app(
        SystemPromptView(
          text: text,
          i18n: zh,
          update: true,
          initiallyOpen: true,
        ),
      ),
    );
    expect(
      find.text(zh.t('chat', 'message.systemPromptUpdate')),
      findsOneWidget,
    );
    expect(find.text('${'x' * 20000}\n$marker'), findsOneWidget);
    expect(find.text(text), findsNothing);
  });

  testWidgets('Enter and Space operate the focused disclosure', (t) async {
    await t.pumpWidget(
      app(const SystemPromptView(text: 'secret prompt', i18n: en)),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('secret prompt'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(find.text('secret prompt'), findsNothing);
  });

  testWidgets(
    'an updated card retains its disclosure state across locale/theme changes',
    (t) async {
      await t.pumpWidget(app(const SystemPromptView(text: 'first', i18n: en)));
      await t.tap(find.text(en.t('chat', 'message.systemPrompt')));
      await t.pump();
      const zh = DshI18n(DshLocale.zh);
      await t.pumpWidget(
        app(
          const SystemPromptView(text: 'second', i18n: zh, update: true),
          brightness: Brightness.dark,
        ),
      );
      await t.pump();
      expect(find.text('second'), findsOneWidget);
    },
  );

  testWidgets('plain prompt selection keeps the exact model-visible text', (
    t,
  ) async {
    String? selected;
    const text = 'First line\n第二行 <tags>';
    await t.pumpWidget(
      app(
        SelectionArea(
          onSelectionChanged: (v) => selected = v?.plainText,
          child: const SystemPromptView(
            text: text,
            i18n: en,
            initiallyOpen: true,
          ),
        ),
      ),
    );
    await t.pump();
    t.state<SelectableRegionState>(find.byType(SelectableRegion)).selectAll();
    await t.pump();
    expect(selected, contains(text));
  });
}
