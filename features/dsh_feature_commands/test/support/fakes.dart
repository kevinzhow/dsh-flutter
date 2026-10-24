import 'package:dsh_client/dsh_client.dart' show RemoteCaller, RemoteException;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart' show SessionSummary;

/// A scripted host: `commands/list` and `commands/execute` answer from the test.
class FakeHost implements RemoteCaller {
  List<Map<String, Object?>> catalog = [
    {
      'name': 'compact',
      'description': 'Compact older conversation history',
      'definitionId': '@deepseek-ai/dsh-command-compact',
    },
    {
      'name': 'goal',
      'description': 'Set a goal',
      'definitionId': '@deepseek-ai/dsh-command-goal',
      'input': {'hint': '[<objective>]', 'attachments': true},
    },
    {
      'name': 'plan',
      'description': 'Enter or leave plan mode',
      'definitionId': '@deepseek-ai/dsh-plan-mode',
      'input': {'hint': '[off|message]'},
    },
    {
      'name': 'permission',
      'description': 'Switch preset',
      'definitionId': '@deepseek-ai/dsh-permission-presets',
      'input': {'hint': '<preset>'},
    },
    {
      'name': 'feedback',
      'description': 'Record feedback',
      'definitionId': '@deepseek-ai/dsh-command-feedback',
      'input': {'hint': '<text>'},
    },
    {
      'name': 'export',
      'description': 'Download this Session log as a ZIP archive',
      'definitionId': '@deepseek-ai/dsh-session-log-export',
    },
    {'name': 'custom', 'description': 'A plugin command'},
  ];
  final List<String> listed = [];
  final List<({String line, int attachments})> executed = [];
  Object? listError;
  Object? executeError;

  /// The `result` the host answers; null means the line matched no command.
  Map<String, Object?>? result = {'kind': 'success'};
  bool unmatched = false;
  int listDelayTicks = 0;

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    if (namespace == 'commands' && method == 'list') {
      listed.add(args['agentId']! as String);
      for (var i = 0; i < listDelayTicks; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      if (listError != null) throw listError!;
      return catalog;
    }
    if (namespace == 'commands' && method == 'execute') {
      executed.add((
        line: args['line']! as String,
        attachments: (args['submittedAttachments']! as List).length,
      ));
      if (executeError != null) throw executeError!;
      if (unmatched) return null;
      return {'commandId': 'c1', 'result': result};
    }
    throw RemoteException('gateway/unknown', '$namespace/$method');
  }
}

class FakeSessions implements InputSessionPort {
  final Set<String> held = {'s1'};
  final Map<String, SessionSummary> summaries = {};
  final List<(String, String)> opened = [];
  Object? openError;
  @override
  String hostHome = '/home/user';

  @override
  Future<void> ensureOpen(String sessionId, AbortSignal signal) async {
    if (!held.contains(sessionId)) {
      throw StateError('session "$sessionId" is not held');
    }
    if (openError != null) throw openError!;
  }

  @override
  bool isSubagentTranscript(String sessionId) => false;

  @override
  SessionSummary? summary(String sessionId) => summaries[sessionId];

  @override
  void openFile(String sessionId, String path) => opened.add((sessionId, path));
}

class RecordingPort implements TriggerEditorPort {
  final List<String> calls = [];
  @override
  bool beginCommand(CommandClaim claim, TokenSpan span) {
    calls.add('claim ${claim.name}');
    return true;
  }

  @override
  bool consumeBareToken(String token) {
    calls.add('consumeToken $token');
    return true;
  }

  @override
  bool consumeSpan(TokenSpan span) {
    calls.add('consumeSpan ${span.start}-${span.end}');
    return true;
  }

  @override
  bool insertReference(ReferenceInsert reference, TokenSpan span) => true;
  @override
  bool insertText(String text, TokenSpan span, {bool keepCompleting = false}) =>
      true;
  @override
  void notify(bool error, String text) =>
      calls.add('notify ${error ? 'error' : 'info'} $text');
  @override
  void requestFocus() => calls.add('focus');
}
