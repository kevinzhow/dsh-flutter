import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class WorkspaceDragItem {
  const WorkspaceDragItem(this.id, this.account);
  final String id, account;
}

/// One gesture commits at most once, including a release outside the list
/// after the last compatible insertion marker (the browser's dragend rule).
class WorkspaceDragState {
  VoidCallback? lastDrop;
  bool committed = false;
  Offset anchor = Offset.zero;
  void Function(bool active)? onActive;
  void begin() {
    onActive?.call(true);
    lastDrop = null;
    committed = false;
  }

  void commit() {
    if (committed) return;
    committed = true;
    onActive?.call(false);
    lastDrop?.call();
    lastDrop = null;
  }
}

class WorkspaceReorderRow extends StatefulWidget {
  const WorkspaceReorderRow({
    super.key,
    required this.item,
    required this.state,
    required this.onDrop,
    required this.child,
    this.draggable = true,
    this.afterOnly = false,
    this.target = true,
  });
  final WorkspaceDragItem item;
  final WorkspaceDragState state;
  final void Function(String sourceId, bool after) onDrop;
  final Widget child;
  final bool draggable, afterOnly, target;
  @override
  State<WorkspaceReorderRow> createState() => _WorkspaceReorderRowState();
}

class _WorkspaceReorderRowState extends State<WorkspaceReorderRow> {
  bool? after;
  bool get pointer =>
      RendererBinding.instance.mouseTracker.mouseIsConnected ||
      switch (defaultTargetPlatform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      };
  void marker(DragTargetDetails<WorkspaceDragItem> details) {
    final box = context.findRenderObject()! as RenderBox;
    final half =
        widget.afterOnly ||
        box.globalToLocal(details.offset + widget.state.anchor).dy >=
            box.size.height / 2;
    if (after != half) setState(() => after = half);
    widget.state.lastDrop = () {
      if (mounted) widget.onDrop(details.data.id, half);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!pointer) return widget.child;
    Widget row = widget.child;
    if (widget.draggable) {
      row = Draggable<WorkspaceDragItem>(
        data: widget.item,
        dragAnchorStrategy: (_, sourceContext, position) {
          final box = sourceContext.findRenderObject()! as RenderBox;
          return widget.state.anchor = box.globalToLocal(position);
        },
        axis: Axis.vertical,
        maxSimultaneousDrags: 1,
        onDragStarted: widget.state.begin,
        onDragEnd: (_) => widget.state.commit(),
        feedback: InheritedTheme.captureAll(
          context,
          SizedBox(
            width: switch (context.findRenderObject()) {
              final RenderBox box when box.hasSize => box.size.width,
              _ => 280.0,
            },
            child: Opacity(opacity: .8, child: widget.child),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: widget.child),
        child: row,
      );
    }
    if (!widget.target) return row;
    return DragTarget<WorkspaceDragItem>(
      onWillAcceptWithDetails: (d) =>
          d.data.account == widget.item.account && d.data.id != widget.item.id,
      onMove: marker,
      onLeave: (_) {
        if (mounted) setState(() => after = null);
      },
      onAcceptWithDetails: (d) {
        marker(d);
        widget.state.commit();
        setState(() => after = null);
      },
      builder: (_, _, _) => Stack(
        children: [
          row,
          if (after != null)
            Positioned(
              left: 0,
              right: 0,
              top: after! ? null : 0,
              bottom: after! ? 0 : null,
              child: SizedBox(
                height: 2,
                child: ColoredBox(
                  color: context.dsh.color(
                    '--dsw-alias-state-business-primary',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
