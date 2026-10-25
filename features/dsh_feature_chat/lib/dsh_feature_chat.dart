/// Chat feature (dsh `ui-chat`): the chat view and the node renderers it owns
/// (user, steering, turn trigger, assistant step, turn tail, turn error,
/// max-tokens notice, system prompt, unknown), registered into the `conversation.view` and
/// `conversation.chat.node` slots.
library;

export 'src/chat_nodes.dart';
export 'src/chat_view.dart';
export 'src/command_view.dart';
export 'src/compaction_view.dart';
export 'src/model_retry_view.dart';
export 'src/register.dart';
export 'src/system_prompt_view.dart';
export 'src/stats_pills.dart';

export 'src/chat_preferences.dart';
export 'src/work_details_view.dart';
export 'src/work_details_settings.dart';

export 'src/context_view.dart';
export 'src/command_input_view.dart';
