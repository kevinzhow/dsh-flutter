/// Input-trigger feature (dsh `ui-input-trigger`): the candidate menu the
/// composer shows above itself when `/` or `@` is typed at the caret, and its
/// registration into `conversation.input.overlay`. The trigger pipeline itself
/// (detection, menu reduction, pick routing) is pure Dart in `dsh_conversation`.
library;

export 'src/candidate_icons.dart';
export 'src/menu_view.dart';
export 'src/register.dart';
