import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_feature_model_selection/dsh_feature_model_selection.dart';
import 'package:dsh_feature_model_selection/testing.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> model(
  String id,
  String name, {
  List<String>? efforts,
  String? defaultEffort,
}) => {
  'id': id,
  'name': name,
  if (efforts != null)
    'reasoning': {
      'efforts': [
        for (final e in efforts)
          {'id': e, 'name': e[0].toUpperCase() + e.substring(1)},
      ],
      'defaultEffort': ?defaultEffort,
    },
};

Map<String, Object?> catalog({
  List<Map<String, Object?>>? groups,
  List<Map<String, Object?>> failures = const [],
  Map<String, Object?>? def,
}) => {
  'default': def ?? {'provider': 'deepseek-official', 'model': 'flash'},
  'routableProviders': ['deepseek-official'],
  'groups':
      groups ??
      [
        {
          'id': 'deepseek-official',
          'name': 'DeepSeek',
          'models': [
            model(
              'flash',
              'DeepSeek Flash',
              efforts: ['low', 'high'],
              defaultEffort: 'high',
            ),
            model('pro', 'DeepSeek Pro', efforts: ['high', 'max']),
          ],
        },
      ],
  'failures': failures,
};

Future<void> flush([int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeHost host;
  late FakeGeneration generation;
  late ModelCatalogDirectory directory;

  setUp(() {
    host = FakeHost();
    generation = FakeGeneration();
    host.generation = generation;
    host.handlers['session/modelCatalog'] = (_) => catalog();
    directory = ModelCatalogDirectory(host.remotes);
  });

  tearDown(() async {
    await directory.dispose();
    await host.close();
  });

  group('provider order', () {
    test('account and official first, the rest in catalog order', () {
      final out = orderModelProviders([
        'third',
        'deepseek-official',
        'other',
        'deepseek-account',
      ], (id) => id);
      expect(out, ['deepseek-account', 'deepseek-official', 'third', 'other']);
    });
  });

  group('catalog directory', () {
    test('loads once and shares the load', () async {
      final a = directory.load();
      final b = directory.load();
      await Future.wait([a, b]);
      expect(host.callsTo('session/modelCatalog'), hasLength(1));
      expect(directory.state.value.status, ModelCatalogStatus.ready);
      // Ready: no second read.
      await directory.load();
      expect(host.callsTo('session/modelCatalog'), hasLength(1));
    });

    test(
      'remembers the reasoning metadata of every model it has seen',
      () async {
        await directory.load();
        expect(
          directory.reasoningFor('deepseek-official', 'flash')?.defaultEffort,
          'high',
        );
        expect(
          directory.reasoningFor('deepseek-official', 'pro')?.defaultEffort,
          isNull,
        );
        expect(directory.reasoningFor('x', 'y'), isNull);
      },
    );

    test(
      'a failed load lands on the state and the next load retries',
      () async {
        var fail = true;
        host.handlers['session/modelCatalog'] = (_) {
          if (fail) throw RemoteException('gateway/internal', 'no adapters');
          return catalog();
        };
        await expectLater(directory.load(), throwsA(isA<RemoteException>()));
        expect(directory.state.value.status, ModelCatalogStatus.error);
        expect(directory.state.value.error, 'gateway/internal: no adapters');
        fail = false;
        await directory.load();
        expect(directory.state.value.status, ModelCatalogStatus.ready);
      },
    );

    test('a Host-side model input change reloads the catalog', () async {
      await directory.load();
      host.handlers['session/modelCatalog'] = (_) => catalog(
        groups: [
          {
            'id': 'deepseek-official',
            'name': 'DeepSeek',
            'models': [model('flash', 'DeepSeek Flash'), model('new', 'New')],
          },
        ],
      );
      host.emit('llm/adapters-updated');
      await flush();
      expect(
        [
          for (final m in directory.state.value.value!.groups.single.models)
            m.id,
        ],
        ['flash', 'new'],
      );
      host.emit('credentials/record-updated');
      host.emit('settings/document-updated');
      await flush();
      expect(
        host.callsTo('session/modelCatalog').length,
        greaterThanOrEqualTo(4),
      );
    });

    test('a new generation clears the old catalog and loads again', () async {
      await directory.load();
      final gate = Completer<void>();
      host.handlers['session/modelCatalog'] = (_) async {
        await gate.future;
        return catalog(def: {'provider': 'deepseek-official', 'model': 'pro'});
      };
      host.gens.add(FakeGeneration());
      expect(directory.state.value.value, isNull);
      expect(directory.reasoningFor('deepseek-official', 'flash'), isNull);
      gate.complete();
      await flush();
      expect(directory.state.value.value?.defaultSelection.model, 'pro');
    });
  });

  group('session directory', () {
    late ProjectionStore projections;
    late ModelDirectory dir;

    setUp(() {
      projections = ProjectionStore();
      dir = ModelDirectory(
        remotes: host.remotes,
        sessionId: 's1',
        catalog: directory,
        projections: projections,
      );
    });
    tearDown(() => dir.dispose());

    void project(Map<String, Object?>? next, [int seq = 1]) => projections
        .apply('modelSelection', {'lastUsed': null, 'next': next}, seq);

    test(
      'waits for the projection and the catalog, then resolves the default',
      () async {
        await dir.load();
        expect(dir.state.value.status, ModelDirectoryStatus.loading);
        project(null);
        expect(dir.state.value.status, ModelDirectoryStatus.ready);
        expect(dir.state.value.current?.model, 'flash');
        expect(dir.state.value.routable, isTrue);
        expect(dir.state.value.retainedEffort, 'High');
      },
    );

    test('the projection wins over the default and may be unroutable', () async {
      await dir.load();
      project({'provider': 'gone', 'model': 'old', 'reasoningEffort': 'max'});
      expect(dir.state.value.current?.provider, 'gone');
      expect(dir.state.value.routable, isFalse);
      // The saved effort is kept as its raw id when the model left the catalog.
      expect(dir.state.value.retainedEffort, 'max');
    });

    test(
      'select submits and waits for the projection frame to update',
      () async {
        host.handlers['session/selectModel'] = (args) => {
          'selected': {'provider': 'deepseek-official', 'model': 'pro'},
        };
        await dir.load();
        project(null);
        final result = await dir.select(
          const _Sel('deepseek-official', 'pro', 'max').wire,
        );
        expect(result.ok, isTrue);
        final call = host.callsTo('session/selectModel').single;
        expect(call.args['request'], {
          'sessionId': 's1',
          'provider': 'deepseek-official',
          'model': 'pro',
          'reasoningEffort': 'max',
        });
        // The answer does not move the current selection; the frame does.
        expect(dir.state.value.current?.model, 'flash');
        expect(dir.state.value.pending, isNull);
        project({
          'provider': 'deepseek-official',
          'model': 'pro',
          'reasoningEffort': 'max',
        }, 2);
        expect(dir.state.value.current?.model, 'pro');
      },
    );

    test('a refusal is reported and kept on the state', () async {
      host.handlers['session/selectModel'] = (_) =>
          throw RemoteException('session/writer-held', 'in use');
      await dir.load();
      project(null);
      final result = await dir.select(
        const _Sel('deepseek-official', 'pro', null).wire,
      );
      expect(result.ok, isFalse);
      expect(result.error?.code, 'session/writer-held');
      expect(dir.state.value.status, ModelDirectoryStatus.error);
      expect(dir.state.value.error, 'session/writer-held: in use');
    });

    test(
      'the pending selection shows while the request is in flight',
      () async {
        final gate = Completer<void>();
        host.handlers['session/selectModel'] = (_) async {
          await gate.future;
          return {
            'selected': {'provider': 'deepseek-official', 'model': 'pro'},
          };
        };
        await dir.load();
        project(null);
        final done = dir.select(
          const _Sel('deepseek-official', 'pro', null).wire,
        );
        await flush();
        expect(dir.state.value.status, ModelDirectoryStatus.selecting);
        expect(dir.state.value.pending?.model, 'pro');
        gate.complete();
        await done;
        expect(dir.state.value.status, ModelDirectoryStatus.ready);
      },
    );

    test('a stale answer never overwrites a newer selection', () async {
      final gates = [Completer<void>(), Completer<void>()];
      var n = 0;
      host.handlers['session/selectModel'] = (args) async {
        final mine = n++;
        await gates[mine].future;
        if (mine == 0) {
          throw RemoteException('session/error', 'first failed');
        }
        return {
          'selected': {'provider': 'deepseek-official', 'model': 'pro'},
        };
      };
      await dir.load();
      project(null);
      final first = dir.select(
        const _Sel('deepseek-official', 'flash', 'low').wire,
      );
      final second = dir.select(
        const _Sel('deepseek-official', 'pro', null).wire,
      );
      gates[1].complete();
      await second;
      gates[0].complete();
      final late = await first;
      // The first still reports its own refusal, but the state is the second's.
      expect(late.ok, isFalse);
      expect(dir.state.value.status, ModelDirectoryStatus.ready);
      expect(dir.state.value.error, isNull);
    });

    test('resetConnected drops a pending selection', () async {
      final gate = Completer<void>();
      host.handlers['session/selectModel'] = (_) async {
        await gate.future;
        return {
          'selected': {'provider': 'deepseek-official', 'model': 'pro'},
        };
      };
      await dir.load();
      project(null);
      final done = dir.select(
        const _Sel('deepseek-official', 'pro', null).wire,
      );
      await flush();
      dir.resetConnected();
      expect(dir.state.value.pending, isNull);
      // With the catalog and the projection in, the inputs resolve to ready.
      expect(dir.state.value.status, ModelDirectoryStatus.ready);
      gate.complete();
      await done;
      expect(dir.state.value.status, ModelDirectoryStatus.ready);
      expect(dir.state.value.pending, isNull);
    });

    test('a catalog error shows with the failed status', () async {
      host.handlers['session/modelCatalog'] = (_) =>
          throw RemoteException('gateway/internal', 'down');
      await directory.dispose();
      directory = ModelCatalogDirectory(host.remotes);
      await dir.dispose();
      dir = ModelDirectory(
        remotes: host.remotes,
        sessionId: 's1',
        catalog: directory,
        projections: projections,
      );
      await expectLater(dir.load(), throwsA(isA<RemoteException>()));
      expect(dir.state.value.status, ModelDirectoryStatus.error);
    });
  });

  group('seat', () {
    late SlotRegistry slots;
    late ModelSelectionFeature feature;
    late SessionOwner owner;
    var i18n = const DshI18n(DshLocale.en);

    setUp(() async {
      i18n = const DshI18n(DshLocale.en);
      await directory.dispose();
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      feature = registerModelSelectionFeature(
        slots,
        remotes: host.remotes,
        i18n: () => i18n,
      );
      owner = testSessionOwner('s1');
      directory = ModelCatalogDirectory(host.remotes);
    });
    tearDown(() => feature.dispose());

    Widget seat({Size size = const Size(390, 800)}) => dshTestApp(
      Align(
        alignment: Alignment.centerLeft,
        child: slots.renderSingle(
          DshSlots.conversationInputModel.typed<SessionOwner, Widget>(),
          owner,
        )!,
      ),
      size: size,
    );

    void project(Map<String, Object?>? next, [int seq = 1]) => owner
        .session
        .projections
        .apply('modelSelection', {'lastUsed': null, 'next': next}, seq);

    Future<void> ready(
      WidgetTester t, {
      Size size = const Size(390, 800),
    }) async {
      // The feature read the catalog when it registered; a test that changed
      // the handler since announces the change like the host would.
      host.emit('llm/adapters-updated');
      await t.pumpWidget(seat(size: size));
      await t.runAsync(() => flush(10));
      project(null);
      await t.pump();
    }

    testWidgets('the chip names the model and its effort', (t) async {
      await ready(t);
      expect(find.text('DeepSeek Flash'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Select model, current DeepSeek Flash, reasoning effort High',
        ),
        findsOneWidget,
      );
    });

    testWidgets('native accessibility selects model and effort from the chip', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      host.handlers['session/selectModel'] = (_) => {
        'selected': {'provider': 'deepseek-official', 'model': 'flash'},
      };
      await ready(t);
      Future<void> activate(Finder finder) async {
        final node = t.getSemantics(finder);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await t.pumpAndSettle();
      }

      Finder trigger() => find.bySemanticsLabel(
        'Select model, current DeepSeek Flash, reasoning effort High',
      );
      await activate(trigger());
      expect(find.byKey(const ValueKey('model-sheet')), findsOneWidget);
      await activate(find.byKey(const ValueKey('model-root-model')));
      await activate(
        find.byKey(const ValueKey('model-option-deepseek-official/pro')),
      );
      await t.runAsync(() => flush(8));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-sheet')), findsNothing);
      expect(host.callsTo('session/selectModel').single.args['request'], {
        'sessionId': 's1',
        'provider': 'deepseek-official',
        'model': 'pro',
      });
      await activate(trigger());
      await activate(find.byKey(const ValueKey('model-root-effort')));
      await activate(find.byKey(const ValueKey('effort-option-effort:low')));
      await t.runAsync(() => flush(8));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-sheet')), findsNothing);
      expect(host.callsTo('session/selectModel').last.args['request'], {
        'sessionId': 's1',
        'provider': 'deepseek-official',
        'model': 'flash',
        'reasoningEffort': 'low',
      });
      semantics.dispose();
    });

    testWidgets('a locked model chip has no native activation action', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      await ready(t);
      await t.pumpWidget(
        dshTestApp(
          Align(
            alignment: Alignment.centerLeft,
            child: ModelSeat(
              directory: feature.directoryFor(owner),
              i18n: i18n,
              locked: true,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final node = t.getSemantics(
        find.bySemanticsLabel(
          'Select model, current DeepSeek Flash, reasoning effort High',
        ),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-sheet')), findsNothing);
      expect(host.callsTo('session/selectModel'), isEmpty);
      semantics.dispose();
    });

    testWidgets('with no model resolved the chip invites a choice', (t) async {
      host.handlers['session/modelCatalog'] = (_) =>
          catalog(groups: const [], def: {'provider': 'x', 'model': 'y'});
      await ready(t);
      expect(find.text('Select model'), findsOneWidget);
    });

    testWidgets(
      'the source content-box menu root has two compact rows and no sheet title',
      (t) async {
        host.handlers['session/modelCatalog'] = (_) => catalog(
          groups: [
            {
              'id': 'deepseek-official',
              'name': 'DeepSeek',
              'models': [
                model('flash', 'Flash', efforts: ['low', 'high']),
              ],
            },
          ],
        );
        await ready(t);
        await t.tap(find.byKey(const ValueKey('model-chip')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('model-root-model')), findsOneWidget);
        expect(find.byKey(const ValueKey('model-root-effort')), findsOneWidget);
        expect(find.text('Model and reasoning effort'), findsNothing);
        expect(
          t.getSize(find.byKey(const ValueKey('model-sheet'))),
          const Size(248, 76),
        );
        expect(
          t.getSize(find.byKey(const ValueKey('model-root-model'))).height,
          34,
        );
      },
    );

    testWidgets('choosing a model submits it with its default effort', (
      t,
    ) async {
      host.handlers['session/selectModel'] = (_) => {
        'selected': {'provider': 'deepseek-official', 'model': 'pro'},
      };
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('model-root-model')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('model-group-deepseek-official')),
        findsOneWidget,
      );
      await t.tap(
        find.byKey(const ValueKey('model-option-deepseek-official/pro')),
      );
      await t.pump();
      await t.runAsync(() => flush(8));
      await t.pumpAndSettle();
      final call = host.callsTo('session/selectModel').single;
      expect(call.args['request'], {
        'sessionId': 's1',
        'provider': 'deepseek-official',
        'model': 'pro',
      });
      // Accepted: the sheet closes.
      expect(find.byKey(const ValueKey('model-sheet')), findsNothing);
    });

    testWidgets('the effort pane lists the model levels and submits one', (
      t,
    ) async {
      host.handlers['session/selectModel'] = (_) => {
        'selected': {'provider': 'deepseek-official', 'model': 'flash'},
      };
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('model-root-effort')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('effort-option-effort:low')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('effort-option-effort:high')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('effort-option-effort:low')));
      await t.pump();
      await t.runAsync(() => flush(8));
      await t.pumpAndSettle();
      expect(host.callsTo('session/selectModel').single.args['request'], {
        'sessionId': 's1',
        'provider': 'deepseek-official',
        'model': 'flash',
        'reasoningEffort': 'low',
      });
    });

    testWidgets('a rejected selection keeps the sheet open with the reason', (
      t,
    ) async {
      host.handlers['session/selectModel'] = (_) =>
          throw RemoteException('session/writer-held', 'busy');
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('model-root-model')));
      await t.pumpAndSettle();
      await t.tap(
        find.byKey(const ValueKey('model-option-deepseek-official/pro')),
      );
      await t.pump();
      await t.runAsync(() => flush(8));
      await t.pump();
      expect(find.byKey(const ValueKey('model-sheet')), findsOneWidget);
      expect(find.textContaining('already in use'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('search appears above four models and ranks by name', (
      t,
    ) async {
      host.handlers['session/modelCatalog'] = (_) => catalog(
        groups: [
          {
            'id': 'deepseek-account',
            'name': 'Account',
            'models': [model('a', 'Alpha'), model('b', 'Beta')],
          },
          {
            'id': 'third',
            'name': 'Third Party',
            'models': [
              model('c', 'Gamma'),
              model('d', 'Delta'),
              model('e', 'Epsilon'),
            ],
          },
        ],
        def: {'provider': 'third', 'model': 'c'},
      );
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('model-root-model')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-search')), findsOneWidget);
      // The account provider reads "DeepSeek Account" and comes first.
      expect(find.text('DeepSeek Account'), findsOneWidget);
      await t.enterText(find.byType(EditableText), 'ta');
      await t.pump();
      expect(
        find.byKey(const ValueKey('model-option-deepseek-account/b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('model-option-third/d')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('model-option-third/c')), findsNothing);
      await t.enterText(find.byType(EditableText), 'zzz');
      await t.pump();
      expect(find.text('No matching models.'), findsOneWidget);
    });

    testWidgets(
      'scrolling the model sheet pins the provider and selects a later group',
      (t) async {
        host.handlers['session/modelCatalog'] = (_) => catalog(
          groups: [
            for (final id in ['first', 'second'])
              {
                'id': id,
                'name': id == 'first' ? 'First provider' : 'Second provider',
                'models': [
                  for (var i = 0; i < 10; i++) model('$i', '$id model $i'),
                ],
              },
          ],
          def: {'provider': 'first', 'model': '0'},
        );
        host.handlers['session/selectModel'] = (_) => {
          'selected': {'provider': 'second', 'model': '5'},
        };
        await ready(t);
        await t.tap(find.byKey(const ValueKey('model-chip')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('model-root-model')));
        await t.pumpAndSettle();
        final list = find.byKey(const ValueKey('model-list'));
        final first = find.byKey(const ValueKey('model-group-first'));
        await t.drag(list, const Offset(0, -100));
        await t.pumpAndSettle();
        expect(t.getTopLeft(first).dy, t.getTopLeft(list).dy + 4);
        await t.drag(list, const Offset(0, -500));
        await t.pumpAndSettle();
        await t.ensureVisible(
          find.byKey(const ValueKey('model-option-second/5')),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('model-option-second/5')));
        await t.pump();
        await t.runAsync(() => flush(8));
        await t.pumpAndSettle();
        expect(host.callsTo('session/selectModel').single.args['request'], {
          'sessionId': 's1',
          'provider': 'second',
          'model': '5',
        });
      },
    );

    testWidgets('a provider that failed to load is listed with a retry', (
      t,
    ) async {
      host.handlers['session/modelCatalog'] = (_) => catalog(
        failures: [
          {'id': 'third', 'name': 'Third Party', 'message': 'timeout'},
        ],
      );
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('model-root-model')));
      await t.pumpAndSettle();
      expect(find.text('Third Party failed to load: timeout'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('model-retry')));
      await t.pump();
      await t.runAsync(() => flush(8));
      expect(
        host.callsTo('session/modelCatalog').length,
        greaterThanOrEqualTo(2),
      );
    });

    testWidgets('a model without reasoning levels has no Effort row', (
      t,
    ) async {
      host.handlers['session/modelCatalog'] = (_) => catalog(
        groups: [
          {
            'id': 'deepseek-official',
            'name': 'DeepSeek',
            'models': [model('flash', 'DeepSeek Flash')],
          },
        ],
      );
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-root-effort')), findsNothing);
      expect(find.text('High'), findsNothing);
    });

    testWidgets('Chinese copy comes from the generated dictionary', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      expect(find.text('模型与推理等级'), findsNothing);
      expect(find.text('模型'), findsOneWidget);
      expect(find.text('推理等级'), findsOneWidget);
    });

    testWidgets('desktop root stays above its trigger and dismisses outside', (
      t,
    ) async {
      host.handlers['session/modelCatalog'] = (_) => catalog(
        groups: [
          {
            'id': 'deepseek-official',
            'name': 'DeepSeek',
            'models': [
              model('flash', 'Flash', efforts: ['low', 'high']),
            ],
          },
        ],
      );
      t.view.physicalSize = const Size(1100, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await ready(t, size: const Size(1100, 800));
      final barrierCount = find.byType(ModalBarrier).evaluate().length;
      final trigger = find.byKey(const ValueKey('model-chip'));
      await t.tap(trigger);
      await t.pumpAndSettle();
      final menu = find.byKey(const ValueKey('model-sheet'));
      expect(t.getSize(menu), const Size(248, 76));
      expect(t.getBottomLeft(menu).dy, t.getTopLeft(trigger).dy - 8);
      expect(find.byType(ModalBarrier).evaluate().length, barrierCount);
      await t.tapAt(const Offset(1000, 760));
      await t.pumpAndSettle();
      expect(menu, findsNothing);
    });

    testWidgets('keyboard drills then Escape returns to root before closing', (
      t,
    ) async {
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-list')), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-root-model')), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-sheet')), findsNothing);
    });

    for (final spec in [
      (size: const Size(1100, 800), width: 428.0, height: 368.0),
      (size: const Size(390, 320), width: 366.0, height: 232.0),
    ]) {
      testWidgets('source content-box overflow bounds at ${spec.size}', (
        t,
      ) async {
        t.view.physicalSize = spec.size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        host.handlers['session/modelCatalog'] = (_) => catalog(
          groups: [
            {
              'id': 'deepseek-official',
              'name': 'DeepSeek',
              'models': [
                for (var i = 0; i < 24; i++)
                  model(
                    i == 0 ? 'flash' : 'model-$i',
                    '${List.filled(60, 'M').join()} $i',
                  ),
              ],
            },
          ],
        );
        await ready(t, size: spec.size);
        await t.tap(find.byKey(const ValueKey('model-chip')));
        await t.pumpAndSettle();
        final menu = find.byKey(const ValueKey('model-sheet'));
        // Published max-width420 and viewport−32 are CONTENT bounds. The
        // source's4px padding on each side sits outside those bounds.
        expect(t.getSize(menu).width, spec.width);
        expect(t.getSize(menu).height, 42);
        await t.tap(find.byKey(const ValueKey('model-root-model')));
        await t.pumpAndSettle();
        // Likewise max-height360 / viewport−96 cap the scrolling content,
        // while the card retains both4px outer padding strips.
        expect(t.getSize(menu), Size(spec.width, spec.height));
        final list = find.byKey(const ValueKey('model-list'));
        final scroll = t.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('content-box change preserves the three-row effort height', (
      t,
    ) async {
      host.handlers['session/modelCatalog'] = (_) => catalog(
        groups: [
          {
            'id': 'deepseek-official',
            'name': 'DeepSeek',
            'models': [
              model(
                'flash',
                'Flash',
                efforts: ['low', 'high', 'max'],
                defaultEffort: 'max',
              ),
            ],
          },
        ],
      );
      await ready(t);
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      final menu = find.byKey(const ValueKey('model-sheet'));
      expect(t.getSize(menu), const Size(248, 76));
      await t.tap(find.byKey(const ValueKey('model-root-effort')));
      await t.pumpAndSettle();
      expect(t.getSize(menu), const Size(248, 110));
    });

    testWidgets(
      'pointer drilling retains the source effort focus cue until blur',
      (t) async {
        t.view.physicalSize = const Size(1100, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        host.handlers['session/modelCatalog'] = (_) => catalog(
          groups: [
            {
              'id': 'deepseek-official',
              'name': 'DeepSeek',
              'models': [
                model(
                  'flash',
                  'Flash',
                  efforts: ['low', 'high', 'max'],
                  defaultEffort: 'max',
                ),
              ],
            },
          ],
        );
        await ready(t, size: const Size(1100, 800));
        await t.tap(find.byKey(const ValueKey('model-chip')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('model-root-effort')));
        await t.pumpAndSettle();
        final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
        await pointer.addPointer(location: const Offset(1090, 790));
        addTearDown(pointer.removePointer);
        await pointer.moveTo(const Offset(1000, 700));
        await t.pumpAndSettle();

        Finder row(String effort) =>
            find.byKey(ValueKey('effort-option-effort:$effort'));
        DshMenuItemButton button(String effort) =>
            t.widget<DshMenuItemButton>(row(effort));
        Color? fill(String effort) =>
            (t
                        .widget<DshContainer>(
                          find
                              .descendant(
                                of: row(effort),
                                matching: find.byType(DshContainer),
                              )
                              .first,
                        )
                        .decoration
                    as ShapeDecoration)
                .color;
        // Actual Chromium still matches :focus-visible after this pointer
        // sequence; selection itself remains a check on a transparent row.
        // Shared menu raster tests verify the composited color; this sequence
        // verifies when the focus cue is present and cleared.
        expect(button('max').focusNode!.hasPrimaryFocus, isTrue);
        expect(button('max').selected, isTrue);
        expect(button('max').selectionFill, isFalse);
        expect(fill('max'), isNotNull);
        expect(fill('high'), isNull);
        expect(fill('low'), isNull);

        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pumpAndSettle();
        expect(button('high').focusNode!.hasPrimaryFocus, isTrue);
        expect(fill('high'), isNotNull);
        expect(button('max').selected, isTrue);
        expect(fill('max'), isNull);

        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('model-root-effort')), findsOneWidget);
        expect(
          t
              .widget<DshMenuItemButton>(
                find.byKey(const ValueKey('model-root-effort')),
              )
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
      },
    );

    testWidgets(
      'pending effort choice keeps the row and blocks a second request',
      (t) async {
        final gate = Completer<void>();
        host.handlers['session/selectModel'] = (_) async {
          await gate.future;
          return {
            'selected': {
              'provider': 'deepseek-official',
              'model': 'flash',
              'reasoningEffort': 'low',
            },
          };
        };
        await ready(t);
        await t.tap(find.byKey(const ValueKey('model-chip')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('model-root-effort')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('effort-option-effort:low')));
        await t.pump();
        expect(find.byKey(const ValueKey('model-sheet')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('effort-option-effort:low')),
            matching: find.byType(DshStatusDot),
          ),
          findsOneWidget,
        );
        await t.tap(find.byKey(const ValueKey('effort-option-effort:high')));
        expect(host.callsTo('session/selectModel'), hasLength(1));
        gate.complete();
        await t.runAsync(() => flush(8));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('model-sheet')), findsNothing);
      },
    );

    testWidgets('public test support runs the real selector and projection', (
      t,
    ) async {
      await t.pumpWidget(
        dshTestApp(
          const ReportedModelFixture(i18n: DshI18n(DshLocale.en)),
          size: const Size(390, 800),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('model-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('model-root-effort')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('effort-option-effort:low')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-sheet')), findsNothing);
      expect(
        find.text('Selection: deepseek-official/flash/low'),
        findsOneWidget,
      );
      expect(find.text('Low'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await t.runAsync(() => flush(3));
    });
  });
}

/// A selection as the generated wire type.
class _Sel {
  const _Sel(this.provider, this.model, this.effort);
  final String provider;
  final String model;
  final String? effort;

  session_ns.ModelSelection get wire => session_ns.ModelSelection(
    provider: provider,
    model: model,
    reasoningEffort: effort,
  );
}
