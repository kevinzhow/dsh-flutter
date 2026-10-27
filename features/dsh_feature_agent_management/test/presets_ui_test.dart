import 'dart:ui' show SemanticsRole;

import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'settings groups preserve custom names, coding gate and broken composition reader',
    (tester) async {
      final semantics = tester.ensureSemantics();
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
      final currentTag = find.widgetWithText(
        DshTag,
        i18n.t('settings.agentPreset', 'inUse'),
      );
      final customTag = find.widgetWithText(
        DshTag,
        i18n.t('settings.agentPreset', 'customGroup'),
      );
      expect(currentTag, findsOneWidget);
      expect(customTag, findsWidgets);
      expect(tester.widget<DshTag>(currentTag).tone, DshTagTone.solid);
      expect(
        tester
            .widgetList<DshTag>(customTag)
            .every((tag) => tag.tone == DshTagTone.outline),
        isTrue,
      );
      expect(find.text('Custom Named'), findsOneWidget);
      expect(find.text('ptc'), findsNothing);
      expect(find.text('Broken preset'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.text(i18n.t('settings.agentPreset', 'modeExplanation')).first,
      );
      await tester.pumpAndSettle();
      final guideTabs = find.byType(DshSegmentedTabs);
      expect(guideTabs, findsOneWidget);
      final explanation = tester
          .getSemantics(
            find.byKey(const ValueKey('preset-guide-tab-explanation')),
          )
          .getSemanticsData();
      expect(explanation.controlsNodes, {'preset-guide-panel-explanation'});
      expect(explanation.role, SemanticsRole.tab);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier ==
                  'preset-guide-panel-explanation' &&
              widget.properties.role == SemanticsRole.tabPanel,
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<DshSegmentedTabs>(guideTabs).label,
        i18n.t('settings.agentPreset', 'guideSections'),
      );
      final focusedTab = tester
          .widgetList<FocusableActionDetector>(
            find.descendant(
              of: guideTabs,
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .singleWhere((item) => item.focusNode?.hasFocus == true);
      expect(focusedTab.focusNode!.skipTraversal, isFalse);
      expect(
        tester.widget<DshMarkdown>(find.byType(DshMarkdown)).data,
        i18n.t('settings.agentPreset', 'guideStandardExplanation'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == 'preset-guide-panel-usage' &&
              widget.properties.role == SemanticsRole.tabPanel,
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<DshMarkdown>(find.byType(DshMarkdown)).data,
        i18n.t('settings.agentPreset', 'guideStandardUsage'),
      );
      await tester.tap(find.text(i18n.t('settings.agentPreset', 'close')));
      await tester.pumpAndSettle();
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
      semantics.dispose();
    },
  );
}
