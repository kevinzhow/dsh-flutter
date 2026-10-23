/// The shell executor's settings page (dsh `ui-settings-shell`): the command
/// timeout and the per-stream output cap over the namespace of the composed
/// shell executor (`bash-sandbox`, or `pwsh-sandbox` on Windows), as a card on
/// the Plugins page that exists only while the host serves one of them.
library;

export 'src/config_form_scope.dart';
export 'src/register.dart';
export 'src/shell_card.dart';
export 'src/shell_card_controller.dart';
