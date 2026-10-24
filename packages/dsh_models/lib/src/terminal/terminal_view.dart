import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_terminal.dart';

import '../observable.dart';
import 'terminal_hold.dart';
import 'terminal_host.dart';
import 'terminal_inventory.dart';
import 'terminal_prefs.dart';

/// Where one terminal tab is (dsh `TerminalViewState.phase`).
enum TerminalPhase {
  idle,
  loading,
  creating,
  connecting,
  connected,
  disconnected,
  closing,
  closed,
  failed,
}

/// Product error identifiers the terminal screen translates (dsh
/// `TerminalViewIssue`): the keys of the `sidebarTerminal` copy.
enum TerminalViewIssue {
  missingTerminal,
  inputFull,
  attachmentEnded,
  invalidOutput,
  terminalLimit,
}

/// One screen write waiting for the emulator (dsh `TerminalRenderFrame`): the
/// next frame is only taken once [TerminalView.acknowledge] named [revision].
class TerminalRenderFrame {
  const TerminalRenderFrame(this.revision, this.frame);
  final int revision;

  /// A [TerminalFrameSnapshot] (reset and redraw) or a [TerminalFrameOutput].
  final TerminalFrame frame;
}

const Object _keep = Object();

/// Observable state of one terminal tab.
class TerminalViewState {
  const TerminalViewState({
    this.phase = TerminalPhase.idle,
    this.environment,
    this.title,
    this.info,
    this.writable = false,
    this.render,
    this.error,
    this.issue,
  });

  final TerminalPhase phase;
  final TerminalEnvironment? environment;
  final String? title;
  final WebTerminalInfo? info;
  final bool writable;
  final TerminalRenderFrame? render;
  final String? error;
  final TerminalViewIssue? issue;

  /// A copy; the nullable fields keep their value unless named (pass null to
  /// clear).
  TerminalViewState copyWith({
    TerminalPhase? phase,
    Object? environment = _keep,
    Object? title = _keep,
    Object? info = _keep,
    bool? writable,
    Object? render = _keep,
    Object? error = _keep,
    Object? issue = _keep,
  }) => TerminalViewState(
    phase: phase ?? this.phase,
    environment: identical(environment, _keep)
        ? this.environment
        : environment as TerminalEnvironment?,
    title: identical(title, _keep) ? this.title : title as String?,
    info: identical(info, _keep) ? this.info : info as WebTerminalInfo?,
    writable: writable ?? this.writable,
    render: identical(render, _keep)
        ? this.render
        : render as TerminalRenderFrame?,
    error: identical(error, _keep) ? this.error : error as String?,
    issue: identical(issue, _keep) ? this.issue : issue as TerminalViewIssue?,
  );
}

class _ViewError implements Exception {
  _ViewError(this.issue, [String? message]) : message = message ?? issue.name;
  final TerminalViewIssue issue;
  final String message;
  @override
  String toString() => message;
}

class _Cost {
  const _Cost(this.inputBytes, this.frameBytes);
  final int inputBytes;
  final int frameBytes;
}

class _Queued {
  const _Queued(this.command, this.cost);
  final TerminalInput command;
  final _Cost cost;
}

int _sequenceOf(TerminalInput input) => switch (input) {
  TerminalInputWrite(:final sequence) => sequence,
  TerminalInputResize(:final sequence) => sequence,
  TerminalInputUnrecognized() => 0,
};

/// One physical `attach` stream and the input bookkeeping that belongs to it:
/// a new attachment starts its command numbering at one, and unacknowledged
/// input is never carried over to the next one.
class _Attachment {
  _Attachment(this.stream);

  final GenerationStream stream;
  StreamSubscription<GenerationFrame>? subscription;
  bool closed = false;

  /// The next stream item has to be this generation's screen snapshot.
  bool expectSnapshot = false;
  int outputSequence = 0;
  int sequence = 0;
  int acknowledged = 0;
  final Map<int, _Cost> pending = {};
  final Queue<_Queued> queued = Queue();
  RemoteUplinkWindow? window;
  int bytes = 0;
  int bufferedBytes = 0;
  int inFlightBytes = 0;

  /// Frames received but not yet rendered (the render handshake is serial).
  final Queue<TerminalFrame> inbox = Queue();
  bool draining = false;
}

/// A view survives the screen that shows it; its process only ends on an
/// explicit [close]. The Dart counterpart of dsh's `TerminalView`
/// (`api-terminal-controller/client`): it creates or finds the Host terminal,
/// holds it for this window, follows its screen over the duplex `attach`
/// stream and orders input and resize commands within the carrier's window.
class TerminalView {
  TerminalView({
    required this.sessionId,
    required this.id,
    required TerminalHost host,
    required TerminalInventory inventory,
    TerminalPrefs? prefs,
    bool createWhenMissing = true,
    this.shellPath,
  }) : _host = host,
       _inventory = inventory,
       _prefs = prefs ?? MemoryTerminalPrefs(),
       _createWhenMissing = createWhenMissing;

  final String sessionId;

  /// The Host terminal identity this view creates or reattaches.
  final String id;

  /// The shell chosen on the guide; null follows the remembered available one.
  final String? shellPath;

  final TerminalHost _host;
  final TerminalInventory _inventory;
  final TerminalPrefs _prefs;
  bool _createWhenMissing;

  /// Observable controls, process metadata and the screen write waiting for
  /// the emulator.
  final Observable<TerminalViewState> state = Observable(
    const TerminalViewState(),
  );

  bool _disposed = false;
  bool _mounted = false;
  _Attachment? _attachment;
  TerminalWindowHold? _hold;
  StreamSubscription<ConnectionGeneration?>? _generations;
  Completer<void>? _pendingRender;
  int _pendingRevision = 0;
  int _revision = 0;
  Future<void>? _creation;
  Future<void>? _loading;
  Future<void>? _closing;
  int _connectToken = 0;

  TerminalViewState get snapshot => state.value;

  /// Attach the screen's lifetime: start the chosen shell, or reconnect the
  /// process this view already knows. Returns the detach callback, which
  /// leaves the process alive.
  void Function() mount() {
    _mounted = true;
    final current = state.value;
    if (current.phase == TerminalPhase.idle) {
      unawaited(refresh());
    } else if (current.info != null &&
        current.phase != TerminalPhase.failed &&
        current.phase != TerminalPhase.closed &&
        current.phase != TerminalPhase.closing) {
      connect();
    }
    return () {
      _mounted = false;
      _detach();
    };
  }

  /// Start or explicitly retry this tab: read the limits, then create the
  /// terminal (a new identity) or find it in the Session list (a known one).
  Future<void> refresh() {
    final creating = _creation;
    if (creating != null) return creating;
    final loading = _loading;
    if (loading != null) return loading;
    if (_closing != null || _disposed) return Future.value();
    final retry = state.value.phase != TerminalPhase.idle;
    _patch(phase: TerminalPhase.loading, error: null, issue: null);
    return _loading = (() async {
      try {
        final environment = await _host.remote.environment(sessionId);
        final available = _createWhenMissing
            ? null
            : await _inventory.read(refresh: retry);
        if (_stopped) return;
        _patch(environment: environment);
        final info = available?[id];
        if (info != null) {
          _adopt(info);
        } else if (_createWhenMissing) {
          var path = shellPath;
          if (path == null) {
            final shells = await _host.remote.shells(sessionId);
            final previous = _prefs.preferredShell;
            path =
                shells.where((s) => s.path == previous).firstOrNull?.path ??
                shells.firstOrNull?.path;
          }
          if (_stopped) return;
          if (path != null) _prefs.rememberShell(path);
          await _create(environment, path);
        } else {
          throw _ViewError(TerminalViewIssue.missingTerminal);
        }
      } on Object catch (error) {
        _fail(error);
      } finally {
        _loading = null;
      }
    })();
  }

  bool get _stopped => _disposed || _closing != null;

  Future<void> _create(TerminalEnvironment environment, String? path) {
    _patch(phase: TerminalPhase.creating, error: null, issue: null);
    final creation = (() async {
      try {
        final info = await _host.remote.create(
          sessionId,
          TerminalCreateRequest(
            id: id,
            shellPath: path,
            cols: environment.maxCols < 80 ? environment.maxCols : 80,
            rows: environment.maxRows < 24 ? environment.maxRows : 24,
          ),
        );
        if (!_disposed) {
          _inventory.update(info);
          _adopt(info);
        }
      } on Object catch (error) {
        _fail(error);
      } finally {
        _creation = null;
      }
    })();
    _creation = creation;
    return creation;
  }

  void _adopt(WebTerminalInfo info) {
    _createWhenMissing = false;
    _patch(info: info, title: info.title);
    final hold = _hold ??= TerminalWindowHold(_host, sessionId, id);
    _generations ??= _host.generations.listen(_onGeneration);
    unawaited(
      hold.ready().then(
        (_) {
          if (_mounted && !_stopped) connect();
        },
        onError: (Object error) {
          if (!_stopped) _fail(error);
        },
      ),
    );
  }

  /// A new connection generation: follow the screen again (the old attachment
  /// ended with the old generation, and nothing it had queued is replayed).
  void _onGeneration(ConnectionGeneration? generation) {
    if (generation == null || !_mounted || _stopped) return;
    final current = state.value;
    if (current.info == null) return;
    if (current.phase == TerminalPhase.failed ||
        current.phase == TerminalPhase.closed ||
        current.phase == TerminalPhase.closing) {
      return;
    }
    final token = ++_connectToken;
    final hold = _hold;
    if (hold == null) {
      connect();
      return;
    }
    unawaited(
      hold.ready().then(
        (_) {
          if (token == _connectToken && _mounted && !_stopped) connect();
        },
        onError: (Object error) {
          if (!_stopped) _fail(error);
        },
      ),
    );
  }

  /// Reattach with a fresh screen and regain input control.
  void connect() {
    final info = state.value.info;
    if (info == null || !_mounted || _stopped) return;
    _detach();
    _connectToken++;
    final _Attachment attachment;
    try {
      attachment = _Attachment(_host.attach(sessionId, info.id));
    } on Object catch (error) {
      // No live connection to open the stream on.
      _fail(error);
      return;
    }
    _attachment = attachment;
    _patch(
      phase: TerminalPhase.connecting,
      writable: false,
      error: null,
      issue: null,
      render: null,
    );
    attachment.subscription = attachment.stream.frames.listen(
      (frame) => _onStreamFrame(attachment, frame),
      onError: (Object error) {
        if (_attachment == attachment) _onEnded(attachment, error);
      },
    );
  }

  void _onStreamFrame(_Attachment attachment, GenerationFrame frame) {
    if (_attachment != attachment) return;
    switch (frame) {
      case StreamOpened():
        attachment.expectSnapshot = true;
      case StreamItem(:final value):
        _onItem(attachment, value);
      case StreamEnded(:final error):
        _onEnded(attachment, error);
    }
  }

  void _onItem(_Attachment attachment, Object? raw) {
    final TerminalFrame frame;
    try {
      frame = TerminalFrame.fromJson(raw);
    } on FormatException {
      _failInput(
        _ViewError(
          TerminalViewIssue.invalidOutput,
          'Terminal output frame is not valid',
        ),
      );
      return;
    }
    try {
      if (attachment.expectSnapshot) {
        if (frame is! TerminalFrameSnapshot) {
          throw _ViewError(
            TerminalViewIssue.invalidOutput,
            'Terminal output generation is missing its screen snapshot',
          );
        }
        attachment
          ..expectSnapshot = false
          ..outputSequence = frame.sequence
          ..window = frame.inputWindow;
      } else if (frame is TerminalFrameOutput) {
        if (frame.sequence != attachment.outputSequence + 1) {
          throw _ViewError(
            TerminalViewIssue.invalidOutput,
            'Terminal output sequence has a gap',
          );
        }
        attachment.outputSequence = frame.sequence;
      } else if (frame is TerminalFrameSnapshot) {
        throw _ViewError(
          TerminalViewIssue.invalidOutput,
          'Unexpected terminal screen snapshot',
        );
      } else if (frame is TerminalFrameUnrecognized) {
        return;
      }
    } on _ViewError catch (error) {
      _failInput(error);
      return;
    }
    if (frame is TerminalFrameAck) {
      _acknowledgeInput(attachment, frame);
      return;
    }
    attachment.inbox.add(frame);
    unawaited(_drain(attachment));
  }

  void _acknowledgeInput(_Attachment attachment, TerminalFrameAck frame) {
    final pending = attachment.pending[frame.sequence];
    if (frame.sequence != attachment.acknowledged + 1 || pending == null) {
      _failInput(
        _ViewError(
          TerminalViewIssue.invalidOutput,
          'Terminal input acknowledgement is out of order',
        ),
      );
      return;
    }
    attachment
      ..acknowledged = frame.sequence
      ..bytes -= pending.inputBytes
      ..bufferedBytes -= pending.frameBytes
      ..inFlightBytes -= pending.frameBytes
      ..pending.remove(frame.sequence);
    if (frame.refusal != null) _patch(writable: false);
    _flushInput(attachment);
  }

  /// Publish the queued screen frames one at a time, each after the emulator
  /// acknowledged the previous one.
  Future<void> _drain(_Attachment attachment) async {
    if (attachment.draining) return;
    attachment.draining = true;
    try {
      while (attachment.inbox.isNotEmpty && _attachment == attachment) {
        final frame = attachment.inbox.removeFirst();
        switch (frame) {
          case TerminalFrameSnapshot(:final info, writable: final canWrite):
            _inventory.update(info);
            _patch(
              info: info,
              title: info.title,
              phase: TerminalPhase.connected,
              writable: info.state == WebTerminalInfoState.running && canWrite,
            );
          case TerminalFrameState(:final info, writable: final canWrite):
            _inventory.update(info);
            _patch(
              info: info,
              title: info.title,
              phase: TerminalPhase.connected,
              writable: info.state == WebTerminalInfoState.running && canWrite,
            );
          default:
            break;
        }
        if (frame is TerminalFrameState) continue;
        final revision = ++_revision;
        final done = Completer<void>();
        _pendingRender = done;
        _pendingRevision = revision;
        _patch(render: TerminalRenderFrame(revision, frame));
        await done.future;
      }
    } finally {
      attachment.draining = false;
    }
  }

  /// Release the next frame once the emulator has parsed this one.
  void acknowledge(int revision) {
    final pending = _pendingRender;
    if (pending == null || _pendingRevision != revision) return;
    _pendingRender = null;
    if (!pending.isCompleted) pending.complete();
  }

  /// Queue [data] within the raw UTF-8 and encoded-frame budgets, waiting for
  /// carrier capacity. Input is dropped (never replayed) while the view cannot
  /// write.
  void write(String data) {
    final current = state.value;
    final attachment = _attachment;
    if (!current.writable || current.info == null || attachment == null) {
      return;
    }
    if (data.isEmpty) return;
    final bytes = utf8.encode(data).length;
    if (attachment.bytes + bytes > (current.environment?.maxInputBytes ?? 0)) {
      _failInput(_ViewError(TerminalViewIssue.inputFull));
      return;
    }
    _send(
      attachment,
      TerminalInputWrite(sequence: attachment.sequence + 1, data: data),
      bytes,
    );
  }

  /// Resize the Host terminal; only the writable view may, and the command is
  /// ordered with keyboard input.
  void resize(int cols, int rows) {
    final current = state.value;
    final attachment = _attachment;
    if (!current.writable || current.info == null || attachment == null) {
      return;
    }
    if (current.info!.cols == cols && current.info!.rows == rows) return;
    final environment = current.environment;
    final c = environment == null || cols < environment.maxCols
        ? cols
        : environment.maxCols;
    final r = environment == null || rows < environment.maxRows
        ? rows
        : environment.maxRows;
    _send(
      attachment,
      TerminalInputResize(sequence: attachment.sequence + 1, cols: c, rows: r),
      0,
    );
  }

  void _send(_Attachment attachment, TerminalInput command, int bytes) {
    final frameBytes =
        utf8.encode(jsonEncode(command.toJson())).length +
        (attachment.window?.frameOverheadBytes.toInt() ?? 0);
    final window = attachment.window;
    if (attachment.bufferedBytes + frameBytes >
            (state.value.environment?.maxBufferedBytes ?? 0) ||
        (window != null && frameBytes > window.maxBytes)) {
      _failInput(_ViewError(TerminalViewIssue.inputFull));
      return;
    }
    attachment.queued.add(_Queued(command, _Cost(bytes, frameBytes)));
    attachment
      ..sequence = _sequenceOf(command)
      ..bytes += bytes
      ..bufferedBytes += frameBytes;
    _flushInput(attachment);
  }

  void _flushInput(_Attachment attachment) {
    while (_attachment == attachment &&
        !attachment.closed &&
        state.value.writable) {
      if (attachment.queued.isEmpty) return;
      final next = attachment.queued.first;
      final window = attachment.window;
      if (window != null &&
          attachment.inFlightBytes + next.cost.frameBytes > window.maxBytes) {
        return;
      }
      attachment.queued.removeFirst();
      try {
        attachment.stream.send(next.command);
      } on Object catch (error) {
        _failInput(error);
        return;
      }
      attachment.pending[_sequenceOf(next.command)] = next.cost;
      attachment.inFlightBytes += next.cost.frameBytes;
    }
  }

  void _failInput(Object error) {
    _fail(error);
    _detach();
  }

  /// Rename the Host terminal (the title every attached view shows).
  Future<void> rename(String title) async {
    final next = title.trim();
    if (next == state.value.title || _disposed) return;
    try {
      await _host.remote.rename(sessionId, id, next);
      if (_stopped) return;
      final current = state.value.info;
      if (current != null) {
        final renamed = WebTerminalInfo(
          id: current.id,
          title: next,
          shell: current.shell,
          cwd: current.cwd,
          cols: current.cols,
          rows: current.rows,
          state: current.state,
          exitCode: current.exitCode,
          error: current.error,
        );
        _inventory.update(renamed);
        _patch(info: renamed, title: next);
      } else {
        _patch(title: next);
      }
    } on Object catch (error) {
      _fail(error);
    }
  }

  /// End this view's process on the Host, independent of the screen. Failures
  /// leave the terminal open and rethrow, so the owner can retry.
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _patch(
      phase: TerminalPhase.closing,
      writable: false,
      error: null,
      issue: null,
    );
    _detach();
    // This window no longer holds the terminal, whatever the Host answers.
    _releaseHold();
    final done = (() async {
      // Even a refused or lost creation response may leave an allocation to close.
      await _creation;
      await _host.remote.close(sessionId, id);
      _inventory.remove(id);
      _detach();
      _patch(phase: TerminalPhase.closed, writable: false);
    })();
    _closing = done;
    return done.catchError((Object error) {
      _closing = null;
      _fail(error);
      throw error;
    });
  }

  /// Stop client work (unmount of the app or the connection): the Host
  /// terminal is left running.
  Future<void> dispose() async {
    _mounted = false;
    _disposed = true;
    _detach();
    _releaseHold();
    await _generations?.cancel();
    _generations = null;
    // A broadcast controller reports done once every listener left; a screen
    // that still listens must not hold the disposal back.
    unawaited(state.dispose());
  }

  void _releaseHold() {
    final hold = _hold;
    _hold = null;
    if (hold != null) unawaited(hold.dispose());
  }

  void _detach() {
    final previous = _attachment;
    _attachment = null;
    final pending = _pendingRender;
    _pendingRender = null;
    if (pending != null && !pending.isCompleted) pending.complete();
    if (previous != null) {
      previous.closed = true;
      previous.inbox.clear();
      unawaited(previous.subscription?.cancel());
    }
  }

  void _onEnded(_Attachment attachment, Object? error) {
    if (_attachment != attachment) return;
    _attachment = null;
    attachment.closed = true;
    unawaited(attachment.subscription?.cancel());
    if (error == null) {
      // The Host ended the stream: the exit state, or an attachment it dropped.
      if (state.value.info?.state == WebTerminalInfoState.exited) {
        _patch(phase: TerminalPhase.closed, writable: false);
      } else {
        _fail(_ViewError(TerminalViewIssue.attachmentEnded));
      }
      return;
    }
    if (error is CarrierLost || error is NotConnected) {
      _patch(phase: TerminalPhase.disconnected, writable: false);
      return;
    }
    if (state.value.info?.state == WebTerminalInfoState.exited) {
      _patch(phase: TerminalPhase.closed, writable: false);
    } else {
      _fail(error);
    }
  }

  void _patch({
    TerminalPhase? phase,
    Object? environment = _keep,
    Object? title = _keep,
    Object? info = _keep,
    bool? writable,
    Object? render = _keep,
    Object? error = _keep,
    Object? issue = _keep,
  }) {
    if (_disposed) return;
    state.set(
      state.value.copyWith(
        phase: phase,
        environment: environment,
        title: title,
        info: info,
        writable: writable,
        render: render,
        error: error,
        issue: issue,
      ),
    );
  }

  void _fail(Object error) {
    TerminalViewIssue? issue;
    if (error is _ViewError) {
      issue = error.issue;
    } else if (error is RemoteException) {
      issue = switch (error.code) {
        'terminal/limit-reached' => TerminalViewIssue.terminalLimit,
        'terminal/unavailable' => TerminalViewIssue.missingTerminal,
        _ => null,
      };
    }
    if (!_stopped && issue == TerminalViewIssue.missingTerminal) {
      _inventory.remove(id);
    }
    final disconnected = error is CarrierLost || error is NotConnected;
    _patch(
      phase: disconnected ? TerminalPhase.disconnected : TerminalPhase.failed,
      writable: false,
      issue: issue,
      error: error is RemoteException
          ? error.message
          : error is _ViewError
          ? error.message
          : describeTransportError(error).isEmpty
          ? error.toString()
          : describeTransportError(error),
    );
  }
}
