import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import '../platform/notifications.dart';

final Slot<SettingsOwner, Widget> _item = DshSlots.settingsGeneralItem
    .typed<SettingsOwner, Widget>();

/// The General rows Whalee adds to dsh's: the interface language (dsh's
/// `client/locale` registers its own at order 0), the notification switch, and
/// the connected host with its Disconnect. The rows that exist in dsh's own
/// General section come from the feature packages.
void registerAppSettingsRows(SlotRegistry slots, AppController controller) {
  slots.register<SettingsOwner, Widget>(
    _item,
    (owner) => LanguageRow(controller: controller),
    id: 'language',
    order: 0,
  );
  if (controller.notifications?.supported ?? false) {
    slots.register<SettingsOwner, Widget>(
      _item,
      (owner) => NotificationsRow(controller: controller),
      id: 'notifications',
      order: 5,
    );
  }
  slots.register<SettingsOwner, Widget>(
    _item,
    (owner) => HostRow(controller: controller),
    id: 'host',
    order: 200,
  );
}

/// The Language row: a selector pill over the two languages dsh ships.
class LanguageRow extends StatelessWidget {
  const LanguageRow({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final i18n = controller.i18n;
    String a(String key) => i18n.t(appNamespace, key);
    return DshSettingsRow(
      key: const ValueKey('language-row'),
      title: i18n.t('settings.locale', 'language.title'),
      description: a('settings.language.description'),
      control: DshSelectorPill(
        key: const ValueKey('language-selector'),
        label: a('settings.language.${controller.locale.name}'),
        onPressed: () async {
          final id = await showDshOptionSheet(
            context,
            selectedId: controller.locale.name,
            options: [
              for (final l in DshLocale.values)
                DshOption(id: l.name, label: a('settings.language.${l.name}')),
            ],
          );
          if (id != null) controller.setLocale(DshLocale.values.byName(id));
        },
      ),
    );
  }
}

/// The notification switch, with the state of the system permission under it.
class NotificationsRow extends StatefulWidget {
  const NotificationsRow({super.key, required this.controller});

  final AppController controller;

  @override
  State<NotificationsRow> createState() => _NotificationsRowState();
}

class _NotificationsRowState extends State<NotificationsRow>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system settings: the permission may have changed.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    await widget.controller.notices?.refreshPermission();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final i18n = c.i18n;
    String a(String key) => i18n.t(appNamespace, key);
    final permission = c.notices?.permission ?? NoticePermission.unsupported;
    final enabled = c.notificationsEnabled;
    final blocked = enabled && permission == NoticePermission.denied;
    final undetermined =
        enabled && permission == NoticePermission.notDetermined;
    final description = blocked
        ? a('settings.notifications.denied')
        : undetermined
        ? a('settings.notifications.undetermined')
        : a('settings.notifications.description');
    return DshSettingsRow(
      key: const ValueKey('notifications-row'),
      title: a('settings.notifications.title'),
      description: description,
      alert: blocked,
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (blocked || undetermined) ...[
            DshButton(
              key: const ValueKey('notifications-fix'),
              variant: DshButtonVariant.outline,
              size: DshButtonSize.sm,
              onPressed: () async {
                if (blocked) {
                  await c.notices?.openSystemSettings();
                } else {
                  await c.notices?.request();
                }
                if (mounted) setState(() {});
              },
              child: Text(
                blocked
                    ? a('settings.notifications.openSettings')
                    : a('settings.notifications.allow'),
              ),
            ),
            const SizedBox(width: DshSpace.sm),
          ],
          DshSwitch(
            key: const ValueKey('notifications-switch'),
            value: enabled,
            label: a('settings.notifications.switch'),
            onChanged: (value) {
              c.setNotificationsEnabled(value);
              setState(() {});
              _refresh();
            },
          ),
        ],
      ),
    );
  }
}

/// The connected host and the way to leave it.
class HostRow extends StatelessWidget {
  const HostRow({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.phase != ConnectionPhase.connected) {
      return const SizedBox.shrink();
    }
    final i18n = controller.i18n;
    String a(String key) => i18n.t(appNamespace, key);
    return DshSettingsRow(
      key: const ValueKey('host-row'),
      title: a('settings.host.title'),
      description: controller.hostOrigin ?? '',
      control: DshButton(
        key: const ValueKey('settings-disconnect'),
        variant: DshButtonVariant.outline,
        onPressed: () async {
          Navigator.of(context).pop();
          await controller.disconnect();
        },
        child: Text(a('sessions.disconnect')),
      ),
    );
  }
}
