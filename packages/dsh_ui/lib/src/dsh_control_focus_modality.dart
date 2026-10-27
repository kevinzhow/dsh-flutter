import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// DSH's focus-visible styling remains pointer-owned until a navigation key,
// or a key followed by focus moving to a different control. Ordinary keys on
// the same control do not bring the outline back after a pointer click.
class DshControlFocusModality extends ChangeNotifier {
  static final DshControlFocusModality instance = DshControlFocusModality();
  static final _navigation = {
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };
  int _users = 0;
  bool pointerOwnsFocus = false;
  FocusNode? _keyOrigin;

  void acquire(VoidCallback listener) {
    addListener(listener);
    if (_users++ != 0) return;
    pointerOwnsFocus = false;
    _keyOrigin = null;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_onFocusChange);
  }

  void release(VoidCallback listener) {
    removeListener(listener);
    if (--_users != 0) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_onFocusChange);
  }

  void _setPointerOwnsFocus(bool value) {
    if (pointerOwnsFocus == value) return;
    pointerOwnsFocus = value;
    notifyListeners();
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    _keyOrigin = null;
    _setPointerOwnsFocus(true);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    _keyOrigin = FocusManager.instance.primaryFocus;
    if (_navigation.contains(event.logicalKey)) _setPointerOwnsFocus(false);
    return false;
  }

  void _onFocusChange() {
    if (_keyOrigin == null ||
        _keyOrigin == FocusManager.instance.primaryFocus) {
      return;
    }
    _keyOrigin = null;
    _setPointerOwnsFocus(false);
  }
}
