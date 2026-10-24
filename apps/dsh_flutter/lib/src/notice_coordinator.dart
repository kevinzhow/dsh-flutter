import 'dart:async';

import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';

import 'platform/notifications.dart';

/// Decides when the phone is told that a session needs the user.
///
/// While the app is in the background (and its connection to the host is
/// alive), a pending approval or a pending question of any session becomes one
/// local notification; answering it elsewhere, or the host withdrawing it,
/// withdraws the notification; returning to the app withdraws all of them (the
/// composer takeover is then on screen). Tapping a notification opens its
/// session, where the same takeover answers it.
///
/// What this cannot do is reach a user whose app the system has killed: the
/// host sends these requests only to connections that are open, and no relay
/// pushes them. To keep the connection open after the user leaves, on Android,
/// the coordinator keeps a foreground service running, but only while sessions
/// are running and the user wants notifications (see [NotificationService.
/// startKeepAlive]).
class NoticeCoordinator {
  NoticeCoordinator({
    required this.service,
    required this.approvals,
    required this.questions,
    required this.i18n,
    required this.sessionTitle,
    required this.runningSessions,
    required this.onOpen,
    bool enabled = true,
  }) : _enabled = enabled {
    _subs.add(approvals.pending.changes.listen((_) => _sync()));
    _subs.add(questions.pending.changes.listen((_) => _sync()));
  }

  final NotificationService service;
  final ApprovalTracker approvals;
  final QuestionTracker questions;

  /// The language of the moment.
  final DshI18n Function() i18n;

  /// A session's title for the notification text (a fallback when unknown).
  final String Function(String sessionId) sessionTitle;

  /// How many sessions are running now.
  final int Function() runningSessions;

  /// Open [sessionId] in the app (a notification was tapped).
  final void Function(String sessionId) onOpen;

  final List<StreamSubscription<Object?>> _subs = [];
  bool _enabled;
  bool _foreground = true;
  bool _connected = false;
  NoticePermission _permission = NoticePermission.notDetermined;

  /// Pending keys already considered: shown, or seen while in the foreground.
  final Set<String> _seen = {};

  /// Notifications on screen by pending key.
  final Map<String, int> _shown = {};
  bool _keepAlive = false;
  int _keepAliveCount = 0;
  bool _disposed = false;

  bool get enabled => _enabled;
  NoticePermission get permission => _permission;

  /// Whether a keep-alive service is requested right now.
  bool get keepingAlive => _keepAlive;

  /// Start the platform side and learn the permission.
  Future<void> init() async {
    await service.init(onOpen: onOpen);
    await refreshPermission();
  }

  Future<void> refreshPermission() async {
    _permission = await service.permission();
    _sync();
  }

  /// Ask the system for permission when the user wants notifications and it
  /// has not been asked (the Android 13 / iOS prompt).
  Future<void> requestIfNeeded() async {
    if (!_enabled || _permission != NoticePermission.notDetermined) return;
    _permission = await service.requestPermission();
    _sync();
  }

  /// The user pressed Allow in settings: ask again, whatever was answered.
  Future<void> request() async {
    _permission = await service.requestPermission();
    _sync();
  }

  Future<void> openSystemSettings() => service.openSettings();

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      unawaited(_cancelShown());
    } else {
      unawaited(requestIfNeeded());
    }
    _sync();
  }

  /// The app moved to or from the foreground.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      unawaited(_cancelShown());
      unawaited(refreshPermission());
    }
    _sync();
  }

  /// Whether a host connection is up (the keep-alive has nothing to keep
  /// otherwise).
  void setConnected(bool connected) {
    if (_connected == connected) return;
    _connected = connected;
    _sync();
  }

  /// The session list changed (running sessions count toward the keep-alive).
  void sessionsChanged() => _sync();

  bool get _mayNotify =>
      !_disposed &&
      _enabled &&
      !_foreground &&
      _permission == NoticePermission.granted;

  _Notice _noticeOf(PendingApproval a) {
    final t = i18n();
    return _Notice(
      a.sessionId,
      t.t(appNamespace, 'notice.approval.title'),
      t.t(
        appNamespace,
        'notice.approval.body',
        params: {'session': sessionTitle(a.sessionId), 'tool': a.toolName},
      ),
    );
  }

  _Notice _noticeOfQuestion(PendingQuestion q) {
    final t = i18n();
    final first = q.questions.isEmpty ? '' : q.questions.first.question;
    final question = first.length > 120 ? '${first.substring(0, 119)}…' : first;
    return _Notice(
      q.sessionId,
      t.t(appNamespace, 'notice.question.title'),
      t.t(
        appNamespace,
        'notice.question.body',
        params: {'session': sessionTitle(q.sessionId), 'question': question},
      ),
    );
  }

  void _sync() {
    if (_disposed) return;
    final current = <String, _Notice Function()>{
      for (final a in approvals.pending.value)
        'approval:${a.key}': () => _noticeOf(a),
      for (final q in questions.pending.value)
        'question:${q.key}': () => _noticeOfQuestion(q),
    };
    // Withdrawn or answered: its notification goes.
    for (final key in _shown.keys.toList()) {
      if (!current.containsKey(key)) {
        unawaited(service.cancel(_shown.remove(key)!));
      }
    }
    _seen.removeWhere((key) => !current.containsKey(key));
    final notify = _mayNotify;
    for (final entry in current.entries) {
      if (!_seen.add(entry.key)) continue;
      // Arrived while the user was looking, or while notifications are off or
      // refused: never notified later.
      if (!notify) continue;
      final n = entry.value();
      final id = _idFor(entry.key);
      _shown[entry.key] = id;
      unawaited(
        service.show(
          id: id,
          title: n.title,
          body: n.body,
          sessionId: n.sessionId,
        ),
      );
    }
    _syncKeepAlive();
  }

  static int _idFor(String key) => (key.hashCode & 0x3fffffff) + 2;

  Future<void> _cancelShown() async {
    _shown.clear();
    await service.cancelAll();
  }

  void _syncKeepAlive() {
    final running = runningSessions();
    final want = _mayNotify && _connected && running > 0;
    if (!want) {
      if (_keepAlive) {
        _keepAlive = false;
        _keepAliveCount = 0;
        unawaited(service.stopKeepAlive());
      }
      return;
    }
    if (_keepAlive && _keepAliveCount == running) return;
    _keepAlive = true;
    _keepAliveCount = running;
    final t = i18n();
    unawaited(
      service.startKeepAlive(
        title: t.t(appNamespace, 'notice.watching.title'),
        body: running == 1
            ? t.t(appNamespace, 'notice.watching.body.one')
            : t.t(
                appNamespace,
                'notice.watching.body.other',
                params: {'count': running},
              ),
      ),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    if (_keepAlive) {
      _keepAlive = false;
      await service.stopKeepAlive();
    }
  }
}

class _Notice {
  const _Notice(this.sessionId, this.title, this.body);
  final String sessionId;
  final String title;
  final String body;
}
