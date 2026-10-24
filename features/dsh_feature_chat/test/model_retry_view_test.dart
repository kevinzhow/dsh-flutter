import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

ModelRetryAttempt attempt({
  int retry = 1,
  num seq = 3,
  int? maximum = 3,
  ModelRetryState state = ModelRetryState.scheduled,
  String code = 'RATE_LIMIT',
  String message = 'Try later',
}) => ModelRetryAttempt(
  seq: seq,
  time: 0,
  retryId: 'fixture',
  turn: 1,
  step: 1,
  retry: retry,
  maxRetries: maximum,
  state: state,
  delayMs: 2500,
  failureCode: code,
  failureMessage: message,
);

Widget app(Widget child, {double width = 700}) => dshTestApp(
  MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  const en = DshI18n(DshLocale.en);

  test('seconds round up and hold at one until the host starts the retry', () {
    expect(modelRetrySeconds(2500), 3);
    expect(modelRetrySeconds(1001), 2);
    expect(modelRetrySeconds(0), 1);
    expect(modelRetrySeconds(-1000), 1);
  });

  testWidgets('countdown uses the client clock and stops when started', (
    t,
  ) async {
    var now = DateTime.utc(2040);
    final a = attempt();
    Future<void> mount(ModelRetryAttempt value) => t.pumpWidget(
      app(ModelRetryView(attempt: value, i18n: en, now: () => now)),
    );
    await mount(a);
    expect(find.text('Retrying model request (1/3) · 3s'), findsOneWidget);
    now = now.add(const Duration(milliseconds: 1500));
    await t.pump(const Duration(milliseconds: 250));
    expect(find.text('Retrying model request (1/3) · 1s'), findsOneWidget);
    now = now.add(const Duration(days: 1));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Retrying model request (1/3) · 1s'), findsOneWidget);
    await mount(a.withState(ModelRetryState.started));
    expect(find.text('Retried model request (1/3) · 3s'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Retried model request (1/3) · 3s'), findsOneWidget);
  });

  testWidgets('a new attempt resets the deadline without closing its details', (
    t,
  ) async {
    var now = DateTime.utc(2040);
    await t.pumpWidget(
      app(ModelRetryView(attempt: attempt(), i18n: en, now: () => now)),
    );
    await t.tap(find.byKey(const ValueKey('model-retry-summary')));
    await t.pump();
    expect(find.textContaining('Try later'), findsOneWidget);
    now = now.add(const Duration(seconds: 10));
    await t.pump(const Duration(milliseconds: 250));
    await t.pumpWidget(
      app(
        ModelRetryView(
          attempt: attempt(seq: 8, retry: 2),
          i18n: en,
          now: () => now,
        ),
      ),
    );
    expect(find.text('Retrying model request (2/3) · 3s'), findsOneWidget);
    expect(find.textContaining('Try later'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });

  testWidgets('cancelled unlimited retries and failure details are localized', (
    t,
  ) async {
    const zh = DshI18n(DshLocale.zh);
    await t.pumpWidget(
      app(
        ModelRetryView(
          attempt: attempt(
            maximum: null,
            state: ModelRetryState.cancelled,
            code: 'AUTH',
            message: 'raw error',
          ),
          i18n: zh,
        ),
      ),
    );
    expect(find.textContaining('∞'), findsOneWidget);
    expect(find.textContaining('Try later'), findsNothing);
    await t.tap(find.byKey(const ValueKey('model-retry-summary')));
    await t.pump();
    expect(
      find.textContaining(zh.t('chat', 'message.failure.auth')),
      findsOneWidget,
    );
    expect(find.textContaining('raw error'), findsNothing);
    expect(find.textContaining('2500'), findsOneWidget);
  });

  testWidgets(
    'details can be opened with the keyboard and fit a narrow window',
    (t) async {
      await t.pumpWidget(
        app(
          ModelRetryView(
            attempt: attempt(
              state: ModelRetryState.started,
              message: 'a long provider failure ' * 8,
            ),
            i18n: en,
          ),
          width: 200,
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(find.textContaining('a long provider failure'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
