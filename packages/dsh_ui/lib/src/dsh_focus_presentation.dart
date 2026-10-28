import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The source distinguishes browser focus-visible history from temporary
/// outline suppression during automatic modal entry and return.
class DshFocusPresentation {
  DshFocusPresentation._();
  static final instance = DshFocusPresentation._();
  final _states = <FocusNode, _FocusPresentationState>{};
  bool _keyboard = false;
  bool _pointerOwnsOutline = false;
  FocusNode? _keyFocusOrigin;

  /// The published global focus.css suppresses non-editable outlines while
  /// input-modality.ts says a pointer owns focus. This is distinct from the
  /// browser's retained :focus-visible history. Consumers opt in separately.
  bool get pointerOwnsOutline => _pointerOwnsOutline;

  void _setPointerOwnsOutline(bool value) {
    if (_pointerOwnsOutline == value) return;
    _pointerOwnsOutline = value;
    for (final state in _states.values.toList()) {
      state.notify();
    }
  }

  static final _navigation = {
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
  };

  void acquire(FocusNode node, VoidCallback listener) {
    if (_states.isEmpty) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
      HardwareKeyboard.instance.addHandler(_key);
    }
    final state = _states.putIfAbsent(node, () {
      final value = _FocusPresentationState(node, _keyboard);
      value.focusChanged = () {
        final focused = node.hasPrimaryFocus;
        if (focused == value.focused) return;
        value.focused = focused;
        value.visible = focused && _keyboard;
        if (focused && _keyFocusOrigin != null && _keyFocusOrigin != node) {
          _keyFocusOrigin = null;
          _setPointerOwnsOutline(false);
        }
        if (!focused) value.suppressed = false;
        value.notify();
      };
      node.addListener(value.focusChanged);
      return value;
    });
    state.listeners.add(listener);
  }

  void release(FocusNode node, VoidCallback listener) {
    final state = _states[node];
    if (state == null) return;
    state.listeners.remove(listener);
    if (state.listeners.isEmpty) {
      node.removeListener(state.focusChanged);
      _states.remove(node);
    }
    if (_states.isEmpty) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
      HardwareKeyboard.instance.removeHandler(_key);
    }
  }

  bool visible(FocusNode node) =>
      node.hasPrimaryFocus && (_states[node]?.visible ?? _keyboard);
  bool suppressed(FocusNode node) => _states[node]?.suppressed ?? false;

  void withoutRing(FocusNode node) {
    final state = _states[node];
    if (state != null) {
      state.suppressed = true;
      state.notify();
    }
    node.requestFocus();
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _keyboard = false;
      _keyFocusOrigin = null;
      _setPointerOwnsOutline(true);
    }
    // A click on an already keyboard-focused control retains :focus-visible.
    // A newly focused control receives the current input mode on focus change.
  }

  bool _key(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    _keyFocusOrigin = FocusManager.instance.primaryFocus;
    if (_navigation.contains(event.logicalKey) ||
        event.logicalKey == LogicalKeyboardKey.pageUp ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _setPointerOwnsOutline(false);
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    _keyboard = true;
    final state = _states[FocusManager.instance.primaryFocus];
    if (state != null) {
      final release =
          _navigation.contains(event.logicalKey) &&
          !keyboard.isControlPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isMetaPressed;
      final changed = !state.visible || (release && state.suppressed);
      state.visible = true;
      if (release) state.suppressed = false;
      if (changed) state.notify();
    }
    return false;
  }
}

class _FocusPresentationState {
  _FocusPresentationState(this.node, bool keyboard)
    : focused = node.hasPrimaryFocus,
      visible = node.hasPrimaryFocus && keyboard;
  final FocusNode node;
  bool focused, visible, suppressed = false;
  late VoidCallback focusChanged;
  final listeners = <VoidCallback>{};
  void notify() {
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

bool dshHasVisibleFocus(FocusNode node) =>
    DshFocusPresentation.instance.visible(node);
void dshFocusWithoutRing(FocusNode node) =>
    DshFocusPresentation.instance.withoutRing(node);
