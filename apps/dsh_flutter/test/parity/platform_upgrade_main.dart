// Device-only fixture: actual SharedPreferences, secure connection store and
// sidebar persistence across adb install -r. All stored values are synthetic.
import 'dart:async';

import 'package:dsh_flutter/src/connection_store.dart';
import 'package:dsh_flutter/src/local_prefs.dart';
import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/material.dart';

const stage = String.fromEnvironment('UPGRADE_STAGE', defaultValue: 'before');
const origin = 'https://synthetic.invalid';
const sessionId = 'synthetic-session';
SidebarTabTypes types() => SidebarTabTypes()
  ..register(
    SidebarTabType(
      kind: 'scheduleTask',
      restorable: true,
      persistParams: (p) => p['id'] is String && p['sessionId'] is String
          ? {'id': p['id'], 'sessionId': p['sessionId']}
          : null,
    ),
  );
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: SafeArea(child: UpgradeFixture())),
    ),
  );
}

class UpgradeFixture extends StatefulWidget {
  const UpgradeFixture({super.key});
  @override
  State<UpgradeFixture> createState() => _UpgradeFixtureState();
}

class _UpgradeFixtureState extends State<UpgradeFixture> {
  String status = 'Reading synthetic state';
  Map<String, bool> checks = {};
  @override
  void initState() {
    super.initState();
    unawaited(read());
  }

  Future<void> read() async {
    final prefs = await SharedLocalPrefs.load(),
        secret = await SecureConnectionStore().load();
    final storage = PrefsSidebarPersistence(prefs);
    final sidebar = SidebarState(
      sessionId,
      types: types(),
      restored: storage.read(origin, sessionId),
    );
    final task = sidebar.tabs
        .where((t) => t.kind == 'scheduleTask')
        .firstOrNull;
    final next = <String, bool>{
      'locale': prefs.locale == 'zh',
      'notifications': !prefs.notificationsEnabled,
      'secure-origin': secret?.origin == origin,
      'secure-token': secret?.token == 'synthetic-upgrade-sentinel',
      'sidebar-expanded': sidebar.expanded,
      'sidebar-fullscreen': sidebar.fullscreen,
      'original-task-binding':
          task?.params['sessionId'] == 'synthetic-original' &&
          task?.params['id'] == 'synthetic-task',
      'host-isolation':
          storage.read('https://other.synthetic.invalid', sessionId) == null,
    };
    sidebar.dispose();
    if (mounted)
      setState(() {
        checks = next;
        status = next.values.every((ok) => ok)
            ? 'All 8 persisted checks passed'
            : 'Synthetic state not seeded';
      });
  }

  Future<void> seed() async {
    final prefs = await SharedLocalPrefs.load();
    await prefs.setLocale('zh');
    await prefs.setNotificationsEnabled(false);
    await SecureConnectionStore().save(
      const SavedHost(origin, 'synthetic-upgrade-sentinel'),
    );
    final storage = PrefsSidebarPersistence(prefs);
    final sidebar = SidebarState(
      sessionId,
      types: types(),
      persist: (value) => storage.write(origin, sessionId, value),
    );
    sidebar.openTab(
      'scheduleTask',
      params: {'id': 'synthetic-task', 'sessionId': 'synthetic-original'},
    );
    sidebar.setExpanded(true);
    sidebar.setFullscreen(true);
    await storage.flush();
    sidebar.dispose();
    await read();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text('Whalee synthetic upgrade'),
      Text('Stage: $stage'),
      Text(status),
      for (final entry in checks.entries)
        Text('${entry.key}: ${entry.value ? 'PASS' : 'missing'}'),
      if (stage == 'before')
        ElevatedButton(
          onPressed: () => unawaited(seed()),
          child: const Text('Write synthetic upgrade state'),
        ),
    ],
  );
}
