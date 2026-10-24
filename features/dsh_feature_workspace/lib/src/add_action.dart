import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'workspace_picker.dart';

/// The add-workspace action of the session list (dsh `WorkspaceBrowser`'s
/// header button): a project-add glyph that raises the directory flow, and on
/// an adopted directory opens a session in that workspace. It hides when the
/// composition has no directory picker (dsh: a dead button is worse than none).
class WorkspaceAddAction extends StatefulWidget {
  const WorkspaceAddAction({
    super.key,
    required this.owner,
    required this.services,
    required this.slots,
    required this.i18n,
    this.box,
    this.iconSize = 18,
    this.inkToken,
    this.requests,
  });

  /// The button's edge (default: the phone's touch target). The desktop
  /// sidebar header uses dsh's 28px control with a hover fill.
  final double? box;
  final double iconSize;

  /// Colour token of the glyph (default: the primary label).
  final String? inkToken;

  /// Counts requests to open the flow without a pointer (the add-workspace
  /// command): every increase opens it, like a press on the button.
  final ValueListenable<int>? requests;

  final SidebarWorkspacesOwner owner;
  final WorkspaceServices services;
  final SlotRegistry slots;
  final DshI18n i18n;

  @override
  State<WorkspaceAddAction> createState() => _WorkspaceAddActionState();
}

class _WorkspaceAddActionState extends State<WorkspaceAddAction> {
  final LayerLink _link = LayerLink();
  StreamSubscription<String>? _sub;
  bool _open = false;
  bool _busy = false;
  bool _hover = false;
  int _seen = 0;

  Slot<DirectoryFlowOwner, Widget> get _flow => DshSlots
      .sidebarWorkspacesDirectoryFlow
      .typed<DirectoryFlowOwner, Widget>();

  @override
  void initState() {
    super.initState();
    _sub = widget.slots.changes.listen((name) {
      if (name == _flow.name && mounted) setState(() {});
    });
    _seen = widget.requests?.value ?? 0;
    widget.requests?.addListener(_requested);
  }

  void _requested() {
    final n = widget.requests!.value;
    if (n == _seen) return;
    _seen = n;
    if (mounted && _available && !_busy) setState(() => _open = true);
  }

  @override
  void dispose() {
    widget.requests?.removeListener(_requested);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  bool get _available =>
      widget.slots.entries(_flow as Slot<Object?, Object?>).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final label = widget.i18n.t('workspace', 'workspace.add');
    final available = _available;
    final stack = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (available)
          CompositedTransformTarget(
            link: _link,
            child: Semantics(
              button: true,
              enabled: !_busy,
              label: label,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('workspace-add'),
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : () => setState(() => _open = true),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hover = true),
                  onExit: (_) => setState(() => _hover = false),
                  cursor: SystemMouseCursors.click,
                  child: DshContainer(
                    width: widget.box ?? DshSpace.touch,
                    height: widget.box ?? DshSpace.touch,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.box != null && _hover && !_busy
                          ? theme.interactiveBgHover
                          : null,
                      borderRadius: BorderRadius.circular(theme.radiusSm),
                    ),
                    child: Opacity(
                      opacity: _busy ? 0.4 : 1,
                      child: DshIcon(
                        DshIcons.projectAdd,
                        size: widget.iconSize,
                        color: widget.inkToken == null
                            ? theme.labelPrimary
                            : theme.color(widget.inkToken!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        WorkspacePickFlow(
          services: widget.services,
          slots: widget.slots,
          flowSlot: _flow,
          i18n: widget.i18n,
          open: _open,
          anchor: _link,
          addOnly: true,
          onBusyChange: (busy) {
            if (mounted && _busy != busy) setState(() => _busy = busy);
          },
          onPick: (workspaceId) {
            setState(() => _open = false);
            unawaited(
              widget.services
                  .openWorkspace(workspaceId)
                  .then(
                    (_) => widget.owner.onStarted(),
                    onError: (Object _) {},
                  ),
            );
          },
          onClose: () {
            if (mounted && _open) setState(() => _open = false);
          },
        ),
      ],
    );
    // A sized seat (the desktop header's control) is exactly that size: the
    // flow beside the button never widens it.
    final edge = widget.box;
    return edge == null
        ? stack
        : SizedBox(width: edge, height: edge, child: stack);
  }
}
