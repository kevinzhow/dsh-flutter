/// Chat feature (dsh `ui-chat`): the chat view and the node renderers it owns
/// (user, steering, turn trigger, assistant step, turn tail, turn error,
/// max-tokens notice, unknown), registered into the `conversation.view` and
/// `conversation.chat.node` slots.
library;

export 'src/chat_nodes.dart';
export 'src/chat_view.dart';
export 'src/register.dart';
export 'src/stats_pills.dart';
