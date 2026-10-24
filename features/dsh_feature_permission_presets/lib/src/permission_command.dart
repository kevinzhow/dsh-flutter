import 'package:dsh_client/generated_permission_presets.dart' as perm;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';

import 'permission_catalog.dart';
import 'presentation.dart';

/// The `/permission` popup rows (dsh `optionsOf`): the process catalog joined
/// with the session's current value. Full access and Auto review each carry
/// their own risk acknowledgement.
List<SelectOption> permissionOptions(
  perm.PermissionCatalog catalog,
  String currentValue,
  DshI18n i18n,
) {
  String t(String key) => i18n.t(permissionAccessNs, key);
  return [
    for (final option in catalog.options)
      SelectOption(
        id: option.value,
        label: option.value == autoReviewPreset
            ? t('auto.label')
            : displayPermissionPreset(
                option.value,
                option.name,
                i18n,
                namespace: permissionAccessNs,
              ),
        badge: option.value == autoReviewPreset ? t('auto.badge') : null,
        detail: option.value == autoReviewPreset
            ? t('auto.description')
            : option.description,
        active: option.value == currentValue,
        confirmation:
            option.value == fullAccessPreset || option.value == autoReviewPreset
            ? () {
                final auto = option.value == autoReviewPreset;
                return SelectConfirmation(
                  title: t(auto ? 'auto.confirm.title' : 'confirm.title'),
                  description: t(
                    auto ? 'auto.confirm.description' : 'confirm.description',
                  ),
                  acknowledgeLabel: t(
                    auto ? 'auto.confirm.acknowledge' : 'confirm.acknowledge',
                  ),
                  cancelLabel: t('confirm.cancel'),
                  confirmLabel: t(
                    auto ? 'auto.confirm.enable' : 'confirm.enable',
                  ),
                );
              }()
            : null,
      ),
  ];
}

/// Hang the `/permission` popup on the Host command (dsh decoration): a bare
/// invocation opens the picker, an argued line still runs the Host command.
/// The session's current value alone decides availability; a missing catalog
/// surfaces through the options load, which keeps the picker's retry reachable.
void Function() decoratePermissionCommand(
  CommandUiRegistry commandUi, {
  required PermissionCatalogDirectory catalog,
  required ProjectionStore? Function(String sessionId) projectionsOf,
  required Future<void> Function(String sessionId, String preset) submit,
  required DshI18n Function() i18n,
}) {
  String? currentOf(String sessionId) {
    final selection = projectionsOf(sessionId)?.get('permissions');
    final stored = selection is Map ? selection['currentValue'] : null;
    return stored is String ? stored : null;
  }

  return commandUi.decorate(
    CommandDecoration(
      name: 'permission',
      available: (sessionId) => currentOf(sessionId) != null,
      ui: PopupSelectSpec(
        options: (sessionId, signal) async {
          final current = currentOf(sessionId);
          if (current == null) {
            throw StateError(
              'permission presets are not available on this host',
            );
          }
          return permissionOptions(await catalog.load(), current, i18n());
        },
        onSelect: (option, sessionId) => submit(sessionId, option.id),
      ),
    ),
  );
}
