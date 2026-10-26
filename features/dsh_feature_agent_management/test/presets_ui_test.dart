import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'settings groups preserve custom names, coding gate and broken composition reader',
    (tester) async {
      final host = FakeHost();
      final settings = FakeConfigForm(
        const ConfigFormSnapshot(
          status: ConfigFormStatus.ready,
          writable: true,
          revision: 1,
          value: {'selectedDefault': 'standard'},
        ),
      );
      final tools = FakeConfigForm(
        const ConfigFormSnapshot(
          status: ConfigFormStatus.ready,
          writable: true,
          revision: 1,
          value: {'enabled': false},
        ),
      );
      host.handlers['agentPresets/list'] = (_) => {
        'presets': [
          {'id': 'standard', 'isDefault': true},
          {'id': 'ptc', 'isDefault': false},
          {'id': 'minimal', 'name': 'Custom Named', 'isDefault': false},
          {
            'id': 'broken',
            'name': 'Broken preset',
            'isDefault': false,
            'broken': 'missing dependency',
          },
        ],
      };
      host.handlers['agentPresets/read'] = (args) => {
        'agentPreset': args['agentPreset'],
        'content': '- plugin: example\n  enabled: false',
      };
      final model = AgentPresetsModel(
        remotes: host.remotes,
        settings: settings,
        tools: tools,
        currentSession: () => null,
      );
      const i18n = DshI18n(DshLocale.en);
      await tester.pumpWidget(
        dshTestApp(
          SingleChildScrollView(
            child: AgentPresetSection(model: model, i18n: i18n),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom Named'), findsOneWidget);
      expect(find.text('ptc'), findsNothing);
      expect(find.text('Broken preset'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final button = find.bySemanticsLabel(
        '${i18n.t('settings.agentPreset', 'view')}: Broken preset',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('- plugin: example\n  enabled: false'), findsOneWidget);
      expect(settings.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(i18n.t('settings.agentPreset', 'close')));
      await tester.pumpAndSettle();
      tools.publish(
        const ConfigFormSnapshot(
          status: ConfigFormStatus.ready,
          writable: true,
          revision: 2,
          value: {'enabled': true},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ptc'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await model.dispose();
        await host.close();
      });
    },
  );
}
