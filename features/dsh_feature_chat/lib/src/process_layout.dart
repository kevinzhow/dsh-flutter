import 'dart:convert';

import 'package:characters/characters.dart';

import 'package:dsh_conversation/dsh_conversation.dart';

/// One stable reference: Assistant reasoning and reply share their Node data.
class ProcessMember {
  const ProcessMember(this.node, [this.part]);
  final ViewNode node;
  final String? part;
  String get key => part == null || part == 'response'
      ? node.key
      : jsonEncode([node.key, part]);
}

class ProcessGroup {
  const ProcessGroup(this.key, this.turn, this.members, this.closed);
  final String key;
  final int turn;
  final List<ProcessMember> members;
  final bool closed;
}

class ProcessEntry {
  const ProcessEntry.node(this.member) : group = null;
  const ProcessEntry.group(this.group) : member = null;
  final ProcessMember? member;
  final ProcessGroup? group;
  String get key => group?.key ?? member!.key;
  ViewNode get first => group?.members.first.node ?? member!.node;
}

/// Policy never changes these groups or reparents their member references.
class ProcessLayout {
  List<ProcessGroup> _previous = const [];

  List<ProcessEntry> project(ChatSnapshot snapshot) {
    final result = <ProcessEntry>[];
    final groups = <ProcessGroup>[];
    var pending = <ProcessMember>[];
    int? turn;
    void flush(bool closed) {
      if (pending.isEmpty) return;
      String? retained;
      for (final old in _previous) {
        if (old.turn != turn) continue;
        final offset = pending.indexWhere(
          (m) => m.key == old.members.first.key,
        );
        if (offset < 0 || offset + old.members.length > pending.length) {
          continue;
        }
        if (List.generate(
          old.members.length,
          (i) => pending[offset + i].key == old.members[i].key,
        ).every((v) => v)) {
          retained = old.key;
          break;
        }
      }
      final group = ProcessGroup(
        retained ?? jsonEncode(['process', pending.first.key]),
        turn!,
        pending,
        closed ||
            snapshot.timeline.turns[turn]?.status == BoundaryStatus.closed,
      );
      groups.add(group);
      result.add(ProcessEntry.group(group));
      pending = [];
    }

    for (final node in snapshot.visibleNodes) {
      final nextTurn = locationTurn(node.location);
      if (nextTurn != turn) {
        flush(true);
        turn = nextTurn;
      }
      if (nextTurn == null || node.groupTree != null) {
        flush(true);
        result.add(ProcessEntry.node(ProcessMember(node)));
      } else if (node.data case final AssistantData assistant) {
        if (assistant.blocks.any(
          (b) => b is ReasoningBlock && b.text.trim().isNotEmpty,
        )) {
          pending.add(ProcessMember(node, 'reasoning'));
        }
        if (hasAssistantReply(assistant.blocks)) {
          flush(true);
          result.add(ProcessEntry.node(ProcessMember(node, 'response')));
        }
      } else {
        pending.add(ProcessMember(node));
      }
    }
    flush(false);
    _previous = groups;
    return result;
  }
}

class TurnProcessPresentation {
  TurnProcessPresentation(ChatSnapshot chat, this.control) {
    final data = spec;
    final turn = owningTurn(control.location)!;
    num? opening;
    final nodes = chat.nodesOfTurn(data.turn);
    for (final n in nodes) {
      if (const {'exchange', 'input'}.contains(n.groupTree) &&
          (data.controlAnchorSeq == turn.start?.seq ||
              n.anchorSeq < data.controlAnchorSeq)) {
        if (opening == null || n.anchorSeq > opening) opening = n.anchorSeq;
      }
    }
    for (final n in nodes) {
      if (n.kind == 'turn-process') continue;
      if (const {'exchange', 'input'}.contains(n.groupTree) &&
          (opening == null || n.anchorSeq > opening)) {
        interleaved = true;
      }
      if (const {'exchange', 'input', 'turn'}.contains(n.groupTree) ||
          n.anchorSeq < data.processStartSeq ||
          (data.answerAnchorSeq != null &&
              n.anchorSeq >= data.answerAnchorSeq!)) {
        continue;
      }
      if (n.data is! AssistantData ||
          (n.data! as AssistantData).step != data.answerStep) {
        external = true;
      }
    }
  }
  final ViewNode control;
  TurnProcessData get spec => control.data! as TurnProcessData;
  bool interleaved = false, external = false;
  bool get hasContent => !interleaved && (external || spec.inlineReasoning);
  bool get alwaysOpen =>
      owningTurn(control.location)?.status != BoundaryStatus.closed ||
      interleaved ||
      turnProcessAlwaysOpen(control);
  bool member(ProcessMember member) {
    final node = member.node;
    if (member.part != 'reasoning' &&
        node.data is AssistantData &&
        (node.data! as AssistantData).step == spec.answerStep &&
        spec.answerAnchorSeq != null) {
      return false;
    }
    if (const {'exchange', 'input', 'turn'}.contains(node.groupTree) ||
        node.anchorSeq < spec.processStartSeq) {
      return false;
    }
    return spec.answerAnchorSeq == null ||
        node.anchorSeq < spec.answerAnchorSeq! ||
        (member.part == 'reasoning' &&
            node.data is AssistantData &&
            (node.data! as AssistantData).step == spec.answerStep);
  }
}

String toolActivity(String name) {
  if (name == 'read') return 'read';
  if (name == 'read_image') return 'readImage';
  if (name == 'grep' || name == 'glob' || name.endsWith('_inspect')) {
    return 'search';
  }
  if (name == 'write') return 'write';
  if (name == 'edit' || name == 'apply_patch') return 'edit';
  if (const {'bash', 'pwsh', 'exec_command', 'write_stdin'}.contains(name) ||
      name.startsWith('terminal_')) {
    return 'commands';
  }
  if (name == 'run_code') return 'code';
  if (name == 'web_search') return 'webSearch';
  if (name == 'web_fetch') return 'webFetch';
  if (isSubagentDelegation(name)) return 'subagents';
  if (const {
    'todo_write',
    'create_goal',
    'update_goal',
    'get_goal',
  }.contains(name)) {
    return 'plan';
  }
  if (name == 'ask_user_question' || name == 'request_user_input') {
    return 'questions';
  }
  return 'tools';
}

class ProcessActivity {
  ProcessActivity(List<ProcessMember> members) {
    final seen = <String>{};
    void visit(ToolCall tool) {
      if (!seen.add(tool.callId)) return;
      // A result without its dispatched call is not evidence of another call.
      if (tool is! ToolResult || tool.callArgsRaw != null) {
        final kind = toolActivity(tool.name);
        counts[kind] = (counts[kind] ?? 0) + 1;
        if (tool is! ToolResult) {
          final time = tool is StartedToolCall
              ? tool.time
              : (tool as PreparingToolCall).time;
          if (time >= runningTime) {
            running = kind;
            runningTime = time;
            preparing = tool is PreparingToolCall;
            detail = _toolDetail(tool);
          }
        }
      }
      for (final child in tool.subCalls) {
        visit(child);
      }
    }

    for (final member in members) {
      if (member.node.data case ToolData(:final root)) visit(root);
    }
    if (running == null) {
      for (final member in members.reversed) {
        if (member.node.data case AssistantData(
          status: 'running',
          :final blocks,
        )) {
          for (final block in blocks.reversed) {
            if (block is ReasoningBlock) {
              final paragraphs = block.text.split(RegExp(r'\r?\n[\t ]*\r?\n'));
              final found = paragraphs.reversed
                  .map((p) => _oneLine(p.replaceAll('**', '')))
                  .firstWhere((p) => p.isNotEmpty, orElse: () => '');
              if (found.isNotEmpty) {
                detail = found;
                return;
              }
            }
          }
        }
      }
    }
  }
  final counts = <String, int>{};
  String? running;
  String detail = '';
  num runningTime = double.negativeInfinity;
  bool preparing = false;
  List<String> get ranked {
    final order = counts.keys.toList();
    return [...order]..sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      return c != 0 ? c : order.indexOf(a).compareTo(order.indexOf(b));
    });
  }
}

String _oneLine(String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final graphemes = line.characters;
  return graphemes.length <= 160
      ? line
      : '${graphemes.take(159).toString().trimRight()}…';
}

String _toolDetail(ToolCall tool) {
  for (final key in const [
    'title',
    'description',
    'objective',
    'task',
    'task_name',
    'name',
    'question',
    'questions',
    'prompt',
    'message',
    'command',
    'cmd',
    'queries',
    'query',
    'pattern',
    'url',
    'uri',
    'file_path',
    'path',
    'target',
    'action',
    'status',
  ]) {
    if (!tool.args.has(key)) continue;
    final value = tool.args.text(key) ?? tool.args.value(key);
    if (value is String && value.trim().isNotEmpty) return _oneLine(value);
    if (value is List && value.every((v) => v is String)) {
      return _oneLine(value.join(', '));
    }
    if (key == 'questions' && value is List) {
      for (final item in value) {
        if (item is Map &&
            item['question'] is String &&
            (item['question'] as String).trim().isNotEmpty) {
          return _oneLine(item['question'] as String);
        }
      }
    }
  }
  return tool.args.isSealed ? tool.name : '';
}
