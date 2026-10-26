import 'dart:async';

import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'parity/helpers/models_settings_fixture.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets(
    'Creator lands cordis on a fresh session without switching the viewed running session',
    (t) async {
      t.view.physicalSize = const Size(1200, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      SyntheticModelSettings(backend.host, welcome: false);
      backend.host.handlers['agentPresets/list'] = (_) => {
        'presets': [
          {'id': 'standard', 'isDefault': true},
          {'id': 'cordis', 'isDefault': false},
        ],
      };
      backend.host.handlers['agentPresets/select'] = (args) =>
          args['agentPreset'];
      backend.host.handlers['schedule/catalog'] = (_) => <Object?>[];
      backend.host.handlers['skills/list'] = (_) => {'skills': <Object?>[]};
      backend.transport.onList = () async => {
        'items': [listRow('old', title: 'Existing work', cwd: '/work/demo')],
      };
      final gate = Completer<Map<String, Object?>>();
      backend.transport.onCreate = (_) => gate.future;
      final controller = makeController(backend);
      await t.pumpWidget(WhaleeApp(controller: controller));
      await t.runAsync(
        () => controller.pair('http://host:18686/?token=synthetic'),
      );
      backend.emitWorkspaces([
        {
          'workspaceId': 'ws',
          'path': '/work/demo',
          'title': 'Demo',
          'sessionIds': ['old'],
          'createdAt': '2026-10-01T00:00:00.000Z',
          'updatedAt': '2026-10-26T00:00:00.000Z',
        },
      ]);
      await settle(t);
      await controller.open('old');
      await settle(t);
      backend.transport.open(
        1,
        snapshot(const [], projections: {'agentPreset': 'standard'}),
      );
      await settle(t);
      controller.openSettings(section: 'agentPresets');
      await settle(t);
      final creator = find.text(
        controller.i18n.t('settings.agentPreset', 'creatorDraft'),
      );
      await t.ensureVisible(creator);
      await t.tap(creator);
      await settle(t);
      expect(backend.transport.createRequests.single, {
        'workspaceId': 'ws',
        'agentPreset': 'cordis',
      });
      expect(
        backend.host
            .callsTo('agentPresets/select')
            .where((c) => c.args['agentId'] == 'old'),
        isEmpty,
      );
      gate.complete({'sessionId': 'created'});
      await settle(t);
      backend.transport.open(
        1,
        snapshot(const [], projections: {'agentPreset': 'cordis'}),
      );
      await settle(t);
      expect(controller.openSessionId, 'created');
      expect(controller.agentPresets!.staged, isNull);
      expect(
        backend.host
            .callsTo('agentPresets/select')
            .where((c) => c.args['agentId'] == 'old'),
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      await t.runAsync(backend.host.close);
      expect(t.takeException(), isNull);
    },
  );
}
