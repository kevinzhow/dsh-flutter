import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_tool/dsh_feature_tool.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);
const zh = DshI18n(DshLocale.zh);

ToolResult settled({bool error = false, String text = 'a.txt\nb.txt'}) =>
    ToolResult(
      callId: 'c1',
      name: 'bash',
      args: PartialArguments.fromText('{"command":"ls -la"}'),
      subCalls: const [],
      seq: 9,
      time: 1,
      callArgsRaw: '{"command":"ls -la"}',
      content: [
        {'type': 'text', 'text': text},
      ],
      isError: error,
    );

void main() {
  group('formatting', () {
    test('tool keys follow dsh dictionary keys', () {
      expect(toolKeyOf('web_fetch'), 'webFetch');
      expect(toolKeyOf('bash'), 'bash');
      expect(toolKeyOf('read-image'), 'readImage');
    });

    test('titles come from the dsh catalog, else generic with the name', () {
      expect(toolTitle(en, 'bash'), 'Bash');
      expect(toolTitle(zh, 'bash'), '运行命令');
      expect(toolTitle(en, 'mystery'), 'Tool call · mystery');
    });

    test('the arguments summary picks the readable field, even partial', () {
      final args = PartialArguments()..append('{"command":"ls -la","time');
      expect(argsSummary(args), 'ls -la');
      final partial = PartialArguments()..append('{"path":"/tmp/some/fi');
      expect(argsSummary(partial), '/tmp/some/fi');
      expect(argsSummary(PartialArguments()), '');
    });

    test('partial JSON reads never throw', () {
      final a = PartialArguments()..append('{"a":1,"b":"x\\n');
      expect(a.keys(), ['a', 'b']);
      expect(a.complete('a'), isTrue);
      expect(a.complete('b'), isFalse);
      expect(a.text('b'), 'x\n');
      expect(a.value('a'), 1);
      expect(PartialArguments.fromText('not json').keys(), isEmpty);
    });

    test('pretty arguments and result previews', () {
      expect(argsPretty('{"a":1}'), '{\n  "a": 1\n}');
      expect(argsPretty('{"a'), '{"a');
      final p = previewLines('1\n2\n3\n4\n5');
      expect(p.text, '1\n2\n3');
      expect(p.cut, isTrue);
    });
  });

  group('card', () {
    Widget card(ToolCall call, {DshI18n i18n = en}) => dshTestApp(
      SingleChildScrollView(
        child: ToolCard(call: call, i18n: i18n),
      ),
    );

    testWidgets('a settled call shows title, summary, preview; expands', (
      t,
    ) async {
      await t.pumpWidget(card(settled()));
      expect(find.text('Bash'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-result-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-args')), findsNothing);
      await t.tap(find.text('Bash'));
      await t.pump();
      expect(find.byKey(const ValueKey('tool-args')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-result')), findsOneWidget);
    });

    testWidgets('a failed call is marked and shows the error label', (t) async {
      await t.pumpWidget(card(settled(error: true, text: 'boom')));
      expect(find.text('Failed'), findsOneWidget);
      await t.tap(find.text('Bash'));
      await t.pump();
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('a running call waits for its result (zh too)', (t) async {
      final started = StartedToolCall(
        callId: 'c2',
        name: 'bash',
        args: PartialArguments.fromText('{"command":"sleep 5"}'),
        argsRaw: '{"command":"sleep 5"}',
        turn: 1,
        step: 1,
        time: 1,
        subCalls: const [],
      );
      await t.pumpWidget(card(started, i18n: zh));
      expect(find.text('运行中'), findsOneWidget);
      await t.tap(find.text('运行命令'));
      await t.pump();
      expect(find.text('等待结果…'), findsOneWidget);
    });

    testWidgets('a preparing call shows its streamed arguments', (t) async {
      final preparing = PreparingToolCall(
        callId: 'c3',
        name: 'read',
        args: PartialArguments()..append('{"path":"/etc/ho'),
        subCalls: const [],
        turn: 1,
        step: 1,
        time: 1,
      );
      await t.pumpWidget(card(preparing));
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('/etc/ho'), findsOneWidget);
    });
  });

  testWidgets('registered node renders the card, a tool view overrides it', (
    t,
  ) async {
    final slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerToolFeature(slots, i18n: () => en);
    final owner = ChatNodeOwner(
      session: testSessionOwner('s'),
      node: ViewNode(
        key: 'k',
        kind: 'tool-call',
        id: 'c1',
        target: 'chat',
        anchorSeq: 1,
        location: const SessionLocation(),
        visible: true,
        data: ToolData(settled()),
      ),
      snapshot: ChatSnapshot.empty,
    );
    final w = slots.renderKeyed(chatNodeSlot, 'tool-call', owner)!;
    await t.pumpWidget(dshTestApp(w));
    expect(find.byType(ToolCard), findsOneWidget);

    slots.register<ToolViewOwner, Widget>(
      toolViewSlot,
      (o) => const Text('custom bash view'),
      key: 'bash',
    );
    await t.pumpWidget(
      dshTestApp(slots.renderKeyed(chatNodeSlot, 'tool-call', owner)!),
    );
    expect(find.text('custom bash view'), findsOneWidget);
    expect(find.byType(ToolCard), findsNothing);
  });
}
