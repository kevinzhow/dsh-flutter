import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'toast_main.dart';

void main() {
  setUpAll(loadPinnedFontsFromEnvironment);
  testWidgets(
    'actual Settings upload notice is reachable before its default deadline',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
      final semantics = t.ensureSemantics();
      final key = GlobalKey<ToastNativeState>();
      await t.pumpWidget(
        ToastNativeApp(key: key, brightness: Brightness.light),
      );
      Future<void> flush([Duration elapsed = Duration.zero]) async {
        await t.pump();
        await t.pump();
        await t.pump(elapsed);
        await t.pump();
      }

      await flush();
      await t.runAsync(() => key.currentState!.saveUpload(true));
      await flush(const Duration(milliseconds: 200));
      List<SemanticsNode> alerts(DebugSemanticsDumpOrder order) {
        final result = <SemanticsNode>[];
        void visit(SemanticsNode node) {
          if (node.getSemanticsData().role == SemanticsRole.alert) {
            result.add(node);
          }
          for (final child in node.debugListChildrenInOrder(order)) {
            visit(child);
          }
        }

        visit(
          t
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        return result;
      }

      for (final order in DebugSemanticsDumpOrder.values) {
        expect(alerts(order), hasLength(1));
        expect(
          alerts(order).single.getSemanticsData().label,
          'Preference saved',
        );
        expect(
          alerts(order).single.rect.size,
          t.getSize(find.byType(DshShadowBox)),
        );
      }
      expect(find.text('Preference saved'), findsOneWidget);
      await flush(const Duration(milliseconds: 3799));
      expect(alerts(DebugSemanticsDumpOrder.traversalOrder), hasLength(1));
      await flush(const Duration(milliseconds: 1));
      expect(alerts(DebugSemanticsDumpOrder.traversalOrder), isEmpty);
      await t.pumpWidget(const SizedBox());
      await flush();
      semantics.dispose();
    },
  );
}
