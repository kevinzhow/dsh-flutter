import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'permission_catalog.dart';
import 'permission_command.dart';
import 'permission_default.dart';
import 'permission_widgets.dart';

final Slot<SettingsOwner, Widget> _generalItem = DshSlots.settingsGeneralItem
    .typed<SettingsOwner, Widget>();
final Slot<SessionOwner, Widget> _composerSeat = DshSlots
    .conversationInputPermission
    .typed<SessionOwner, Widget>();

/// What the feature keeps alive for the app: the shared catalog and the
/// Settings row's controller.
class PermissionPresetsFeature {
  PermissionPresetsFeature._(this.catalog, this.defaults, this._offs);

  final List<void Function()> _offs;

  final PermissionCatalogDirectory catalog;
  final PermissionDefaultController defaults;

  /// Withdraw the slot occupants and stop the controllers.
  Future<void> dispose() async {
    for (final off in _offs) {
      off();
    }
    await defaults.dispose();
    await catalog.dispose();
  }
}

/// Register the new-session default into `settings.general.item` (order -20,
/// the first row, as in dsh) and the current-session control into
/// `conversation.input.permission`.
PermissionPresetsFeature registerPermissionPresetsFeature(
  SlotRegistry slots, {
  required HostRemotes remotes,
  required ConfigForms forms,
  required DshI18n Function() i18n,
  CommandUiRegistry? commandUi,
  ProjectionStore? Function(String sessionId)? projectionsOf,
}) {
  final catalog = PermissionCatalogDirectory(remotes);
  final defaults = PermissionDefaultController(
    mirror: forms.mirror,
    remotes: remotes,
    catalog: catalog,
  );
  final offs = <void Function()>[];
  offs.add(
    slots.register<SettingsOwner, Widget>(
      _generalItem,
      (owner) => PermissionRow(controller: defaults, i18n: i18n()),
      id: 'permission',
      order: -20,
    ),
  );
  offs.add(
    slots.register<SessionOwner, Widget>(
      _composerSeat,
      (owner) => PermissionSelect(
        owner: owner,
        catalog: catalog,
        submit: (sessionId, preset) =>
            submitPermission(remotes, sessionId, preset),
        i18n: i18n(),
      ),
    ),
  );
  if (commandUi != null && projectionsOf != null) {
    offs
      ..add(
        decoratePermissionCommand(
          commandUi,
          catalog: catalog,
          projectionsOf: projectionsOf,
          submit: (sessionId, preset) =>
              submitPermission(remotes, sessionId, preset),
          i18n: i18n,
        ),
      )
      ..add(
        // Only an invalidation makes displayed options stale: drop an open popup
        // on it, and leave one a read merely settled alone.
        _dismissOnInvalidation(catalog, commandUi),
      );
  }
  return PermissionPresetsFeature._(catalog, defaults, offs);
}

void Function() _dismissOnInvalidation(
  PermissionCatalogDirectory catalog,
  CommandUiRegistry commandUi,
) {
  final sub = catalog.invalidations.changes.listen(
    (_) => commandUi.dismiss('permission'),
  );
  return () => unawaited(sub.cancel());
}
