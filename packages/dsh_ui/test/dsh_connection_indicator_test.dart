import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DshThemeData official(Brightness b) => resolveTheme(
  officialPack,
  ThemeSettings(
    preference: b == Brightness.dark
        ? ThemePreference.dark
        : ThemePreference.light,
  ),
  Brightness.light,
);

Widget host(DshThemeData theme, Widget child, {bool animations = false}) =>
    MaterialApp(
      theme: ThemeData(extensions: [theme]),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

DshConnectionIndicator indicator(
  DshConnectionIndicatorState? state, {
  VoidCallback? onReconnect,
}) => DshConnectionIndicator(
  state: state,
  disconnectedLabel: 'Disconnected',
  connectingLabel: 'Reconnecting',
  recoveredLabel: 'Connected',
  reconnectActionLabel: 'Disconnected, reconnect now',
  restartActionLabel: 'Reconnecting, reconnect now',
  onReconnect: onReconnect ?? () {},
);

ShapeDecoration surface(WidgetTester t) =>
    t
            .widget<Container>(find.byKey(DshConnectionIndicator.surfaceKey))
            .decoration!
        as ShapeDecoration;

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    group('official ${brightness.name}', () {
      final theme = official(brightness);

      testWidgets('disconnected: warning colours, refresh icon, 28px tall', (
        t,
      ) async {
        await t.pumpWidget(
          host(theme, indicator(DshConnectionIndicatorState.disconnected)),
        );
        expect(find.text('Disconnected'), findsOneWidget);
        expect(
          surface(t).color,
          theme.color('--dsw-alias-state-warn-tertiary'),
        );
        expect(
          t.getSize(find.byKey(DshConnectionIndicator.surfaceKey)).height,
          28,
        );
        final label = t.widget<Text>(find.text('Disconnected'));
        expect(
          DefaultTextStyle.of(t.element(find.text('Disconnected'))).style.color,
          theme.color('--dsw-alias-state-warn-label'),
        );
        expect(label.softWrap, isFalse);
      });

      testWidgets('connecting: the label then three dots', (t) async {
        await t.pumpWidget(
          host(theme, indicator(DshConnectionIndicatorState.connecting)),
        );
        expect(find.text('Reconnecting'), findsOneWidget);
        expect(find.textContaining('...', findRichText: true), findsOneWidget);
      });

      testWidgets('recovered: success colours and no action', (t) async {
        var taps = 0;
        await t.pumpWidget(
          host(
            theme,
            indicator(
              DshConnectionIndicatorState.recovered,
              onReconnect: () => taps++,
            ),
          ),
        );
        expect(
          surface(t).color,
          theme.color('--dsw-alias-state-success-tertiary'),
        );
        await t.tap(find.text('Connected'));
        expect(taps, 0);
      });
    });
  }

  testWidgets('tapping the outage control asks for a reconnect', (t) async {
    var taps = 0;
    await t.pumpWidget(
      host(
        official(Brightness.light),
        indicator(
          DshConnectionIndicatorState.disconnected,
          onReconnect: () => taps++,
        ),
      ),
    );
    await t.tap(find.text('Disconnected'));
    expect(taps, 1);
  });

  testWidgets('accessible labels name the action', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      host(
        official(Brightness.light),
        indicator(DshConnectionIndicatorState.disconnected),
      ),
    );
    expect(
      find.bySemanticsLabel('Disconnected, reconnect now'),
      findsOneWidget,
    );
    await t.pumpWidget(
      host(
        official(Brightness.light),
        indicator(DshConnectionIndicatorState.connecting),
      ),
    );
    expect(
      find.bySemanticsLabel('Reconnecting, reconnect now'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('hover darkens the warning fill by a mix of the primary', (
    t,
  ) async {
    final theme = official(Brightness.light);
    await t.pumpWidget(
      host(theme, indicator(DshConnectionIndicatorState.disconnected)),
    );
    final base = surface(t).color;
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.text('Disconnected')));
    await t.pump();
    expect(surface(t).color, isNot(base));
  });

  testWidgets('state null fades out, then unmounts', (t) async {
    final theme = official(Brightness.light);
    await t.pumpWidget(
      host(
        theme,
        indicator(DshConnectionIndicatorState.disconnected),
        animations: true,
      ),
    );
    expect(find.text('Disconnected'), findsOneWidget);
    await t.pumpWidget(host(theme, indicator(null), animations: true));
    expect(find.text('Disconnected'), findsOneWidget);
    await t.pump(
      DshConnectionIndicator.exitDuration + const Duration(milliseconds: 10),
    );
    expect(find.text('Disconnected'), findsNothing);
  });

  testWidgets('without a state nothing is shown', (t) async {
    await t.pumpWidget(host(official(Brightness.light), indicator(null)));
    expect(find.byType(Text), findsNothing);
  });
}
