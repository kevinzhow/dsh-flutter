import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

/// The renderless occupant of a directory-flow hole (dsh `NativeDirectoryFlow`):
/// each rising edge of `open` runs exactly one `pick` and reports exactly one
/// outcome. The chooser opens on the host's display, so the flow is offered
/// only where that is this machine. An answer that arrives after the occupant
/// is gone is dropped (the wire has no per-request abort).
class NativeDirectoryFlow extends StatefulWidget {
  const NativeDirectoryFlow({
    super.key,
    required this.owner,
    required this.pick,
  });

  final DirectoryFlowOwner owner;

  /// Open the chooser; the chosen absolute path, or null when dismissed.
  final Future<String?> Function() pick;

  @override
  State<NativeDirectoryFlow> createState() => _NativeDirectoryFlowState();
}

class _NativeDirectoryFlowState extends State<NativeDirectoryFlow> {
  bool _armed = false;
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(NativeDirectoryFlow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  void _sync() {
    if (!widget.owner.open) {
      _armed = false;
      return;
    }
    if (_armed) return;
    _armed = true;
    // The owner's latest handlers receive the outcome, not the ones captured
    // when the chooser opened.
    widget.pick().then(
      (path) {
        if (!_alive) return;
        if (path == null) {
          widget.owner.onCancel();
        } else {
          widget.owner.onPicked(path);
        }
      },
      onError: (Object reason) {
        if (!_alive) return;
        widget.owner.onError('$reason');
      },
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Fill both directory-flow holes with the native chooser, ahead of any other
/// occupant (the browse flow stays the fallback). Returns the disposer.
void Function() registerDirectoryPickerNativeFeature(
  SlotRegistry slots, {
  required Future<String?> Function() pick,
}) {
  Widget build(DirectoryFlowOwner owner) =>
      NativeDirectoryFlow(owner: owner, pick: pick);
  final offs = <void Function()>[
    slots.register<DirectoryFlowOwner, Widget>(
      DshSlots.conversationHeroWorkspaceDirectoryFlow
          .typed<DirectoryFlowOwner, Widget>(),
      build,
      priority: -10,
    ),
    slots.register<DirectoryFlowOwner, Widget>(
      DshSlots.sidebarWorkspacesDirectoryFlow
          .typed<DirectoryFlowOwner, Widget>(),
      build,
      priority: -10,
    ),
  ];
  return () {
    for (final off in offs) {
      off();
    }
  };
}
