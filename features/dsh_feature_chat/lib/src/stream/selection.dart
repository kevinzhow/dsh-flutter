import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';

// Ported from raft-flutter `packages/raft_ui/lib/src/raft_selection_area.dart`:
// [SelectionArea] whose touch selection ends with the next touch elsewhere
// (Flutter keeps a touch selection and its handles until the same text is
// tapped again). Raft mounts one region per message body
// (`message_body.dart`, with `joinsAmbientSelection` for a host that already
// has one); here one region covers the list, as in dsh web. The Quote
// shortcut is Raft Web's and has no dsh counterpart.

/// A selection region that a touch outside clears; a mouse selection stays
/// until it is replaced (desktop behaviour).
class DshSelectionArea extends StatefulWidget {
  const DshSelectionArea({super.key, required this.child});
  final Widget child;

  @override
  State<DshSelectionArea> createState() => _DshSelectionAreaState();
}

class _DshSelectionAreaState extends State<DshSelectionArea> {
  BuildContext? _inside;

  SelectableRegionState? get _region => _inside?.mounted == true
      ? _inside!.findAncestorStateOfType<SelectableRegionState>()
      : null;

  void _outsidePress(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad) {
      return;
    }
    _region?.clearSelection();
  }

  @override
  Widget build(BuildContext context) => TapRegion(
    groupId: SelectableRegion,
    onTapOutside: _outsidePress,
    child: SelectionArea(
      child: Builder(
        builder: (context) {
          _inside = context;
          return widget.child;
        },
      ),
    ),
  );
}

/// Marks a subtree that already sits in one selection region (the desktop
/// timeline), so messages inside do not open their own.
class AmbientSelection extends InheritedWidget {
  const AmbientSelection({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientSelection>() != null;

  @override
  bool updateShouldNotify(AmbientSelection oldWidget) => false;
}

/// How the stream selects text: one region over the whole list, so a drag
/// (or, on a touch screen, a long press and its handles) runs across messages
/// like the browser's native selection on dsh web, and Ctrl/Cmd+C copies it.
/// Rows that scroll out of the built range drop out of the selection (the list
/// is lazy). A touch outside the region clears a touch selection, as a tap
/// elsewhere does in a browser.
class StreamSelection extends StatelessWidget {
  const StreamSelection({super.key, required this.child});
  final Widget child;

  /// The list-wide region around [child]. [wide] is kept for callers that
  /// still pass it; selection no longer depends on the width.
  static Widget list(Widget child, {bool wide = false}) =>
      DshSelectionArea(child: AmbientSelection(child: child));

  @override
  Widget build(BuildContext context) =>
      AmbientSelection.of(context) ? child : DshSelectionArea(child: child);
}
