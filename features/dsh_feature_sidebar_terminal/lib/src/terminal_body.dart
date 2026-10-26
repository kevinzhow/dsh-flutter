import 'dart:async';

import 'package:dsh_client/generated_terminal.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart' as xterm;

import 'terminal_keys.dart';
import 'terminal_theme.dart';

/// The view of a terminal tab: created with the shell the guide chose, found
/// again by every part of the tab (body, title) under the tab's identity.
TerminalView terminalViewOf(ClientTerminals terminals, SidebarTabOwner owner) {
  final shell = owner.params['shellPath'], known = owner.params['terminalId'];
  final view = terminals.view(
    owner.session.sessionId,
    owner.id,
    terminalId: known is String ? known : null,
    shellPath: shell is String ? shell : null,
  );
  final actions = owner.actions;
  if (actions is SidebarTabBindingActions && known != view.id) {
    // Providers can be constructed by a slot during build. Report the stable
    // identity after that build, without publishing Host work or changing it.
    scheduleMicrotask(
      () => actions.rememberBinding(owner.id, {'terminalId': view.id}),
    );
  }
  return view;
}

/// What the strip above the screen says and offers for one view state (dsh
/// `TerminalBody`): the status line, whether the view is read-only (offering to
/// take control), whether a reconnect or retry is offered, and whether the
/// terminal has ended (offering a new one).
class TerminalStatus {
  const TerminalStatus({
    this.text,
    this.textParams = const {},
    this.readOnly = false,
    this.retry = false,
    this.reconnect = false,
    this.ended = false,
    this.error,
  });

  /// The `sidebarTerminal` key of the status line, if any.
  final String? text;
  final Map<String, Object?> textParams;
  final bool readOnly;

  /// Offer the retry that lists the environment again (nothing is attached).
  final bool retry;

  /// Offer a reconnect of the known terminal.
  final bool reconnect;
  final bool ended;

  /// The failure text shown under the screen, or its issue key.
  final ({String? key, String? message})? error;

  bool get showsStrip => text != null || retry || reconnect || readOnly;
}

/// The strip and error line of [state], as dsh's `TerminalBody` derives them.
TerminalStatus terminalStatusOf(TerminalViewState state) {
  final info = state.info;
  final phase = state.phase;
  ({String? key, String? message})? error;
  if (phase != TerminalPhase.disconnected) {
    if (state.issue != null) {
      error = (key: state.issue!.name, message: null);
    } else {
      final message = state.error ?? info?.error;
      if (message != null) error = (key: null, message: message);
    }
  }
  String? text;
  Map<String, Object?> params = const {};
  if (phase == TerminalPhase.idle || phase == TerminalPhase.loading) {
    text = 'loading';
  } else if (phase == TerminalPhase.creating ||
      phase == TerminalPhase.connecting ||
      phase == TerminalPhase.disconnected) {
    text = phase.name;
  } else if (info?.state == WebTerminalInfoState.exited) {
    text = 'exited';
    params = {'code': '${info!.exitCode ?? '—'}'};
  } else if (info?.state == WebTerminalInfoState.failed) {
    text = 'unavailable';
  } else if (phase == TerminalPhase.closed) {
    text = 'closed';
  }
  final ended =
      info?.state == WebTerminalInfoState.exited ||
      phase == TerminalPhase.closed;
  final canRetry =
      !ended &&
      (phase == TerminalPhase.failed || phase == TerminalPhase.disconnected);
  return TerminalStatus(
    text: text,
    textParams: params,
    readOnly:
        phase == TerminalPhase.connected &&
        info?.state == WebTerminalInfoState.running &&
        !state.writable,
    retry: canRetry && info == null,
    reconnect: canRetry && info != null,
    ended: ended,
    error: error,
  );
}

/// The terminal tab's body (dsh `ui-sidebar-terminal` `TerminalBody`): the
/// emulator over the Host terminal's screen, the status strip, and on phones
/// the key bar. It owns the emulator for as long as it is mounted; the process
/// and its view live on in [ClientTerminals].
class TerminalBody extends StatefulWidget {
  const TerminalBody({
    super.key,
    required this.owner,
    required this.terminals,
    required this.i18n,
  });

  final SidebarTabOwner owner;
  final ClientTerminals terminals;
  final DshI18n i18n;

  @override
  State<TerminalBody> createState() => _TerminalBodyState();
}

class _TerminalBodyState extends State<TerminalBody> {
  late TerminalView _view;
  void Function()? _detach;
  StreamSubscription<TerminalViewState>? _sub;
  xterm.Terminal? _terminal;
  final FocusNode _focus = FocusNode(debugLabel: 'terminal');
  final xterm.TerminalController _controller = xterm.TerminalController();
  int _lastRevision = 0;
  bool _applying = false;
  bool _ctrl = false;
  bool _wasWritable = false;

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('sidebarTerminal', key, params: params);

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _view = terminalViewOf(widget.terminals, widget.owner);
    _sub = _view.state.changes.listen(_onState);
    // Starting the view publishes state the tab's title listens to; that must
    // not happen while this frame is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _detach = _view.mount();
    });
  }

  @override
  void didUpdateWidget(TerminalBody old) {
    super.didUpdateWidget(old);
    if (old.owner.visible != widget.owner.visible) _fit();
  }

  @override
  void dispose() {
    _detach?.call();
    unawaited(_sub?.cancel());
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  xterm.Terminal _createTerminal() {
    final environment = _view.snapshot.environment;
    final terminal = xterm.Terminal(
      maxLines:
          (environment?.scrollback ?? 1000) + (environment?.maxRows ?? 200),
    );
    terminal
      ..onOutput = _onOutput
      ..onResize = (cols, rows, _, _) => _onResize(cols, rows);
    return terminal;
  }

  void _onOutput(String data) {
    var out = data;
    if (_ctrl) {
      final code = controlCharacterFor(data);
      if (code != null) {
        out = code;
        _ctrl = false;
        if (mounted) setState(() {});
      }
    }
    _view.write(out);
  }

  void _onResize(int cols, int rows) {
    if (_applying || !widget.owner.visible) return;
    _view.resize(cols, rows);
  }

  /// The Host grid follows the visible, writable view's size.
  void _fit() {
    final terminal = _terminal;
    if (terminal == null || !widget.owner.visible) return;
    if (_view.snapshot.writable) {
      _view.resize(terminal.viewWidth, terminal.viewHeight);
    }
  }

  void _onState(TerminalViewState state) {
    final render = state.render;
    if (render != null && render.revision > _lastRevision) {
      _lastRevision = render.revision;
      _apply(render);
    }
    final writable = state.writable;
    if (writable && !_wasWritable) {
      if (widget.owner.visible) _focus.requestFocus();
      scheduleMicrotask(_fit);
    }
    if (!writable && _ctrl) _ctrl = false;
    _wasWritable = writable;
    if (mounted) setState(() {});
  }

  void _apply(TerminalRenderFrame render) {
    final frame = render.frame;
    _applying = true;
    try {
      if (frame is TerminalFrameSnapshot) {
        final terminal = _terminal ??= _createTerminal();
        // The Host sends the whole screen: start over at its size, then draw.
        terminal.write('\x1bc');
        terminal.resize(frame.info.cols, frame.info.rows);
        terminal.write(frame.screen);
      } else if (frame is TerminalFrameOutput) {
        _terminal?.write(frame.data);
      }
    } finally {
      _applying = false;
    }
    _view.acknowledge(render.revision);
  }

  void _press(TerminalBarKey key) {
    final terminal = _terminal;
    if (terminal == null || !_view.snapshot.writable) return;
    switch (key) {
      case TerminalBarKey.ctrl:
        setState(() => _ctrl = !_ctrl);
      case TerminalBarKey.escape:
        terminal.keyInput(xterm.TerminalKey.escape);
      case TerminalBarKey.tab:
        terminal.keyInput(xterm.TerminalKey.tab, ctrl: _ctrl);
      case TerminalBarKey.up:
        terminal.keyInput(xterm.TerminalKey.arrowUp, ctrl: _ctrl);
      case TerminalBarKey.down:
        terminal.keyInput(xterm.TerminalKey.arrowDown, ctrl: _ctrl);
      case TerminalBarKey.left:
        terminal.keyInput(xterm.TerminalKey.arrowLeft, ctrl: _ctrl);
      case TerminalBarKey.right:
        terminal.keyInput(xterm.TerminalKey.arrowRight, ctrl: _ctrl);
    }
    if (key != TerminalBarKey.ctrl && key != TerminalBarKey.escape && _ctrl) {
      setState(() => _ctrl = false);
    }
    if (_focus.canRequestFocus && !_focus.hasFocus) _focus.requestFocus();
  }

  void _newTerminal() =>
      widget.owner.actions.openTab('terminal', replaceTabId: widget.owner.id);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final state = _view.snapshot;
    final label = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: theme.labelPrimary);
    final base = DefaultTextStyle(
      style: label,
      child: ColoredBox(color: theme.bgBase, child: _content(context, state)),
    );
    return Padding(
      key: const ValueKey('terminal-body'),
      padding: const EdgeInsets.only(top: 8),
      child: base,
    );
  }

  Widget _content(BuildContext context, TerminalViewState state) {
    final theme = context.dsh;
    if (state.issue == TerminalViewIssue.missingTerminal) {
      return _Missing(
        message: _t('missingTerminal'),
        action: _t('new'),
        onNew: _newTerminal,
      );
    }
    final status = terminalStatusOf(state);
    final terminal = _terminal;
    final phoneKeys =
        MediaQuery.sizeOf(context).width < sidebarInlineMinWindowWidth;
    final strip = status.showsStrip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (strip)
          _Strip(
            key: const ValueKey('terminal-status'),
            children: [
              if (status.text != null)
                DshChromeText(
                  _t(status.text!, status.textParams),
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(color: theme.labelPrimary),
                ),
              if (status.readOnly) ...[
                DshChromeText(
                  _t('readonly'),
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(color: theme.labelPrimary),
                ),
                DshButton(
                  key: const ValueKey('terminal-take-control'),
                  variant: DshButtonVariant.outline,
                  size: DshButtonSize.sm,
                  onPressed: _view.connect,
                  child: DshChromeText(_t('control')),
                ),
              ],
              if (status.retry)
                DshButton(
                  key: const ValueKey('terminal-retry'),
                  variant: DshButtonVariant.outline,
                  size: DshButtonSize.sm,
                  onPressed: () => unawaited(_view.refresh()),
                  child: DshChromeText(
                    _t(
                      state.phase == TerminalPhase.disconnected
                          ? 'reconnect'
                          : 'retry',
                    ),
                  ),
                ),
              if (status.reconnect)
                DshButton(
                  key: const ValueKey('terminal-reconnect'),
                  variant: DshButtonVariant.outline,
                  size: DshButtonSize.sm,
                  onPressed: _view.connect,
                  child: DshChromeText(_t('reconnect')),
                ),
              if (status.ended)
                DshButton(
                  key: const ValueKey('terminal-new'),
                  variant: DshButtonVariant.primary,
                  size: DshButtonSize.sm,
                  icon: DshIcon(
                    DshIcons.plus,
                    size: 12,
                    color: theme.labelPrimaryForeground,
                  ),
                  onPressed: _newTerminal,
                  child: DshChromeText(_t('new')),
                ),
            ],
          ),
        if (state.info != null && terminal != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: xterm.TerminalView(
                terminal,
                key: const ValueKey('terminal-screen'),
                controller: _controller,
                focusNode: _focus,
                theme: terminalThemeOf(theme),
                textStyle: terminalStyleOf(theme),
                backgroundOpacity: 1,
                readOnly: !state.writable,
                autofocus: false,
                keyboardType: TextInputType.visiblePassword,
                deleteDetection: true,
              ),
            ),
          ),
        if (status.error != null)
          _ErrorLine(
            key: const ValueKey('terminal-error'),
            text: _t('failed', {
              'message': status.error!.key != null
                  ? _t(status.error!.key!)
                  : status.error!.message,
            }),
          ),
        if (phoneKeys && state.writable)
          TerminalKeyBar(i18n: widget.i18n, ctrlArmed: _ctrl, onKey: _press),
      ],
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // dsh's sheet paints these with `--dsw-alias-bg-l2`, a token the theme
    // contract does not define, so the strip has no fill of its own.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Semantics(
        liveRegion: true,
        child: DshChromeText(
          text,
          style: theme
              .textStyle('--dsw-font-xs-13')
              .copyWith(color: theme.labelPrimary),
        ),
      ),
    );
  }
}

/// A terminal that no longer exists on the Host: the glyph, the message and a
/// button for a new terminal in its place.
class _Missing extends StatelessWidget {
  const _Missing({
    required this.message,
    required this.action,
    required this.onNew,
  });

  final String message;
  final String action;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Center(
      key: const ValueKey('terminal-missing'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DshTerminalTile(size: 36),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 28 * 7.5),
              child: Semantics(
                liveRegion: true,
                child: DshChromeText(
                  message,
                  textAlign: TextAlign.center,
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(color: theme.labelPrimary, height: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DshButton(
              key: const ValueKey('terminal-new'),
              variant: DshButtonVariant.primary,
              icon: DshIcon(
                DshIcons.plus,
                size: 12,
                color: theme.labelPrimaryForeground,
              ),
              onPressed: onNew,
              child: DshChromeText(action),
            ),
          ],
        ),
      ),
    );
  }
}
