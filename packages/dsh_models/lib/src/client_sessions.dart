import 'session.dart';
import 'session_manager.dart';

/// A reference-counted handle on one resident [Session] (dsh `SessionBinding`).
/// UI adapters hold bindings; the manager keeps the Session alive.
class SessionBinding {
  SessionBinding._(this._owner, this.sessionId, this.session);

  final ClientSessions _owner;
  final String sessionId;
  final Session session;
  bool _released = false;

  /// Release this reference; the Session stays resident in the manager.
  void release() {
    if (_released) return;
    _released = true;
    _owner._release(sessionId);
  }
}

/// Owns references and stable bindings, and projects catalog state without
/// selecting a global "current" session (dsh `ClientSessions`).
class ClientSessions {
  ClientSessions(this.manager);

  final SessionManager manager;
  final Map<String, int> _refs = {};

  /// Bind [sessionId], starting its follow stream on first reference.
  SessionBinding bind(String sessionId) {
    final session = manager.get(sessionId);
    if ((_refs[sessionId] = (_refs[sessionId] ?? 0) + 1) == 1) {
      // Fire and forget: failures land in the Session snapshot (openState).
      session.open();
    }
    return SessionBinding._(this, sessionId, session);
  }

  int referenceCount(String sessionId) => _refs[sessionId] ?? 0;

  void _release(String sessionId) {
    final n = (_refs[sessionId] ?? 1) - 1;
    if (n <= 0) {
      _refs.remove(sessionId);
    } else {
      _refs[sessionId] = n;
    }
  }
}
