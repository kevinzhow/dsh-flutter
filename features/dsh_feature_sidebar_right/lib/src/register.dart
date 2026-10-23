import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'panel.dart';
import 'state.dart';

/// What the sidebar needs from the composition root.
abstract interface class SidebarServices {
  /// The app navigator: the phone presentation is a sheet pushed onto it.
  GlobalKey<NavigatorState> get navigatorKey;
}

/// The right sidebar as other features and the app reach it.
class SidebarRightFeature {
  SidebarRightFeature._(this._slots, this._i18n, this._services);

  final SlotRegistry _slots;
  final DshI18n Function() _i18n;
  final SidebarServices _services;
  final Map<String, SidebarState> _states = {};

  /// The sidebar state of [sessionId] (created on first use).
  SidebarState stateFor(String sessionId) =>
      _states.putIfAbsent(sessionId, () => SidebarState(sessionId));

  bool _inline(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= sidebarInlineMinWindowWidth;

  /// Show or hide the sidebar of [owner]'s session: a column on wide windows,
  /// a sheet otherwise.
  void toggle(BuildContext context, SessionOwner owner) {
    final state = stateFor(owner.sessionId);
    if (_inline(context)) {
      state.setInlineOpen(!state.inlineOpen);
    } else {
      unawaited(_sheet(context, owner));
    }
  }

  /// Open the preview of [path] (absolute or workspace-relative) at [line],
  /// showing the sidebar if it is closed (the tool cards' `openFile`).
  void openFile(SessionOwner owner, String path, {int? line}) {
    final state = stateFor(owner.sessionId);
    state.openResource(
      fileAddressFor(owner.sessionId, owner.cwd, path),
      line: line,
    );
    final context = _services.navigatorKey.currentContext;
    if (context == null) return;
    if (_inline(context)) {
      state.setInlineOpen(true);
    } else if (!_sheetOpen.contains(owner.sessionId)) {
      unawaited(_sheet(context, owner));
    }
  }

  final Set<String> _sheetOpen = {};

  Future<void> _sheet(BuildContext context, SessionOwner owner) async {
    if (!_sheetOpen.add(owner.sessionId)) return;
    final theme = context.dsh;
    final state = stateFor(owner.sessionId);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: theme.bgBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(theme.radiusPanel),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (sheet) => SizedBox(
          key: const ValueKey('sidebar-sheet'),
          height: MediaQuery.sizeOf(sheet).height * 0.92,
          child: SidebarPanel(
            state: state,
            owner: owner,
            slots: _slots,
            i18n: _i18n(),
            onCollapse: () => Navigator.of(sheet).pop(),
          ),
        ),
      );
    } finally {
      _sheetOpen.remove(owner.sessionId);
    }
  }
}

/// Occupy `conversation.session.header.actions` with the button that opens the
/// sidebar and `rightbar.session` with the inline column.
SidebarRightFeature registerSidebarRightFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  required SidebarServices services,
}) {
  final feature = SidebarRightFeature._(slots, i18n, services);
  slots.register<SessionOwner, Widget>(
    DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
    (owner) => _SidebarButton(feature: feature, owner: owner, i18n: i18n),
    id: 'sidebar-right',
    order: 100,
  );
  slots.register<SessionOwner, Widget>(
    DshSlots.rightbarSession.typed<SessionOwner, Widget>(),
    (owner) {
      final state = feature.stateFor(owner.sessionId);
      return ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.inlineOpen ||
              MediaQuery.sizeOf(context).width < sidebarInlineMinWindowWidth) {
            return const SizedBox.shrink();
          }
          return SizedBox(
            key: const ValueKey('sidebar-inline'),
            width: sidebarInlineWidth,
            child: SidebarPanel(
              state: state,
              owner: owner,
              slots: slots,
              i18n: i18n(),
              bordered: true,
              onCollapse: () => state.setInlineOpen(false),
            ),
          );
        },
      );
    },
  );
  return feature;
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.feature,
    required this.owner,
    required this.i18n,
  });

  final SidebarRightFeature feature;
  final SessionOwner owner;
  final DshI18n Function() i18n;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      button: true,
      label: i18n().t('sidebarRight', 'chrome.expandAria'),
      child: GestureDetector(
        key: const ValueKey('sidebar-open'),
        behavior: HitTestBehavior.opaque,
        onTap: () => feature.toggle(context, owner),
        child: SizedBox(
          width: DshSpace.touch,
          height: DshSpace.touch,
          child: Center(
            child: DshIcon(
              DshIcons.folderClose,
              size: 20,
              color: theme.labelSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
