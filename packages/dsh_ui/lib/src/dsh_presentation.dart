import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_focus_presentation.dart';
import 'dsh_recipes.g.dart';
import 'dsh_shell_chrome.dart';
import 'dsh_snapped_box.dart';
import 'theme_access.dart';

/// Source Modal layer. Callers keep their own content profiles; the shared
/// layer owns viewport fitting, mask, entry motion and keyboard ownership.
Future<T?> showDshDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? label,
  double width = DshModalRecipe.defaultWidth,
  double? height,
  bool dismissible = true,
  FocusNode? restoreFocus,
}) async {
  final theme = context.dsh;
  final frame = FrameInsetsScope.of(context);
  final owner = ModalRoute.of(context);
  final duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : theme.duration(DshModalRecipe.animationDurationToken);
  try {
    return await showGeneralDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierLabel: label ?? '',
      // Paint the source mask inside the page so native caption paint can be
      // excluded while the entire modal route continues to block input.
      barrierColor: const Color(0x00000000),
      transitionDuration: duration,
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation.drive(
          CurveTween(
            curve: const Cubic(
              DshModalRecipe.curveX1,
              DshModalRecipe.curveY1,
              DshModalRecipe.curveX2,
              DshModalRecipe.curveY2,
            ),
          ),
        ),
        child: child,
      ),
      pageBuilder: (dialogContext, _, _) => FrameInsetsScope(
        insets: frame,
        child: _DialogLayer(
          label: label,
          width: width,
          height: height,
          dismissible: dismissible,
          builder: builder,
        ),
      ),
    );
  } finally {
    if (context.mounted &&
        (owner == null || owner.isCurrent) &&
        restoreFocus?.context?.mounted == true &&
        restoreFocus!.canRequestFocus) {
      dshFocusWithoutRing(restoreFocus);
    }
  }
}

class _DialogLayer extends StatefulWidget {
  const _DialogLayer({
    required this.builder,
    required this.label,
    required this.width,
    required this.height,
    required this.dismissible,
  });
  final WidgetBuilder builder;
  final String? label;
  final double width;
  final double? height;
  final bool dismissible;
  @override
  State<_DialogLayer> createState() => _DialogLayerState();
}

class _DialogLayerState extends State<_DialogLayer> {
  TextEditingController? _editor;
  bool _wasComposing = false, _compositionEnded = false;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_syncEditor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      // Honor a caller's explicit autofocus before applying Modal's first
      // focusable-control fallback.
      FocusManager.instance.applyFocusChangesIfNeeded();
      final scope = FocusScope.of(context);
      if (scope.focusedChild == null) {
        scope.nextFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        final target = FocusManager.instance.primaryFocus;
        if (target != null && scope.hasFocus) dshFocusWithoutRing(target);
      }
      _syncEditor();
    });
  }

  TextEditingController? _focusedEditor() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return null;
    EditableText? editor = focused.widget is EditableText
        ? focused.widget as EditableText
        : null;
    focused.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        editor = element.widget as EditableText;
        return false;
      }
      return true;
    });
    return editor?.controller;
  }

  bool get _composing =>
      _editor?.value.composing.isValid == true &&
      _editor?.value.composing.isCollapsed == false;

  void _compositionChanged() {
    final active = _composing;
    if (_wasComposing && !active) _compositionEnded = true;
    _wasComposing = active;
  }

  void _syncEditor() {
    if (!mounted) return;
    final next = ModalRoute.of(context)?.isCurrent == true
        ? _focusedEditor()
        : null;
    if (identical(next, _editor)) return;
    _editor?.removeListener(_compositionChanged);
    _editor = next;
    _wasComposing = _composing;
    _compositionEnded = false;
    _editor?.addListener(_compositionChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncEditor);
    _editor?.removeListener(_compositionChanged);
    super.dispose();
  }

  KeyEventResult _guard(FocusNode _, KeyEvent event) {
    _syncEditor();
    if (event is KeyUpEvent) {
      _compositionEnded = false;
      return KeyEventResult.ignored;
    }
    final composing = _composing || _compositionEnded;
    _compositionEnded = false;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    return event is KeyRepeatEvent || composing
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final frame = FrameInsetsScope.of(context);
    final margin = math.max(DshModalRecipe.rootMargin, frame.overlayTop);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _guard,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x00000000)),
          Positioned.fill(
            top: frame.chromeTop,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.dismissible
                  ? () => Navigator.of(context).pop()
                  : null,
              child: ColoredBox(color: theme.color(DshModalRecipe.maskToken)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: DshModalRecipe.rootHorizontalMargin,
                    vertical: margin,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      role: SemanticsRole.dialog,
                      label: widget.label,
                      child: DshDialogFrame(
                        width: widget.width,
                        height: widget.height,
                        child: widget.builder(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Canonical Modal card. Content-specific spacing stays with a generated
/// profile, allowing existing headless callers to migrate independently.
class DshDialogFrame extends StatelessWidget {
  const DshDialogFrame({
    super.key,
    required this.width,
    this.height,
    required this.child,
  });
  final double width;
  final double? height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final radius = theme.number(DshModalRecipe.radiusToken);
    final color = theme.color(DshModalRecipe.backgroundToken);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.hasBoundedWidth
            ? width.clamp(0.0, constraints.maxWidth)
            : width;
        final h = height == null
            ? null
            : constraints.hasBoundedHeight
            ? height!.clamp(0.0, constraints.maxHeight)
            : height!;
        return SizedBox(
          width: w,
          height: h,
          child: DshDecoratedBox(
            decoration: ShapeDecoration(
              shape: theme.cornerBorder(radius),
              color: color,
              shadows: theme.boxShadow(DshModalRecipe.elevationToken),
            ),
            child: ClipPath(
              clipper: ShapeBorderClipper(
                shape: DshCornerBorder(
                  radius: radius,
                  curvature: dshCornerCurvature(theme),
                ),
              ),
              child: DshSurface(
                color: color,
                child: Material(type: MaterialType.transparency, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}
