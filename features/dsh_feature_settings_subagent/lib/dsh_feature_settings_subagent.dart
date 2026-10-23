/// The Subagent settings page (dsh `ui-settings-subagent`), its delegation
/// limits only: maximum recursion depth and parallelism limit over the
/// `subagent` namespace, as a card on the Plugins page that exists only while
/// the host serves that namespace.
///
/// Not ported: dsh's second card on the same page, the models agents may
/// choose (`subagent-model-selection-settings`), which needs the model catalog
/// and its own save path.
library;

export 'src/config_form_scope.dart';
export 'src/register.dart';
export 'src/subagent_card.dart';
export 'src/subagent_limits_card_controller.dart';
