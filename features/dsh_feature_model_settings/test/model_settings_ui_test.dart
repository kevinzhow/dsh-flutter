import 'dart:ui' show Tristate;

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_settings.dart';
import 'package:dsh_feature_model_settings/src/provider_editor.dart';
import 'package:dsh_feature_model_settings/src/welcome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeHost host;
  late ConfigForms forms;
  late ModelsSettingsStore store;
  setUp(() async {
    host = FakeHost();
    host.handlers['settings/describe'] = (_) => describeValue([view()]);
    host.handlers['llm/listProviders'] = (_) => [
      {'id': 'openai', 'name': 'OpenAI'},
    ];
    host.handlers['llm/listConfigurableProviders'] = (_) => [
      {
        'provider': 'openai',
        'displayName': 'OpenAI',
        'settingsNs': 'llm-pi-ai',
        'settingsPath': ['providers', 'openai'],
        'declared': false,
      },
    ];
    host.handlers['credentials/describe'] = (_) => {
      'OPENAI_API_KEY': {
        'configured': true,
        'writable': true,
        'source': 'file',
      },
    };
    forms = ConfigForms(host.remotes);
    store = ModelsSettingsStore(host.remotes, forms.mirror);
    await store.load();
  });
  tearDown(() async {
    await store.dispose();
    await forms.dispose();
    await host.close();
  });
  const i18n = DshI18n(DshLocale.en);
  Future<void> show(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
    });
    await t.pumpWidget(
      dshTestApp(
        SingleChildScrollView(child: child),
        size: const Size(900, 1600),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Key key) async {
    await t.pump();
    final f = find.byKey(key);
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'provider key starts blank; partial save shows failure then retries only key',
    (t) async {
      final semantics = t.ensureSemantics();
      var closed = false;
      var keyAttempts = 0;
      host.handlers['settings/mutate'] = (args) => view(
        revision: 8,
        user: {
          'providers': {
            'openai': {
              'apiKeyEnv': 'OPENAI_API_KEY',
              'baseURL': 'https://gateway.example/v1',
            },
          },
        },
      );
      host.handlers['credentials/set'] = (_) {
        if (++keyAttempts == 1) {
          throw RemoteException(
            'gateway/refused',
            'Synthetic key save refused',
          );
        }
        return null;
      };
      await show(
        t,
        ProviderEditor(
          store: store,
          namespace: forms.mirror.namespace('llm-pi-ai')!,
          provider: 'openai',
          displayName: 'OpenAI',
          path: const ['providers', 'openai'],
          i18n: i18n,
          onClose: (_) => closed = true,
        ),
      );
      final key = find.byKey(const ValueKey('provider-api-key'));
      expect(
        find
            .descendant(of: key, matching: find.byType(EditableText))
            .evaluate()
            .single
            .widget,
        isA<EditableText>().having((e) => e.controller.text, 'initial key', ''),
      );
      final literal = ['synthetic', '-ui'].join();
      await t.enterText(key, literal);
      await t.pump();
      final fieldSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.textField == true &&
            w.properties.label == 'API key',
      );
      expect(fieldSemantics, findsOneWidget);
      final node = t.getSemantics(fieldSemantics);
      expect(node.flagsCollection.isTextField, true);
      expect(node.flagsCollection.isObscured, true);
      expect(node.label, contains('API key'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.setText), true);

      await tap(t, const ValueKey('provider-key-reveal'));
      expect(
        t
            .getSemantics(find.byKey(const ValueKey('provider-key-reveal')))
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: key, matching: find.byType(EditableText)),
            )
            .obscureText,
        false,
      );
      await t.enterText(key, '$literal-changed');
      await t.pump();
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: key, matching: find.byType(EditableText)),
            )
            .obscureText,
        true,
      );
      await t.enterText(key, literal);

      await tap(t, const ValueKey('provider-customized'));
      await t.enterText(
        find.byKey(const ValueKey('provider-baseURL')),
        'https://gateway.example/v1',
      );
      await tap(t, const ValueKey('provider-save'));
      expect(find.text('Synthetic key save refused'), findsOneWidget);
      expect(closed, false);
      await tap(t, const ValueKey('provider-save'));
      expect(closed, true);
      expect(host.callsTo('settings/mutate'), hasLength(1));
      expect(host.callsTo('credentials/set'), hasLength(2));
      expect(host.callsTo('credentials/set').last.args, {
        'ref': 'OPENAI_API_KEY',
        'value': literal,
      });
      await t.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );
  testWidgets(
    'custom provider validates route/protocol/models and buffers incomplete capacity text',
    (t) async {
      var closed = false;
      host.handlers['settings/mutate'] = (args) {
        expect(args['expectedRevision'], 7);
        expect(args['ops'], [
          {
            'op': 'set',
            'path': ['providers', 'acme-gateway'],
            'value': {
              'api': 'openai-completions',
              'baseURL': 'https://api.example/v1',
              'models': [
                {'id': 'model-x', 'contextWindow': 256000},
              ],
            },
          },
        ]);
        return view(
          revision: 8,
          user: {
            'providers': {
              'acme-gateway': {
                'api': 'openai-completions',
                'baseURL': 'https://api.example/v1',
                'models': [
                  {'id': 'model-x', 'contextWindow': 256000},
                ],
              },
            },
          },
        );
      };
      await show(
        t,
        ProviderEditor(
          store: store,
          namespace: forms.mirror.namespace('llm-pi-ai')!,
          provider: '',
          displayName: 'Custom',
          path: const [],
          declared: true,
          creating: true,
          i18n: i18n,
          onClose: (_) => closed = true,
        ),
      );
      await t.enterText(find.byKey(const ValueKey('provider-route')), '9bad');
      await t.pump();
      expect(
        find.text(i18n.t('settings.models', 'customRouteInvalid')),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const ValueKey('provider-route')),
        'acme-gateway',
      );
      await t.enterText(
        find.byKey(const ValueKey('provider-baseURL')),
        'https://api.example/v1',
      );
      await tap(t, const ValueKey('add-provider-model'));
      await t.enterText(find.byKey(const ValueKey('model-0-id')), 'model-x');
      final capacity = find.byKey(const ValueKey('model-0-contextWindow'));
      await t.ensureVisible(capacity);
      await t.enterText(capacity, '2.');
      await t.pump();
      expect(
        find
            .descendant(of: capacity, matching: find.byType(EditableText))
            .evaluate()
            .single
            .widget,
        isA<EditableText>().having(
          (e) => e.controller.text,
          'kept draft',
          '2.',
        ),
      );
      expect(find.textContaining('Context window must be'), findsOneWidget);
      await t.enterText(capacity, '256K');
      await t.pump();
      await tap(t, const ValueKey('provider-save'));
      expect(closed, true);
      expect(host.callsTo('credentials/set'), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'discovery uses unsaved request and adopting preserves existing row metadata',
    (t) async {
      host.handlers['llm/discoverModels'] = (args) {
        expect(args['request'], {
          'provider': 'openai',
          'api': 'openai-completions',
          'apiKey': 'synthetic',
        });
        return [
          {
            'id': 'listed',
            'name': 'Listed',
            'inputModalities': ['text', 'image'],
          },
          {'id': 'extra', 'name': 'Extra'},
        ];
      };
      final namespace = SettingsNamespaceView.fromJson(
        view(
          user: {
            'providers': {
              'openai': {
                'api': 'openai-completions',
                'models': [
                  {'id': 'listed', 'opaque': true},
                ],
              },
            },
          },
        ),
      );
      await show(
        t,
        ProviderEditor(
          store: store,
          namespace: namespace,
          provider: 'openai',
          displayName: 'OpenAI',
          path: const ['providers', 'openai'],
          i18n: i18n,
          onClose: (_) {},
        ),
      );
      await t.enterText(
        find.byKey(const ValueKey('provider-api-key')),
        'synthetic',
      );
      await tap(t, const ValueKey('provider-customized'));
      await tap(t, const ValueKey('fetch-provider-models'));
      expect(host.callsTo('credentials/set'), isEmpty);
      expect(host.callsTo('settings/mutate'), isEmpty);
      await tap(t, const ValueKey('adopt-provider-models'));
      expect(find.text('extra'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'welcome only completes for exact accepted version and retries refusal',
    (t) async {
      final form = FakeConfigForm(
        const ConfigFormSnapshot(
          status: ConfigFormStatus.ready,
          writable: true,
          value: {'welcomeNoticeVersion': 'previous'},
          user: {'welcomeNoticeVersion': 'previous'},
          base: {},
          revision: 1,
        ),
      )..answer = false;
      var completed = 0;
      await t.pumpWidget(
        dshTestApp(
          WelcomeNotice(
            form: form,
            owner: SettingsOnboardingOwner(
              stepId: 'welcome',
              explicit: false,
              complete: () => completed++,
              openSection: (_) {},
            ),
            i18n: i18n,
          ),
          size: const Size(900, 1600),
        ),
      );
      await tap(t, const ValueKey('welcome-continue'));
      expect(completed, 0);
      expect(
        find.text(i18n.t('settings.models', 'welcomeError')),
        findsOneWidget,
      );
      form.answer = true;
      await tap(t, const ValueKey('welcome-continue'));
      expect(completed, 1);
      expect(
        (form.writes.last.ops.single as SetOp).value,
        welcomeNoticeVersion,
      );
      expect(find.byKey(const ValueKey('welcome-continue')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}

Map<String, Object?> schema() => {
  'uid': 9,
  'refs': {
    '1': {'type': 'string', 'meta': {}},
    '2': {'type': 'const', 'value': 'openai-completions', 'meta': {}},
    '3': {
      'type': 'union',
      'list': [2],
      'meta': {},
    },
    '4': {'type': 'any', 'meta': {}},
    '5': {
      'type': 'array',
      'inner': 4,
      'meta': {'default': []},
    },
    '6': {
      'type': 'object',
      'dict': {'api': 3, 'baseURL': 1, 'apiKeyEnv': 1, 'models': 5},
      'meta': {},
    },
    '8': {'type': 'dict', 'inner': 6, 'sKey': 1, 'meta': {}},
    '9': {
      'type': 'object',
      'dict': {'providers': 8},
      'meta': {},
    },
  },
};
Map<String, Object?> view({int revision = 7, Map<String, Object?>? user}) =>
    nsView(
      'llm-pi-ai',
      schema: schema(),
      value:
          user ??
          {
            'providers': {
              'openai': {'apiKeyEnv': 'OPENAI_API_KEY'},
            },
          },
      base: {'providers': {}},
      user:
          user ??
          {
            'providers': {
              'openai': {'apiKeyEnv': 'OPENAI_API_KEY'},
            },
          },
      revision: revision,
    );
