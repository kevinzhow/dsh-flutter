import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const i18n = DshI18n(DshLocale.en);
MessageData contextData({
  String? form,
  Map<String, Object?> source = const {},
  List<Object?> content = const [],
}) => MessageData(
  kind: 'context',
  seq: 1,
  time: 1000,
  source: {'kind': 'fixture', ...source},
  content: content,
  form: form,
  producerRole: 'context',
  producerLabel: 'Fixture',
);
void main() {
  testWidgets(
    'malformed structured source falls back without losing text/block order',
    (tester) async {
      final data = contextData(
        form: 'catalog',
        source: {
          'entries': [
            {'name': 'good', 'description': 'readable'},
            {'name': 'bad'},
          ],
        },
        content: [
          {'type': 'text', 'text': 'Before'},
          {'type': 'text', 'text': ' joined'},
          {'type': 'future-kind', 'value': 'middle'},
          {'type': 'text', 'text': 'After'},
        ],
      );
      expect(resolvedContextForm(data), isNull);
      await tester.pumpWidget(
        dshTestApp(
          ContextInjectionView(data: data, i18n: i18n, initiallyOpen: true),
        ),
      );
      expect(find.byKey(const ValueKey('context-body-opaque')), findsOneWidget);
      expect(find.text('Before joined'), findsOneWidget);
      await tester.tap(
        find.bySemanticsLabel(i18n.t('chat', 'message.unknownBlock')),
      );
      await tester.pump();
      expect(find.textContaining('future-kind'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('After')).dy,
        greaterThan(tester.getTopLeft(find.textContaining('future-kind')).dy),
      );
      expect(
        find.text('form'),
        findsNothing,
      ); // Declaration is present only when recorded in source.
    },
  );
  testWidgets(
    'catalog caps rows and retains unknown blocks; empty replacement is real',
    (tester) async {
      final data = contextData(
        form: 'catalog',
        source: {
          'update': true,
          'entries': List.generate(
            201,
            (i) => {'name': 'skill-$i', 'description': 'Synthetic entry'},
          ),
        },
        content: [
          {'type': 'text', 'text': 'Replacement prose'},
          {'type': 'future', 'value': 'kept'},
        ],
      );
      expect(
        resolvedContextForm(
          contextData(form: 'catalog', source: {'entries': []}),
        ),
        'catalog',
      );
      await tester.pumpWidget(
        dshTestApp(
          ContextInjectionView(data: data, i18n: i18n, initiallyOpen: true),
        ),
      );
      expect(find.text('skill-199'), findsOneWidget);
      expect(find.text('skill-200'), findsNothing);
      expect(find.text('Replacement prose'), findsNothing);
      expect(tester.widget<DshJsonBlock>(find.byType(DshJsonBlock)).payload, {
        'type': 'future',
        'value': 'kept',
      });
      expect(
        tester
            .getSize(find.byKey(const ValueKey('context-body-catalog')))
            .height,
        lessThanOrEqualTo(141),
      );
    },
  );
  testWidgets(
    'tool changes single row stays closed; mixed row opens by keyboard',
    (tester) async {
      await tester.pumpWidget(
        dshTestApp(
          ContextInjectionView(
            data: contextData(
              content: [
                {'type': 'tool-addition', 'toolName': 'read'},
              ],
            ),
            i18n: i18n,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('context-body-opaque')), findsNothing);
      await tester.tap(find.textContaining('read'));
      await tester.pump();
      expect(find.byKey(const ValueKey('context-body-opaque')), findsNothing);
      await tester.pumpWidget(
        dshTestApp(
          ContextInjectionView(
            key: const ValueKey('mixed'),
            data: contextData(
              content: [
                {'type': 'tool-addition', 'toolName': 'read'},
                {'type': 'tool-removal', 'toolName': 'old'},
              ],
            ),
            i18n: i18n,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byKey(const ValueKey('context-body-opaque')), findsOneWidget);
      expect(find.textContaining('old'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('six forms validate every entry and keep absent/unknown declarations opaque', () {
    final cases = <String, Map<String, Object?>>{
      'instructions': {
        'changes': [
          {'path': 'AGENTS.md', 'action': 'set'},
        ],
      },
      'catalog': {'entries': []},
      'snapshot': {
        'sections': [
          {'name': 'State', 'text': ''},
        ],
      },
      'notice': {'summary': 'Ready'},
      'relay': {'senderSessionId': 'sender'},
      'recall': {
        'references': [
          {
            'label': 'Earlier',
            'retainedMessages': 1,
            'omittedMessages': 2,
            'truncated': true,
          },
        ],
      },
    };
    for (final e in cases.entries) {
      expect(
        resolvedContextForm(contextData(form: e.key, source: e.value)),
        e.key,
      );
    }
    expect(
      resolvedContextForm(contextData(form: 'notice', source: {'summary': ''})),
      isNull,
    );
    expect(resolvedContextForm(contextData(form: 'future')), isNull);
    expect(
      resolvedContextForm(
        contextData(
          form: 'instructions',
          source: {
            'changes': [
              {'path': 'ok', 'action': 'set'},
              {'path': 'bad', 'action': 'future'},
            ],
          },
        ),
      ),
      isNull,
    );
  });
}
