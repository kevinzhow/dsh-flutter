import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'folder_error.dart';
import 'picker_menu.dart';

const String _addWorkspace = '::add-workspace';

/// The failure text of an adoption (dsh: the error's message, else its text).
String adoptionFailureText(Object reason) =>
    reason is RemoteException ? reason.message : '$reason';

/// Workspace pick/add flow (dsh `WorkspacePickFlow`): the pick menu and the
/// adoption error dialog around a directory-flow hole.
///
/// The menu is dsh's anchored popover at every width (it hangs from [anchor],
/// the chip). Directory
/// picking itself belongs to whatever occupies [flowSlot]: this flow opens it,
/// adopts the picked path (`workspace/create`), and owns the error surface.
/// Adding a workspace has exactly one route: pick a host directory, new or
/// existing (the browser's own New folder covers creating one).
class WorkspacePickFlow extends StatefulWidget {
  const WorkspacePickFlow({
    super.key,
    required this.services,
    required this.slots,
    required this.flowSlot,
    required this.i18n,
    required this.open,
    required this.onPick,
    required this.onClose,
    this.anchor,
    this.selectedId,
    this.addOnly = false,
    this.onBusyChange,
  });

  final WorkspaceServices services;
  final SlotRegistry slots;
  final Slot<DirectoryFlowOwner, Widget> flowSlot;
  final DshI18n i18n;

  /// The menu was asked for (the chip or the add button was pressed).
  final bool open;

  /// A real workspace was picked or adopted.
  final void Function(String workspaceId) onPick;

  /// Close the menu (outside tap, Escape, after a pick).
  final VoidCallback onClose;

  /// What the popover hangs from on a wide window.
  final LayerLink? anchor;

  /// The workspace in use (the trailing check).
  final String? selectedId;

  /// Only the add action, no existing workspaces.
  final bool addOnly;

  /// The picking interaction or an adoption started or ended.
  final void Function(bool busy)? onBusyChange;

  @override
  State<WorkspacePickFlow> createState() => _WorkspacePickFlowState();
}

class _WorkspacePickFlowState extends State<WorkspacePickFlow> {
  final OverlayPortalController _portal = OverlayPortalController();
  StreamSubscription<WorkspaceSnapshot>? _listSub;
  StreamSubscription<String>? _slotSub;
  bool _flowOpen = false;
  bool _picking = false;
  bool _errorOpen = false;
  String? _modalError;
  bool _lastBusy = false;

  bool get _flowBusy => _flowOpen || _picking;
  bool get _flowAvailable => widget.slots
      .entries(widget.flowSlot as Slot<Object?, Object?>)
      .isNotEmpty;

  @override
  void initState() {
    super.initState();
    _listSub = widget.services.workspaces.changes.listen((_) => _refresh());
    _slotSub = widget.slots.changes.listen((name) {
      if (name == widget.flowSlot.name) _refresh();
    });
  }

  @override
  void dispose() {
    unawaited(_listSub?.cancel());
    unawaited(_slotSub?.cancel());
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('workspace', key, params: params);

  String _title(WorkspaceSnapshot snapshot, int i) {
    final w = snapshot.items[i];
    return workspaceDisplayTitle(
      w.title,
      widget.i18n.t('conversation', 'workspace.defaultName'),
    );
  }

  // ---- the owner side of the flow conversation ---------------------------

  DirectoryFlowOwner get _owner => DirectoryFlowOwner(
    open: _flowOpen,
    busy: _picking,
    onPicked: (path) {
      setState(() => _picking = true);
      unawaited(
        _adopt(path).whenComplete(() {
          if (mounted) setState(() => _picking = false);
        }),
      );
    },
    onCancel: () {
      if (mounted) setState(() => _flowOpen = false);
    },
    onError: (message) {
      if (!mounted) return;
      setState(() {
        _flowOpen = false;
        _modalError = message;
        _errorOpen = true;
      });
    },
  );

  /// Adopt a picked directory; failures land in the folder-error dialog
  /// (Choose again reopens the flow).
  Future<void> _adopt(String path) async {
    try {
      final workspace = await widget.services.createWorkspace(path);
      if (!mounted) return;
      setState(() => _flowOpen = false);
      widget.onPick(workspace.workspaceId);
    } on Object catch (reason) {
      if (!mounted) return;
      setState(() {
        _modalError = adoptionFailureText(reason);
        _flowOpen = false;
        _errorOpen = true;
      });
    }
  }

  void _openDirectoryFlow() {
    widget.onClose();
    setState(() {
      _errorOpen = false;
      _modalError = null;
      _flowOpen = true;
    });
  }

  void _handleSelect(String id) {
    if (id == _addWorkspace) {
      _openDirectoryFlow();
      return;
    }
    widget.onPick(id);
  }

  // ---- derived state, as dsh computes it ---------------------------------

  ({
    List<PickerRow> rows,
    List<PickerRow> footer,
    bool addIsTheOnlyEntry,
    bool menuIsEmpty,
    bool pending,
  })
  _model() {
    final snapshot = widget.services.workspaces.value;
    final flowAvailable = _flowAvailable;
    final add = flowAvailable
        ? [
            PickerRow(
              id: _addWorkspace,
              label: _t('menu.addWorkspace'),
              icon: DshIcons.plus,
              disabled: _flowBusy,
            ),
          ]
        : <PickerRow>[];
    final pinAdd = !widget.addOnly && snapshot.items.isNotEmpty;
    final rows = pinAdd
        ? [
            for (var i = 0; i < snapshot.items.length; i++)
              PickerRow(
                id: snapshot.items[i].workspaceId,
                label: _title(snapshot, i),
                icon: DshIcons.folderClose,
                disabled: _flowBusy,
              ),
          ]
        : add;
    final settled = widget.addOnly || snapshot.phase == WorkspacePhase.ready;
    return (
      rows: rows,
      footer: pinAdd ? add : const [],
      // An empty list is only final once the baseline lands, and a menu of one
      // row would offer nothing to choose between: the gesture IS the action.
      addIsTheOnlyEntry: !pinAdd && settled && add.length == 1,
      menuIsEmpty: rows.isEmpty,
      pending: !widget.addOnly && snapshot.phase == WorkspacePhase.pending,
    );
  }

  // ---- lifecycle of the menu and the dialogs -----------------------------

  @override
  void didUpdateWidget(WorkspacePickFlow old) {
    super.didUpdateWidget(old);
    _syncSurfaces();
  }

  void _syncSurfaces() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reportBusy();
      final m = _model();
      final menuShown = widget.open && !m.addIsTheOnlyEntry && !m.menuIsEmpty;
      if (widget.open && m.addIsTheOnlyEntry && !_flowBusy) {
        _openDirectoryFlow();
        return;
      }
      if (menuShown) {
        if (!_portal.isShowing) _portal.show();
      } else if (_portal.isShowing) {
        _portal.hide();
      }
      if (_errorOpen && !_errorShown) unawaited(_showError());
    });
  }

  void _reportBusy() {
    if (_lastBusy == _flowBusy) return;
    _lastBusy = _flowBusy;
    widget.onBusyChange?.call(_flowBusy);
  }

  bool _errorShown = false;

  Future<void> _showError() async {
    _errorShown = true;
    final retry = await showDshDialog<bool>(
      context,
      label: _t('folderError.title'),
      builder: (ctx) => FolderErrorForm(
        message: _modalError ?? '',
        title: _t('folderError.title'),
        cancelLabel: widget.i18n.t('common', 'cancel'),
        closeLabel: widget.i18n.t('common', 'close'),
        retryLabel: _t('folderError.retry'),
        retryEnabled: _flowAvailable,
      ),
    );
    _errorShown = false;
    if (!mounted) return;
    setState(() {
      _errorOpen = false;
      if (retry != true) _modalError = null;
    });
    if (retry == true) _openDirectoryFlow();
  }

  @override
  Widget build(BuildContext context) {
    _syncSurfaces();
    final link = widget.anchor;
    final m = _model();
    final statusShown =
        widget.open && !m.addIsTheOnlyEntry && !m.menuIsEmpty && m.pending;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        if (link == null) return const SizedBox.shrink();
        final model = _model();
        return Positioned(
          left: 0,
          top: 0,
          child: PickerMenu(
            link: link,
            rows: model.rows,
            footer: model.footer,
            selectedId: widget.selectedId,
            onSelect: _handleSelect,
            onClose: widget.onClose,
          ),
        );
      },
      // The directory-flow hole sits in the tree and draws nothing in place.
      // dsh's loading line is not part of the menu: it lands beside the chip
      // while the menu is up and the list has not arrived.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.slots.renderSingle(widget.flowSlot, _owner) ??
              const SizedBox.shrink(),
          if (statusShown)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: DshChromeText(
                _t('picker.loading'),
                key: const ValueKey('workspace-menu-status'),
                style: context.dsh
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: context.dsh.labelSecondary,
                      height: 18 / 12,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
