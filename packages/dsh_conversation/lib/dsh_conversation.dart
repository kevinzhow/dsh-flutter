/// Conversation layer (dsh `ui-conversation` engine and `ui-chat` target):
/// event Definitions correlating durable session events and live
/// `assistant/live-chunk` updates into stable Contexts, and the chat target
/// snapshot built from them.
library;

export 'src/assembler.dart' show ConversationAssembler, conversationContextKey;
export 'src/binding.dart';
export 'src/chat/definitions.dart';
export 'src/chat/nodes.dart';
export 'src/chat/partial_arguments.dart';
export 'src/chat/snapshot.dart';
export 'src/contract.dart';
export 'src/event.dart' show ConvEvent, seqText;
export 'src/location_index.dart' show ConversationLocationIndex;
export 'src/registry.dart';
