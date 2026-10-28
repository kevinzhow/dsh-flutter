import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const i18n = DshI18n(DshLocale.en);

  group('formatting', () {
    test('tokens are compact', () {
      expect(formatTokens(517, i18n), '517');
      expect(formatTokens(12200, i18n), '12.2K');
      expect(formatTokens(13000, i18n), '13K');
      expect(formatTokens(517000, i18n), '517K');
      expect(formatTokens(1200000, i18n), '1.2M');
    });

    test('exact counts group digits', () {
      expect(formatExactTokens(0, i18n), '0');
      expect(formatExactTokens(1234567, i18n), '1,234,567');
    });

    test('a partial hit never rounds up to 100', () {
      expect(formatCacheHitPercent(0, 0), isNull);
      expect(formatCacheHitPercent(0, 1000), '0');
      expect(formatCacheHitPercent(500, 1000), '50');
      expect(formatCacheHitPercent(1000, 1000), '100');
      expect(formatCacheHitPercent(996, 1000), '99.6');
      expect(formatCacheHitPercent(9996, 10000), '99.96');
    });

    test('durations name seconds or minutes', () {
      expect(formatDuration(45200, i18n), '45.2s');
      expect(formatDuration(162000, i18n), '2m42s');
    });
  });

  group('the pills', () {
    late SessionOwner owner;

    Future<void> pump(WidgetTester t, {Map<String, Object?>? values}) async {
      t.view.physicalSize = const Size(800, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      owner = testSessionOwner('s1');
      for (final e in (values ?? const <String, Object?>{}).entries) {
        owner.session.projections.apply(e.key, e.value, 1);
      }
      await t.pumpWidget(
        dshTestApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatsPill(owner: owner, i18n: i18n, activity: true),
                const SizedBox(width: 12),
                StatsPill(owner: owner, i18n: i18n, activity: false),
              ],
            ),
          ),
          size: const Size(800, 400),
        ),
      );
      await t.pumpAndSettle();
    }

    const stats = {
      'turns': 5,
      'steps': 9,
      'llmMs': 12000,
      'toolMs': 2500,
      'ttftMs': 900,
      'ttftSteps': 3,
      'decodeMs': 10000,
      'decodeTokens': 420,
    };
    const usage = {
      'uncachedInputTokens': 9000,
      'cacheReadTokens': 0,
      'cacheWriteTokens': 0,
      'outputTokens': 4000,
    };

    testWidgets('nothing before the log has steps or billing', (t) async {
      await pump(t);
      expect(find.byKey(const ValueKey('stat-activity')), findsNothing);
      expect(find.byKey(const ValueKey('stat-usage')), findsNothing);
    });

    testWidgets('counts with speed, and tokens with the cache hit', (t) async {
      await pump(t, values: {'sessionStats': stats, 'tokenUsage': usage});
      expect(
        find.textContaining('5 turns 9 steps', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('42 tok/s', findRichText: true), findsWidgets);
      expect(find.textContaining('13K tok', findRichText: true), findsWidgets);
      expect(
        find.textContaining('Cache hit 0%', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('the activity pill opens its time and speed dialog', (t) async {
      await pump(t, values: {'sessionStats': stats});
      await t.tap(find.byKey(const ValueKey('stat-activity')));
      await t.pumpAndSettle();
      expect(find.text('Session statistics'), findsOneWidget);
      expect(find.text('LLM time'), findsOneWidget);
      expect(find.text('12s'), findsOneWidget);
      expect(find.text('Tool time'), findsOneWidget);
      expect(find.text('2.5s'), findsOneWidget);
      expect(find.text('Avg time to first token (TTFT)'), findsOneWidget);
      expect(find.text('300ms'), findsNothing);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(find.text('Session statistics'), findsNothing);
    });

    testWidgets('the usage pill lists every billing bucket', (t) async {
      await pump(t, values: {'tokenUsage': usage});
      await t.tap(find.byKey(const ValueKey('stat-usage')));
      await t.pumpAndSettle();
      expect(find.text('Token usage'), findsOneWidget);
      expect(find.text('13,000 tok'), findsOneWidget);
      expect(find.text('9,000 tok'), findsOneWidget);
      expect(find.text('Cache write'), findsNothing, reason: 'none written');
      expect(find.text('Output'), findsOneWidget);
    });

    testWidgets('one click switches the open statistics panel', (t) async {
      await pump(t, values: {'sessionStats': stats, 'tokenUsage': usage});
      await t.tap(find.byKey(const ValueKey('stat-activity')));
      await t.pumpAndSettle();
      expect(find.text('Session statistics'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('stat-usage')));
      await t.pumpAndSettle();
      expect(find.text('Session statistics'), findsNothing);
      expect(find.text('Token usage'), findsOneWidget);
      expect(find.byType(DshStatPanel), findsOneWidget);
    });

    testWidgets('keyboard opens the trigger and Escape retains its focus', (
      t,
    ) async {
      await pump(t, values: {'sessionStats': stats});
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final triggerFocus = FocusManager.instance.primaryFocus;
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Session statistics'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(triggerFocus));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Session statistics'), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(triggerFocus));
    });

    testWidgets('an open panel follows the durable projection update', (
      t,
    ) async {
      await pump(t, values: {'sessionStats': stats});
      await t.tap(find.byKey(const ValueKey('stat-activity')));
      await t.pumpAndSettle();
      expect(find.text('12s'), findsOneWidget);
      owner.session.projections.apply('sessionStats', {
        ...stats,
        'llmMs': 18000,
      }, 2);
      await t.pumpAndSettle();
      expect(find.text('12s'), findsNothing);
      expect(find.text('18s'), findsOneWidget);
    });

    testWidgets(
      'published panel fits a narrow viewport and filters its backdrop',
      (t) async {
        t.view.physicalSize = const Size(280, 360);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final pill = activityPill(
          const SessionStats(
            turns: 231,
            steps: 2901,
            llmMs: 37673000,
            toolMs: 9394000,
            ttftMs: 95000,
            ttftSteps: 10,
            decodeMs: 10000,
            decodeTokens: 1460,
          ),
          i18n,
        )!;
        await t.pumpWidget(
          dshTestApp(
            Align(
              alignment: Alignment.bottomRight,
              child: StatPillView(pill: pill),
            ),
            size: const Size(280, 360),
          ),
        );
        await t.tap(find.byType(StatPillView));
        await t.pumpAndSettle();
        final rect = t.getRect(find.byKey(const ValueKey('stats-panel')));
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(rect.right, lessThanOrEqualTo(268));
        expect(
          rect.width,
          256,
          reason: '300px floor yields to viewport minus 24px',
        );
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  });
}
