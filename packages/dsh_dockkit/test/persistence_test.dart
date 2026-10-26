import 'dart:convert';
import 'dart:io';

import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restoration decisions match the actual pinned TypeScript validator',
    () {
      final fixture = jsonDecode(
        File('test/fixtures/sidebar_layouts.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final cases = fixture['cases'] as List<dynamic>,
          expected =
              (fixture['expected'] as Map<String, dynamic>)['accepted']
                  as List<dynamic>;
      for (var i = 0; i < cases.length; i++) {
        final row = cases[i] as Map<String, dynamic>;
        expect(
          SavedDockLayout.tryRead(row['value']) != null,
          expected[i],
          reason: row['name'] as String,
        );
      }
    },
  );
  test(
    'split and floating layout restore without history or identity collisions',
    () {
      final dock = DockController();
      final first = dock.openContent(
        const OpenContentInput(
          contentId: 'synthetic://one',
          kind: 'text',
          title: 'One',
        ),
      );
      dock.setExpanded(true);
      expect(dock.splitPane(), isTrue);
      dock.openContent(
        const OpenContentInput(
          contentId: 'synthetic://two',
          kind: 'text',
          title: 'Two',
        ),
      );
      dock.floatTab(first, const FloatRect(10, 20, 320, 240));
      final saved = SavedDockLayout.tryRead(
        jsonDecode(jsonEncode(dock.savedLayout.toJson())),
      )!;
      expect(saved.layout, dock.snapshot.state);
      final restored = DockController(DockControllerOptions(restored: saved));
      expect(restored.snapshot.canUndo, isFalse);
      expect(restored.snapshot.canRedo, isFalse);
      final newTab = restored.openContent(
        const OpenContentInput(
          contentId: 'synthetic://three',
          kind: 'text',
          title: 'Three',
        ),
      );
      expect(saved.layout.tabs.containsKey(newTab), isFalse);
      expect(restored.savedLayout.minted, greaterThan(saved.minted));
    },
  );

  test(
    'invalid references, allocations, dimensions and split shapes are refused',
    () {
      final dock = DockController();
      final tab = dock.openContent(
        const OpenContentInput(
          contentId: 'synthetic://one',
          kind: 'text',
          title: 'One',
        ),
      );
      dock.setExpanded(true);
      dock.splitPane();
      Map<String, dynamic> snapshot() =>
          jsonDecode(jsonEncode(dock.savedLayout.toJson()))
              as Map<String, dynamic>;
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (s) => s['minted'] = 0,
        (s) => s['layout']['activePaneId'] = 'pane999',
        (s) => s['layout']['tabs'][tab]['id'] = 'tab999',
        (s) => s['layout']['nodes'][s['layout']['rootId']]['children'] = [
          s['layout']['rootId'],
          s['layout']['rootId'],
        ],
        (s) => s['layout']['nodes'][s['layout']['rootId']]['sizes'] = [.2, .2],
        (s) => s['layout']['nodes'][s['layout']['rootId']]['axis'] = 'column',
      ]) {
        final value = snapshot();
        mutate(value);
        expect(SavedDockLayout.tryRead(value), isNull);
      }
    },
  );
}
