import 'dart:convert';

import '../chat/definitions.dart';
import '../contract.dart';
import '../event.dart';

/// Complete Markdown and heading of one submitted plan (dsh `SubmittedPlan`).
class SubmittedPlan {
  const SubmittedPlan({
    required this.callId,
    required this.markdown,
    required this.title,
  });

  /// The originating `exit_plan_mode` invocation.
  final String callId;
  final String markdown;
  final String title;
}

/// Read a complete plan from untrusted logged arguments (dsh
/// `submittedPlan`): a native `tool/call` or a PTC dispatch of
/// `exit_plan_mode` whose `plan` argument is Markdown opening with a heading.
SubmittedPlan? submittedPlan(String type, Map<String, Object?> data) {
  if (type != 'tool/call' &&
      type != 'tool/ptc-dispatch-start' &&
      type != 'tool/ptc-dispatch') {
    return null;
  }
  if (data['name'] != 'exit_plan_mode') return null;
  final callId = type == 'tool/call' ? data['callId'] : data['subCallId'];
  if (callId is! String || callId.isEmpty) return null;
  Object? args = data['arguments'];
  if (type == 'tool/call') {
    if (args is! String) return null;
    try {
      args = jsonDecode(args);
    } on FormatException {
      return null; // Malformed model JSON stays in the generic tool row.
    }
  }
  if (args is! Map<String, Object?> || args['plan'] is! String) return null;
  final markdown = args['plan']! as String;
  final title = RegExp(r'^#\s+(\S[^\r\n]*)')
      .firstMatch(markdown.trim())
      ?.group(1);
  return title == null
      ? null
      : SubmittedPlan(callId: callId, markdown: markdown, title: title);
}

/// Node kind of a submitted plan on the chat target.
const submittedPlanKind = 'submitted-plan';

/// One hidden card-data node per `exit_plan_mode` invocation, placed in its
/// resolved Turn (dsh `planDefinition`); a later PTC settlement keeps the
/// original position.
class SubmittedPlanDefinition extends ConversationDefinition {
  const SubmittedPlanDefinition();

  @override
  String get kind => submittedPlanKind;
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {
    'tool/call',
    'tool/ptc-dispatch-start',
    'tool/ptc-dispatch',
  };

  @override
  MatchResult? match(ConvEvent event) {
    final plan = submittedPlan(event.type, event.data);
    return plan == null
        ? null
        : MatchResult(
            plan.callId,
            event.type == 'tool/ptc-dispatch'
                ? MatchRole.update
                : MatchRole.start,
          );
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => submittedPlan(match.event.type, match.event.data)!;

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final start = context.start ?? context.matches.firstOrNull;
    final data =
        context.state as SubmittedPlan? ??
        (start == null
            ? null
            : submittedPlan(start.event.type, start.event.data));
    if (data == null || start == null) return null;
    return ViewNode(
      key: context.key,
      kind: submittedPlanKind,
      id: context.id,
      target: chatTarget,
      anchorSeq: start.event.seq,
      location: start.location,
      visible: false,
      data: data,
    );
  }
}
