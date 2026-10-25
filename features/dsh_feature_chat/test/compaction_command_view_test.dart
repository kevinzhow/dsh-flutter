import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);
const marker = CompactionData(
  seq: 3,
  time: 10003,
  summary: '## Summary\n\nRemember **this**.',
  shadowedItemCount: 2,
  shadowedTokenCount: 125,
);
Widget app(Widget child, {double width = 480}) => dshTestApp(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: child),
  ),
);

void main() {
  testWidgets(
    'only a loaded summary expands, with localized structured counts',
    (t) async {
      await t.pumpWidget(app(const CompactionView(data: marker, i18n: en)));
      expect(find.byType(DshMarkdown), findsNothing);
      expect(
        find.text(
          en.t(
            'chat',
            'message.compaction.completed',
            params: {'items': 2, 'tokens': 125},
          ),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('compaction-header')));
      await t.pump();
      expect(find.byType(DshMarkdown), findsOneWidget);
      expect(
        t.widget<DshMarkdown>(find.byType(DshMarkdown)).data,
        marker.summary,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable checkpoint is disabled and never shows an envelope',
    (t) async {
      await t.pumpWidget(
        app(
          const CompactionView(data: CompactionData(seq: 3, time: 3), i18n: en),
        ),
      );
      expect(
        find.text(en.t('chat', 'message.compaction.unavailable')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('compaction-header')));
      await t.pump();
      expect(find.byType(DshMarkdown), findsNothing);
    },
  );

  testWidgets('keyboard opens and closes without pointer hover', (t) async {
    await t.pumpWidget(app(const CompactionView(data: marker, i18n: en)));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(find.byType(DshMarkdown), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.byType(DshMarkdown), findsNothing);
  });

  testWidgets(
    'sticky header stays clickable and is pushed out at the row end',
    (t) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final text = List.generate(60, (i) => 'Paragraph $i.').join('\n\n');
      final viewport = GlobalKey(), row = GlobalKey();
      await t.pumpWidget(
        app(
          SizedBox(
            key: viewport,
            height: 240,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 100),
                  CompactionView(
                    key: row,
                    data: CompactionData(seq: 3, time: 3, summary: text),
                    i18n: en,
                  ),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('compaction-header')));
      await t.pump();
      final rowHeight = t.getSize(find.byKey(row)).height;
      expect(rowHeight, greaterThan(240));
      controller.jumpTo(200);
      await t.pump();
      final top = t.getTopLeft(find.byKey(viewport)).dy;
      expect(
        t.getTopLeft(find.byKey(const ValueKey('compaction-header'))).dy,
        closeTo(top, .01),
      );
      controller.jumpTo(100 + rowHeight - 10);
      await t.pump();
      expect(
        t.getBottomLeft(find.byKey(const ValueKey('compaction-header'))).dy,
        lessThan(top + 12),
      );
      controller.jumpTo(200);
      await t.pump();
      await t.tapAt(t.getTopLeft(find.byKey(viewport)) + const Offset(150, 12));
      await t.pump();
      expect(find.byType(DshMarkdown), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'manual failure keeps full literal output, not Markdown or a false marker',
    (t) async {
      const text = 'First line\n<tag> **literal**';
      const data = ManualCompactionData(
        CommandData(
          seq: 1,
          time: 1,
          commandId: 'c',
          name: 'compact',
          outcome: CommandOutcome(kind: 'error', text: text),
        ),
        null,
      );
      await t.pumpWidget(app(const ManualCompactionView(data: data, i18n: en)));
      expect(find.byType(CompactionView), findsNothing);
      await t.tap(find.text('compact'));
      await t.pump();
      expect(find.byType(DshMarkdown), findsNothing);
      expect(find.text(text), findsNWidgets(2));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    },
  );

  testWidgets('running manual command settles into the landed marker once', (
    t,
  ) async {
    const command = CommandData(
      seq: 1,
      time: 1,
      commandId: 'c',
      name: 'compact',
    );
    await t.pumpWidget(
      app(
        const ManualCompactionView(
          data: ManualCompactionData(command, null),
          i18n: en,
        ),
      ),
    );
    expect(find.text(en.t('chat', 'message.compaction.running')), findsWidgets);
    await t.pumpWidget(
      app(
        const ManualCompactionView(
          data: ManualCompactionData(command, marker),
          i18n: en,
        ),
      ),
    );
    expect(find.byType(CommandView), findsNothing);
    expect(find.byType(CompactionView), findsOneWidget);
    await t.tap(find.text('compact'));
    await t.pump();
    expect(find.byType(DshMarkdown), findsOneWidget);
  });

  testWidgets(
    'single-line and empty settlements stay unexpandable at phone width',
    (t) async {
      for (final text in ['Complete', '']) {
        await t.pumpWidget(
          app(
            CommandView(
              data: CommandData(
                seq: 1,
                time: 1,
                commandId: 'c',
                outcome: CommandOutcome(kind: 'success', text: text),
              ),
              i18n: en,
            ),
            width: 240,
          ),
        );
        await t.tap(find.text(en.t('chat', 'command.title')));
        await t.pump();
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'command-name slot overrides ordinary commands and keeps generic fallback',
    (t) async {
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      final owner = testSessionOwner('fixture');
      addTearDown(owner.conversation.dispose);
      registerChatFeature(slots, i18n: () => en);
      final slot = DshSlots.conversationChatCommandview
          .typed<CommandViewOwner, Widget>();
      slots.register(
        slot,
        (o) => Text('Specialized ${o.command.name}'),
        key: 'status',
      );
      owner.session.eventSource.replace([
        EventEntry({
          'seq': 1,
          'time': 1,
          'type': 'command/run',
          'data': {'commandId': 'c', 'name': 'status'},
        }),
      ], false);
      final snap = owner.conversation.chat.value,
          node = snap.visibleNodes.single;
      final view = slots.renderKeyed(
        chatNodeSlot,
        node.kind,
        ChatNodeOwner(session: owner, node: node, snapshot: snap),
      );
      await t.pumpWidget(app(view!));
      expect(find.text('Specialized status'), findsOneWidget);
      owner.session.eventSource.replace([
        EventEntry({
          'seq': 2,
          'time': 2,
          'type': 'command/run',
          'data': {'commandId': 'other', 'name': 'unregistered'},
        }),
      ], false);
      final fallbackSnapshot = owner.conversation.chat.value;
      final fallbackNode = fallbackSnapshot.visibleNodes.single;
      final fallback = slots.renderKeyed(
        chatNodeSlot,
        fallbackNode.kind,
        ChatNodeOwner(
          session: owner,
          node: fallbackNode,
          snapshot: fallbackSnapshot,
        ),
      );
      await t.pumpWidget(app(fallback!));
      expect(find.byType(CommandView), findsOneWidget);
      expect(find.text('unregistered'), findsWidgets);
    },
  );
}
