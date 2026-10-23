import 'package:dsh_models/dsh_models.dart' show FileRef, ImageRef;

import 'partial_arguments.dart';

/// Assistant content blocks sorted by what a UI target presents (dsh
/// `AssistantBlock`).
sealed class AssistantBlock {
  const AssistantBlock();
}

class TextBlock extends AssistantBlock {
  const TextBlock(this.text);
  final String text;
}

class ReasoningBlock extends AssistantBlock {
  const ReasoningBlock(this.text);
  final String text;
}

class ImageBlock extends AssistantBlock {
  const ImageBlock(this.attachment);
  final Object? attachment;
}

class ToolCallRefBlock extends AssistantBlock {
  const ToolCallRefBlock({
    required this.callId,
    required this.name,
    required this.argsRaw,
  });
  final String callId;
  final String name;
  final String argsRaw;
}

class OtherBlock extends AssistantBlock {
  const OtherBlock(this.block);
  final Object? block;
}

/// A finalized assistant message or an interruption-frozen prefix (dsh
/// `AssistantMessageNode`).
class AssistantMessage {
  const AssistantMessage({
    required this.seq,
    required this.time,
    required this.turn,
    required this.step,
    required this.blocks,
    this.messageId,
    this.usage,
    this.stepStartTime,
    this.firstTokenTime,
    this.completedTime,
    this.interrupted = false,
  });
  final num seq;
  final String? messageId;
  final num time;
  final int turn;
  final int step;
  final List<AssistantBlock> blocks;
  final Object? usage;
  final num? stepStartTime;
  final num? firstTokenTime;
  final num? completedTime;
  final bool interrupted;
}

/// Final Assistant row payload shared by streaming and settled states (dsh
/// `AssistantChatData`).
class AssistantData {
  const AssistantData({
    required this.status,
    required this.turn,
    required this.step,
    required this.blocks,
    required this.time,
    this.usage,
    this.finalNode,
  });

  /// `running`, `settled` or `interrupted`.
  final String status;
  final int turn;
  final int step;
  final List<AssistantBlock> blocks;
  final num time;
  final Object? usage;
  final AssistantMessage? finalNode;
}

/// A tool call as the chat tracks it (dsh `ToolCallBlock`): preparing while its
/// arguments stream, started when dispatched, settled with a result.
sealed class ToolCall {
  const ToolCall({
    required this.callId,
    required this.name,
    required this.args,
    required this.subCalls,
    this.parentCallId,
  });
  final String callId;
  final String? parentCallId;
  final String name;

  /// The argument view; see [PartialArguments].
  final PartialArguments args;
  final List<ToolCall> subCalls;
}

class PreparingToolCall extends ToolCall {
  const PreparingToolCall({
    required super.callId,
    required super.name,
    required super.args,
    required super.subCalls,
    required this.turn,
    required this.step,
    required this.time,
  });
  final int turn;
  final int step;
  final num time;
}

class StartedToolCall extends ToolCall {
  const StartedToolCall({
    required super.callId,
    required super.name,
    required super.args,
    required super.subCalls,
    required this.argsRaw,
    required this.turn,
    required this.step,
    required this.time,
    super.parentCallId,
  });
  final String argsRaw;
  final int turn;
  final int step;
  final num time;
}

/// A settled tool call (dsh `ToolResultNode`).
class ToolResult extends ToolCall {
  const ToolResult({
    required super.callId,
    required super.name,
    required super.args,
    required super.subCalls,
    required this.seq,
    required this.time,
    required this.content,
    required this.isError,
    this.callArgsRaw,
    this.callTime,
    this.error,
    this.meta,
    super.parentCallId,
  });
  final num seq;
  final num time;

  /// Raw argument text of the paired call, null when the call left the window.
  final String? callArgsRaw;
  final num? callTime;
  final List<Object?> content;
  final bool isError;
  final Map<String, Object?>? error;
  final Object? meta;
}

class ToolData {
  const ToolData(this.root);
  final ToolCall root;
}

/// A finalized user (or steering/context) message (dsh `UserMessageNode`,
/// `SteeringMessageNode`, `ContextMessageNode`).
class MessageData {
  const MessageData({
    required this.kind,
    required this.seq,
    required this.time,
    required this.content,
    required this.source,
    this.messageId,
    this.producerRole,
    this.producerLabel,
    this.form,
    this.waking = false,
  });

  /// `user`, `steering` or `context`.
  final String kind;
  final num seq;
  final num time;
  final List<Object?> content;
  final Map<String, Object?>? source;
  final String? messageId;
  final String? producerRole;
  final String? producerLabel;
  final String? form;
  final bool waking;

  /// The text blocks joined, for plain display.
  String get text => [
    for (final b in content)
      if (b is Map && b['type'] == 'text') '${b['text']}',
  ].join();

  /// The message split the way ui-chat's `contentParts` does: text joined,
  /// durable attachments in order, every other block left over.
  UserContentParts get parts => userContentParts(content);
}

/// One durable attachment of a message: an [ImageRef] or a [FileRef].
sealed class MessageAttachment {
  const MessageAttachment();
}

final class MessageImage extends MessageAttachment {
  const MessageImage(this.image);
  final ImageRef image;
}

final class MessageFile extends MessageAttachment {
  const MessageFile(this.file);
  final FileRef file;
}

/// dsh ui-chat `contentParts`.
class UserContentParts {
  const UserContentParts({
    required this.text,
    required this.attachments,
    required this.rest,
  });

  final String text;
  final List<MessageAttachment> attachments;

  /// Blocks that are neither text nor a well-formed attachment.
  final List<Object?> rest;
}

/// Split message [content] into text, attachments and the rest. A malformed
/// attachment block stays in `rest` (dsh shows those as extra blocks).
UserContentParts userContentParts(List<Object?> content) {
  final texts = StringBuffer();
  final attachments = <MessageAttachment>[];
  final rest = <Object?>[];
  for (final block in content) {
    if (block is Map) {
      final type = block['type'];
      if (type == 'text' && block['text'] is String) {
        texts.write(block['text']);
        continue;
      }
      if (type == 'image') {
        final ref = ImageRef.tryParse(block['attachment']);
        if (ref != null) {
          attachments.add(MessageImage(ref));
          continue;
        }
      } else if (type == 'file') {
        final ref = FileRef.tryParse(block['attachment']);
        if (ref != null) {
          attachments.add(MessageFile(ref));
          continue;
        }
      }
    }
    rest.add(block);
  }
  return UserContentParts(
    text: texts.toString(),
    attachments: attachments,
    rest: rest,
  );
}

class TurnTailData {
  const TurnTailData({
    required this.turn,
    required this.seq,
    required this.time,
    required this.closing,
    required this.branchUnavailable,
  });
  final int turn;
  final num seq;
  final num time;

  /// Last finalized content-bearing Assistant of the turn.
  final AssistantData? closing;
  final bool branchUnavailable;
}

class TurnErrorData {
  const TurnErrorData({
    required this.seq,
    required this.time,
    required this.turn,
    required this.step,
    required this.message,
    this.code,
  });
  final num seq;
  final num time;
  final int turn;
  final int step;
  final String message;
  final String? code;
}

class TurnMaxTokensData {
  const TurnMaxTokensData({
    required this.seq,
    required this.time,
    required this.turn,
    required this.step,
  });
  final num seq;
  final num time;
  final int turn;
  final int step;
}

class UnknownData {
  const UnknownData({
    required this.seq,
    required this.time,
    required this.type,
    required this.data,
  });
  final num seq;
  final num time;
  final String type;
  final Object? data;
}
