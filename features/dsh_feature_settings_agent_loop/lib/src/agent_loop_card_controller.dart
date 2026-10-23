import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';

import 'config_form_scope.dart';

/// Namespace of the agent loop's user-owned settings. Spelled here rather than
/// imported: a client package must not depend on a Host package.
const String agentLoopNamespace = 'agent-loop';

/// The field this page edits; the composed `agents` array is deliberately not
/// part of it.
const String maxParallelToolCallsField = 'maxParallelToolCalls';

/// What the agent-loop page renders (dsh `AgentLoopCardState`).
class AgentLoopCardState {
  const AgentLoopCardState({
    required this.shell,
    required this.maxParallelToolCalls,
  });

  /// Availability, writability, and what a save would do.
  final SettingsFormShell shell;

  /// Parallel tool-call cap.
  final SettingsFieldState maxParallelToolCalls;
}

/// Bridges the `agent-loop` form onto the page's staged form (dsh
/// `AgentLoopCardController`).
class AgentLoopCardController {
  /// [form] is the shared configuration form of the `agent-loop` namespace.
  AgentLoopCardController(ConfigForm form)
    : _model = SettingsFormModel(ConfigFormScope(form), [
        settingsNumberField(maxParallelToolCallsField),
      ]) {
    store = _model.bind(
      () => AgentLoopCardState(
        shell: _model.shell(),
        maxParallelToolCalls: _model.field(maxParallelToolCallsField),
      ),
    );
    actions = _model.actions();
  }

  final SettingsFormModel _model;

  /// The projection the card renders.
  late final SettingsFormStore<AgentLoopCardState> store;

  /// Edit, reset, save and discard.
  late final SettingsFormActions actions;

  /// Release the form subscription.
  void dispose() => _model.dispose();
}
