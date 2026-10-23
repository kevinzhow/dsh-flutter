import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';

import 'config_form_scope.dart';

/// Profile entry id of the POSIX shell executor; the base bundle composes it
/// off Windows.
const String bashNamespace = 'bash-sandbox';

/// Profile entry id of the PowerShell executor; the base bundle composes it on
/// Windows.
const String pwshNamespace = 'pwsh-sandbox';

/// Foreground command timeout in milliseconds.
const String timeoutMsField = 'timeoutMs';

/// Per-stream in-memory output cap in bytes.
const String maxOutputBytesField = 'maxOutputBytes';

/// What the shell page renders (dsh `ShellCardState`).
class ShellCardState {
  const ShellCardState({
    required this.shell,
    required this.timeoutMs,
    required this.maxOutputBytes,
  });

  /// Availability, writability, and what a save would do.
  final SettingsFormShell shell;

  /// Command timeout in milliseconds.
  final SettingsFieldState timeoutMs;

  /// Per-stream output cap in bytes.
  final SettingsFieldState maxOutputBytes;
}

/// Bridges one shell executor entry's form onto the page's staged form (dsh
/// `ShellCardController`). The fields are a subset of the served schema by
/// design.
class ShellCardController {
  /// [form] is the shared configuration form of the composed shell executor
  /// entry.
  ShellCardController(ConfigForm form)
    : _model = SettingsFormModel(ConfigFormScope(form), [
        settingsNumberField(timeoutMsField),
        settingsNumberField(maxOutputBytesField),
      ]) {
    store = _model.bind(
      () => ShellCardState(
        shell: _model.shell(),
        timeoutMs: _model.field(timeoutMsField),
        maxOutputBytes: _model.field(maxOutputBytesField),
      ),
    );
    actions = _model.actions();
  }

  final SettingsFormModel _model;

  /// The projection the card renders.
  late final SettingsFormStore<ShellCardState> store;

  /// Edit, reset, save and discard.
  late final SettingsFormActions actions;

  /// Release the form subscription.
  void dispose() => _model.dispose();
}
