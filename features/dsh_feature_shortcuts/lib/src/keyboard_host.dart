/// Turns platform key events into shortcut gestures (dsh `client/dom.ts` and
/// `native.ts`) and dispatches them through the service.
///
/// Windows and macOS desktop bindings take priority over local handlers and
/// modal controls (dsh intercepts them natively), so they run in the hardware
/// keyboard handler, before any widget sees the key. Other environments
/// dispatch after the focused widgets had their say, from a root focus
/// handler, and respect the command's declared regions and modals.
library;

import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'key_codes.dart';

/// Wraps the app and feeds the [service] its keyboard input.
class ShortcutKeyboardHost extends StatefulWidget {
  const ShortcutKeyboardHost({
    super.key,
    required this.service,
    required this.child,
    this.enabled = true,
  });

  final ShortcutService service;
  final Widget child;

  /// False while a recorder owns the keyboard.
  final bool enabled;

  @override
  State<ShortcutKeyboardHost> createState() => _ShortcutKeyboardHostState();
}

class _ShortcutKeyboardHostState extends State<ShortcutKeyboardHost> {
  final Set<String> _held = {};
  final FocusNode _root = FocusNode(
    debugLabel: 'shortcut-host',
    skipTraversal: true,
  );

  ShortcutService get service => widget.service;

  bool get _priority =>
      service.runtime == ShortcutRuntime.desktop &&
      (service.platform == ShortcutPlatform.windows ||
          service.platform == ShortcutPlatform.macos);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_hardware);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_hardware);
    _root.dispose();
    super.dispose();
  }

  bool _hardware(KeyEvent event) {
    _track(event);
    return _priority && _dispatch(event);
  }

  KeyEventResult _local(FocusNode node, KeyEvent event) {
    if (_priority) return KeyEventResult.ignored;
    return _dispatch(event) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _track(KeyEvent event) {
    final code = domCodeOf(event.physicalKey);
    if (code == null || isModifierCode(code)) return;
    if (event is KeyUpEvent) {
      _held.remove(code);
    } else {
      _held.add(code);
    }
  }

  bool _dispatch(KeyEvent event) {
    if (!widget.enabled ||
        event is KeyUpEvent ||
        service.modals.top == 'shortcut-edit') {
      return false;
    }
    final code = domCodeOf(event.physicalKey);
    if (code == null || isModifierCode(code)) return false;
    final kb = HardwareKeyboard.instance;
    final desktopChords = _priority;
    final others = _held.where((c) => c != code).toList();
    final gesture = ShortcutGesture(
      code: code,
      secondCode: desktopChords && others.length == 1 ? others.first : null,
      control: kb.isControlPressed,
      alt: kb.isAltPressed,
      shift: kb.isShiftPressed,
      meta: kb.isMetaPressed,
      repeat: event is KeyRepeatEvent,
      // AltGraph composes characters on layouts that have it.
      composing: kb.logicalKeysPressed.contains(LogicalKeyboardKey.altGraph),
    );
    var consumed = false;
    final result = service.dispatch(gesture, _context(), () => consumed = true);
    return consumed || result is DispatchHandled;
  }

  ShortcutContext _context() {
    final focus = FocusManager.instance.primaryFocus;
    final editable =
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    return ShortcutContext(
      region: editable ? ShortcutRegion.editable : ShortcutRegion.page,
      modal: service.modals.top,
      target: focus?.context,
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _root,
    // Focused while nothing else is, so that a key pressed on an empty page
    // still reaches the dispatch; a focused descendant sends its keys up here.
    autofocus: true,
    skipTraversal: true,
    onKeyEvent: _local,
    child: widget.child,
  );
}

/// Whether the host platform is a desktop whose window the shell draws for.
bool get isDesktopPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// The shortcut platform of this device.
ShortcutPlatform shortcutPlatformOf(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.macOS || TargetPlatform.iOS => ShortcutPlatform.macos,
      TargetPlatform.windows => ShortcutPlatform.windows,
      _ => ShortcutPlatform.linux,
    };
