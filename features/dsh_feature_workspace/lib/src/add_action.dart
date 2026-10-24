import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
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
  });

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

  Slot<DirectoryFlowOwner, Widget> get _flow => DshSlots
      .sidebarWorkspacesDirectoryFlow
      .typed<DirectoryFlowOwner, Widget>();

  @override
  void initState() {
    super.initState();
    _sub = widget.slots.changes.listen((name) {
      if (name == _flow.name && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
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
    return Stack(
      alignment: Alignment.center,
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
                child: SizedBox(
                  width: DshSpace.touch,
                  height: DshSpace.touch,
                  child: Center(
                    child: Opacity(
                      opacity: _busy ? 0.4 : 1,
                      child: DshIcon(
                        DshIcons.projectAdd,
                        size: 18,
                        color: theme.labelPrimary,
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
  }
}
