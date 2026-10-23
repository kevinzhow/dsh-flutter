import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';

import 'config_form_scope.dart';

/// Namespace of the delegation limits. Spelled here rather than imported: a
/// client package must not depend on a Host package.
const String subagentNamespace = 'subagent';

/// Deepest chain of subagents an agent may create; 0 disables subagents.
const String maxDepthField = 'maxDepth';

/// Live subagents allowed under one main agent, at every depth.
const String maxActiveSubagentsField = 'maxActiveSubagents';

/// A whole-number field with a [minimum] (dsh `limitField`): the number field's
/// verdicts, narrowed to safe integers at or above the minimum, and not `-0`.
SettingsFieldSpec subagentLimitField(String field, int minimum) {
  final numeric = settingsNumberField(field);
  return SettingsFieldSpec(
    field: field,
    format: numeric.format,
    parse: (text) {
      final write = numeric.parse(text);
      if (write is! SettingsFieldSet) return write;
      final value = write.value;
      // `Object.is(value, -0)`: the number parser reads "-0" as the integer 0,
      // so the sign has to be read from the text.
      final negativeZero = value == 0 && RegExp(r'^\s*-').hasMatch(text);
      // The parser answers an int exactly for whole numbers inside the safe
      // range (`Number.isSafeInteger`); anything else stays a double.
      return value is int && value >= minimum && !negativeZero ? write : null;
    },
  );
}

/// What the limits card renders (dsh `SubagentLimitsCardState`).
class SubagentLimitsCardState {
  const SubagentLimitsCardState({
    required this.shell,
    required this.maxDepth,
    required this.maxActiveSubagents,
  });

  /// Availability, writability, and what a save would do.
  final SettingsFormShell shell;

  final SettingsFieldState maxDepth;
  final SettingsFieldState maxActiveSubagents;
}

/// Binds two independently resettable limits to one staged settings form (dsh
/// `SubagentLimitsCardController`).
class SubagentLimitsCardController {
  /// [form] is the Host's `subagent` settings section.
  SubagentLimitsCardController(ConfigForm form)
    : _model = SettingsFormModel(ConfigFormScope(form), [
        subagentLimitField(maxDepthField, 0),
        subagentLimitField(maxActiveSubagentsField, 1),
      ]) {
    store = _model.bind(
      () => SubagentLimitsCardState(
        shell: _model.shell(),
        maxDepth: _model.field(maxDepthField),
        maxActiveSubagents: _model.field(maxActiveSubagentsField),
      ),
    );
    actions = _model.actions();
  }

  final SettingsFormModel _model;

  /// The projection the card renders.
  late final SettingsFormStore<SubagentLimitsCardState> store;

  /// Edit, reset, save and discard.
  late final SettingsFormActions actions;

  /// Release the form subscription.
  void dispose() => _model.dispose();
}
