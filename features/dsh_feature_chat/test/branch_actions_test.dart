import 'dart:async';

import 'package:dsh_feature_chat/src/stream/message_actions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'branch is keyboard accessible and remains visible when focused',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var calls = 0;
      await t.pumpWidget(
        dshTestApp(
          MessageActions(
            text: 'Synthetic',
            i18n: const DshI18n(DshLocale.en),
            revealed: false,
            onBranch: () async {
              calls++;
            },
          ),
        ),
      );
      // The detector owns its Focus internally, retrieve the mounted node.
      Focus.of(t.element(find.byKey(const ValueKey('message-branch'))))
          .requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(calls, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(
        t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'branch action blocks duplicate admission and non-final boundaries',
    (t) async {
      final gate = Completer<void>();
      var calls = 0;
      Widget view(bool unavailable) => dshTestApp(
        MessageActions(
          text: 'Synthetic',
          i18n: const DshI18n(DshLocale.en),
          clockFirst: false,
          branchUnavailable: unavailable,
          onBranch: () {
            calls++;
            return calls == 1 ? gate.future : Future.value();
          },
        ),
      );
      await t.pumpWidget(view(true));
      await t.tap(find.byKey(const ValueKey('message-branch')));
      await t.pump();
      expect(calls, 0);
      await t.pumpWidget(view(false));
      await t.tap(find.byKey(const ValueKey('message-branch')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('message-branch')));
      await t.pump();
      expect(calls, 1);
      gate.completeError(StateError('Synthetic refusal'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('message-branch')));
      await t.pump();
      expect(calls, 2);
      expect(t.takeException(), isNull);
    },
  );
}
