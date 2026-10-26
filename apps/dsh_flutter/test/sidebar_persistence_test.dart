import 'dart:async';
import 'dart:convert';

import 'package:dsh_flutter/src/local_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'parity/helpers/models_settings_fixture.dart';

class HeldPrefs extends MemoryLocalPrefs {
  final first = Completer<void>();
  final writes = <String>[];
  @override
  Future<void> setSidebarLayouts(String json) async {
    writes.add(json);
    if (writes.length == 1) await first.future;
    await super.setSidebarLayouts(json);
  }
}

void main() {
  test(
    'production root restores the original task binding only on its Host',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final prefs = MemoryLocalPrefs();
      final firstBackend = FakeBackend();
      SyntheticModelSettings(firstBackend.host, welcome: false);
      final first = makeController(firstBackend, prefs: prefs);
      expect(await first.pair('http://host:18686/?token=synthetic'), isTrue);
      final original = first.sidebar.stateFor('viewing-session');
      original.openTab(
        'scheduleTask',
        params: {'id': 'synthetic-task', 'sessionId': 'original-session'},
      );
      original.setExpanded(true);
      original.setFullscreen(true);
      await Future<void>.delayed(Duration.zero);
      first.dispose();
      await Future<void>.delayed(Duration.zero);
      final nextBackend = FakeBackend();
      SyntheticModelSettings(nextBackend.host, welcome: false);
      final next = makeController(nextBackend, prefs: prefs);
      expect(await next.pair('http://host:18686/?token=synthetic'), isTrue);
      final restored = next.sidebar.stateFor('viewing-session');
      expect(restored.fullscreen, isTrue);
      expect(restored.expanded, isTrue);
      expect(
        restored.tabs.singleWhere((t) => t.kind == 'scheduleTask').params,
        {'id': 'synthetic-task', 'sessionId': 'original-session'},
      );
      expect(
        await next.pair('http://other-host:18686/?token=synthetic'),
        isTrue,
      );
      expect(next.sidebar.stateFor('viewing-session').tabs, isEmpty);
      next.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'host and original Session scopes survive restart without key collisions',
    () async {
      final prefs = MemoryLocalPrefs();
      final first = PrefsSidebarPersistence(prefs);
      first.write('http://synthetic-a:123', 'same-session', 'a');
      first.write('http://synthetic-b:123', 'same-session', 'b');
      first.write('http://synthetic-a:123', 'different-session', 'c');
      await first.flush();
      final restarted = PrefsSidebarPersistence(prefs);
      expect(restarted.read('http://synthetic-a:123', 'same-session'), 'a');
      expect(restarted.read('http://synthetic-b:123', 'same-session'), 'b');
      expect(
        restarted.read('http://synthetic-a:123', 'different-session'),
        'c',
      );
    },
  );
  test('a slow storage write cannot overwrite a newer committed snapshot', () async {
    final prefs = HeldPrefs();
    // Use the same adapter and storage instance throughout the ordered writes.
    final ordered = PrefsSidebarPersistence(prefs);
    ordered.write('host', 'session', 'old');
    await Future<void>.delayed(Duration.zero);
    ordered.write('host', 'session', 'new');
    expect(prefs.writes, hasLength(1));
    prefs.first.complete();
    await ordered.flush();
    expect(prefs.writes, hasLength(2));
    expect(PrefsSidebarPersistence(prefs).read('host', 'session'), 'new');
  });
  test(
    'untrusted device JSON and oversized snapshots do not grow storage',
    () async {
      final prefs = MemoryLocalPrefs(sidebarLayouts: '{broken');
      final storage = PrefsSidebarPersistence(prefs);
      for (var i = 0; i < 70; i++) {
        storage.write('host', 'session-$i', 'synthetic');
      }
      storage.write('host', 'oversized', 'x' * (512 * 1024 + 1));
      await storage.flush();
      expect((jsonDecode(prefs.sidebarLayouts!) as Map).length, 64);
      expect(storage.read('host', 'session-0'), isNull);
      expect(storage.read('host', 'oversized'), isNull);
      expect(storage.read('host', 'session-69'), 'synthetic');
    },
  );
  test('oversized legacy preference maps are bounded during recovery', () {
    final prefs = MemoryLocalPrefs(
      sidebarLayouts: jsonEncode({
        for (var i = 0; i < 70; i++)
          jsonEncode(['host', 'session-$i']): 'synthetic',
      }),
    );
    final storage = PrefsSidebarPersistence(prefs);
    expect(storage.read('host', 'session-0'), isNull);
    expect(storage.read('host', 'session-69'), 'synthetic');
  });
}
