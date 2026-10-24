import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_model_selection/dsh_feature_model_selection.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);

session_ns.ModelProviderGroup group(
  String id,
  String name,
  List<String> models,
) => session_ns.ModelProviderGroup(
  id: id,
  name: name,
  models: [
    for (final m in models) session_ns.ModelCatalogModel(id: m, name: m),
  ],
);

void main() {
  test('the /model rows follow the selector: account first, current marked, failures last', () {
    final state = ModelDirectoryState(
      current: const session_ns.ModelSelection(provider: 'p', model: 'm2'),
      groups: [
        group('p', 'Local', ['m1', 'm2']),
        group('deepseek-account', 'ignored', ['flash']),
      ],
      failures: const [
        session_ns.ModelCatalogFailure(
          id: 'bad',
          name: 'Broken',
          message: 'timeout',
        ),
      ],
    );
    final rows = modelOptions(state, en);
    expect(rows.map((r) => r.id), [
      'deepseek-account/flash',
      'p/m1',
      'p/m2',
      'failure/bad',
    ]);
    expect(rows.first.group!.label, 'DeepSeek Account');
    expect(rows.where((r) => r.active).map((r) => r.id), ['p/m2']);
    expect(rows.last.detail, contains('timeout'));
    expect(rows.last.group, isNull);
  });

  test('a picked row resolves back to its selection, keeping the effort of the same route', () {
    final state = ModelDirectoryState(
      current: const session_ns.ModelSelection(
        provider: 'p',
        model: 'm1',
        reasoningEffort: 'high',
      ),
      groups: [
        group('p', 'Local', ['m1', 'm2']),
      ],
    );
    final same = modelSelectionOf(state, 'p/m1')!;
    expect(
      (same.provider, same.model, same.reasoningEffort),
      ('p', 'm1', 'high'),
    );
    final other = modelSelectionOf(state, 'p/m2')!;
    expect(other.reasoningEffort, isNull);
    expect(modelSelectionOf(state, 'failure/bad'), isNull);
    expect(modelSelectionOf(state, 'p/gone'), isNull);
  });

  test('the command is a client contribution that a subagent transcript does not offer', () {
    final registry = CommandUiRegistry();
    registerModelCommand(
      registry,
      directoryOf: (_) => null,
      isSubagent: (id) => id == 'sub',
      i18n: () => en,
    );
    final model = registry.contributions['model']!;
    expect(model.available('s1'), isTrue);
    expect(model.available('sub'), isFalse);
    expect(model.label!(), 'Model');
    expect(
      (model.ui as PopupSelectSpec).searchMode,
      PopupSearchMode.fuzzyLabel,
    );
    expect(
      () => (model.ui as PopupSelectSpec).options('s1', AbortSignal.never),
      throwsStateError,
    );
  });
}
