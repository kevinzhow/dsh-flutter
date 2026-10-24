import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';

import 'model_directory.dart';
import 'provider_order.dart';

String _rowId(String provider, String model) => '$provider/$model';

/// The `/model` popup rows (dsh `optionsOf`): every loaded provider group in the
/// selector's order with the current model marked active, then one row per
/// provider-local load failure.
List<SelectOption> modelOptions(ModelDirectoryState state, DshI18n i18n) {
  String t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('model', key, params: params);
  final rows = <SelectOption>[];
  for (final group in orderModelProviders(state.groups, (g) => g.id)) {
    final name = group.id == 'deepseek-account'
        ? t('provider.account')
        : group.name;
    for (final model in group.models) {
      rows.add(
        SelectOption(
          id: _rowId(group.id, model.id),
          label: model.name,
          group: SelectOptionGroup(name: group.id, label: name),
          active:
              state.current != null &&
              state.current!.provider == group.id &&
              state.current!.model == model.id,
        ),
      );
    }
  }
  for (final failure in state.failures) {
    rows.add(
      SelectOption(
        id: 'failure/${failure.id}',
        label: failure.id == 'deepseek-account'
            ? t('provider.account')
            : failure.name,
        detail: t('option.loadError', {'message': failure.message}),
      ),
    );
  }
  return rows;
}

/// Resolve a picked row back to its model selection by matching the loaded
/// groups (the data the rows were built from; ids stay opaque). Null for a
/// failure row or a stale id.
session_ns.ModelSelection? modelSelectionOf(
  ModelDirectoryState state,
  String id,
) {
  for (final group in state.groups) {
    for (final model in group.models) {
      if (_rowId(group.id, model.id) != id) continue;
      final sameRoute =
          state.current?.provider == group.id &&
          state.current?.model == model.id;
      final effort = sameRoute
          ? state.current?.reasoningEffort ?? model.reasoning?.defaultEffort
          : model.reasoning?.defaultEffort;
      return session_ns.ModelSelection(
        provider: group.id,
        model: model.id,
        reasoningEffort: effort,
      );
    }
  }
  return null;
}

/// Register the `/model` popupSelect over the shared directory (dsh
/// `ui-model-selection` entry 1). [directoryOf] resolves one session's
/// directory (shared with the composer seat); null for a session this client
/// does not hold. A subagent transcript offers no model selection.
void Function() registerModelCommand(
  CommandUiRegistry commandUi, {
  required ModelDirectory? Function(String sessionId) directoryOf,
  required bool Function(String sessionId) isSubagent,
  required DshI18n Function() i18n,
}) {
  String t(String key) => i18n().t('model', key);
  ModelDirectory directory(String sessionId) {
    if (isSubagent(sessionId)) {
      throw StateError(
        'model selection is unavailable for addressed subagent sessions',
      );
    }
    final d = directoryOf(sessionId);
    if (d == null) throw StateError('this session is not open');
    return d;
  }

  return commandUi.register(
    CommandContribution(
      name: 'model',
      label: () => t('command.label'),
      description: () => t('command.description'),
      icon: 'model',
      available: (sessionId) => !isSubagent(sessionId),
      ui: PopupSelectSpec(
        searchMode: PopupSearchMode.fuzzyLabel,
        searchLabels: () => PopupSearchLabels(
          placeholder: t('search.placeholder'),
          empty: t('empty.models'),
          noResults: t('search.empty'),
        ),
        options: (sessionId, signal) async =>
            modelOptions(await directory(sessionId).load(), i18n()),
        onSelect: (option, sessionId) async {
          final d = directory(sessionId);
          final selection = modelSelectionOf(d.state.value, option.id);
          if (selection == null) {
            throw StateError(
              "this provider's catalog failed to load: pick a model from a loaded group",
            );
          }
          final result = await d.select(selection);
          final refusal = result.error;
          if (refusal != null) {
            if (refusal.code == 'session/writer-held') {
              throw StateError(t('error.sessionInUse'));
            }
            throw refusal;
          }
        },
      ),
    ),
  );
}
