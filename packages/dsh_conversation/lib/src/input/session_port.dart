/// What the trigger sources need to know about the sessions of the composition
/// root (dsh's `ctx.sessions`): whether a session is open, its list facts, and
/// where a file reference opens. Sources never reach a session themselves.
library;

import 'package:dsh_models/dsh_models.dart' show SessionSummary;

import 'trigger_types.dart';

abstract interface class InputSessionPort {
  /// Completes when the session's initial history open succeeded; throws its
  /// open error otherwise, or the abort reason. A request for a session the app
  /// does not hold throws without a host call (dsh: "requires a retained
  /// session").
  Future<void> ensureOpen(String sessionId, AbortSignal signal);

  /// Whether the session is an addressed subagent transcript (read-only: no
  /// command catalog, no model selection).
  bool isSubagentTranscript(String sessionId);

  /// The session's list row, if the host listed it.
  SessionSummary? summary(String sessionId);

  /// The host account home, for abbreviating displayed paths.
  String get hostHome;

  /// Open a workspace file of [sessionId] in the sidebar (a file chip tap).
  void openFile(String sessionId, String path);
}
