import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';

class Services implements SidebarServices {
  @override
  final navigatorKey = GlobalKey<NavigatorState>();
  @override
  LayoutController? get layout => null;
  @override
  ShortcutService? get shortcuts => null;
}

class Storage implements SidebarPersistence {
  final values = <String, String>{};
  @override
  String? read(String scope, String session) => values['$scope/$session'];
  @override
  void write(String scope, String session, String value) {
    values['$scope/$session'] = value;
  }
}

void main() {
  test(
    'live and restored states stay isolated when Hosts reuse a Session id',
    () {
      final slots = SlotRegistry();
      for (final slot in DshSlots.all) {
        slots.declare(slot);
      }
      final storage = Storage();
      var host = 'first-host';
      final feature = registerSidebarRightFeature(
        slots,
        i18n: () => const DshI18n(DshLocale.en),
        services: Services(),
        persistence: storage,
        scope: () => host,
      );
      final first = feature.stateFor('same-session');
      first.openTab('files');
      first.setExpanded(true);
      host = 'second-host';
      final second = feature.stateFor('same-session');
      expect(second, isNot(same(first)));
      expect(second.tabs, isEmpty);
      second.openTab('files');
      second.setFullscreen(true);
      // A late first-Host event retains its captured storage scope.
      first.setFullscreen(false);
      feature.reset();
      expect(feature.stateFor('same-session').fullscreen, isTrue);
      host = 'first-host';
      expect(feature.stateFor('same-session').fullscreen, isFalse);
      expect(feature.stateFor('same-session').expanded, isTrue);
      feature.reset();
      feature.dispose();
    },
  );
  test(
    'task binding survives duplicate, original close, split and restart',
    () {
      final types = SidebarTabTypes()
        ..register(
          SidebarTabType(
            kind: 'scheduleTask',
            restorable: true,
            persistParams: (p) => p['id'] is String && p['sessionId'] is String
                ? {'id': p['id'], 'sessionId': p['sessionId']}
                : null,
          ),
        );
      String? saved;
      final first = SidebarState(
        'viewing-session',
        types: types,
        persist: (value) => saved = value,
      );
      first.openTab(
        'scheduleTask',
        params: {
          'id': 'synthetic-task',
          'sessionId': 'original-session',
          'transient': 'not persisted',
        },
      );
      final original = first.tabs.singleWhere((t) => t.kind == 'scheduleTask');
      final duplicate = first.dock.duplicateTab(TabId(original.id));
      first.close(original.id);
      first.dock.splitPane();
      first.setExpanded(true);
      final expected = first.layout;
      first.dispose();
      final restored = SidebarState(
        'viewing-session',
        types: types,
        restored: saved,
      );
      expect(restored.layout, expected);
      expect(restored.dock.snapshot.canUndo, isFalse);
      expect(restored.tabs.singleWhere((t) => t.id == duplicate).params, {
        'id': 'synthetic-task',
        'sessionId': 'original-session',
      });
      restored.openTab(
        'scheduleTask',
        params: {'id': 'second-task', 'sessionId': 'original-session'},
      );
      expect(
        restored.tabs.singleWhere((t) => t.kind == 'scheduleTask').params['id'],
        'second-task',
      );
      restored.dispose();
    },
  );
  test(
    'restart never recreates terminal work and corrupt state starts empty',
    () {
      final types = SidebarTabTypes()
        ..register(const SidebarTabType(kind: 'terminal', multiple: true));
      String? saved;
      final first = SidebarState(
        'session',
        types: types,
        persist: (value) => saved = value,
      );
      first.openTab('terminal', params: {'shellPath': '/synthetic/shell'});
      first.setExpanded(true);
      first.dispose();
      final restored = SidebarState('session', types: types, restored: saved);
      expect(restored.tabs.where((t) => t.kind == 'terminal'), isEmpty);
      expect(restored.tabs.every((tab) => tab.kind == 'guide'), isTrue);
      restored.dispose();
      final corrupt = SidebarState(
        'session',
        types: types,
        restored: '{"version":1,"surface":{}}',
      );
      expect(corrupt.tabs, isEmpty);
      corrupt.dispose();
    },
  );
}
