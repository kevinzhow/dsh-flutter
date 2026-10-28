import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'applications.dart';
import 'controller.dart';
import 'target_button.dart';
import 'file_route_action.dart';

/// The id of the command that opens the workspace in the chosen application.
const String openLocalCommand = 'workspace.openLocal';

/// What open-in-app needs from the composition root.
abstract interface class OpenInAppServices {
  OpenInAppController get controller;
  DshI18n get i18n;

  /// The window's shortcut service (null: no command, no tooltip keys).
  ShortcutService? get shortcuts;

  /// The app navigator, whose overlay carries the failure banner of a command.
  GlobalKey<NavigatorState> get navigatorKey;

  /// The workspace directory of the session in the main view, or null while a
  /// global panel covers it or the session has none.
  String? currentDirectory();
}

/// Register the header split button and the `workspace.openLocal` command (dsh
/// `ui-open-in-app` `apply`). Returns a disposer.
void Function() registerOpenInAppFeature(
  SlotRegistry slots, {
  required OpenInAppServices services,
}) {
  final controller = services.controller;
  final toasts = DshToasts();
  String t(String key) => services.i18n.t('open-in-app', key);

  Future<void> launch(
    BuildContext? context,
    String id,
    String path, {
    bool explicit = false,
  }) async {
    try {
      await controller.launch(id, path);
    } on Object {
      final text = t('path.openError');
      if (context != null && context.mounted) {
        toasts.show(context, text, icon: const DshIcon(DshIcons.warning));
      } else {
        final overlay = services.navigatorKey.currentState?.overlay;
        if (overlay != null) {
          toasts.showOn(overlay, text, icon: const DshIcon(DshIcons.warning));
        }
      }
      return;
    }
    if (explicit) controller.choose(id);
  }

  final offs = <void Function()>[
    slots.register<SessionOwner, Widget>(
      DshSlots.conversationSessionHeaderUtilities.typed<SessionOwner, Widget>(),
      (owner) => _HeaderAction(
        services: services,
        owner: owner,
        launch: launch,
        toasts: toasts,
      ),
      id: 'open-in-app',
      order: -10,
    ),
  ];
  for (final slot in [
    DshSlots.deliverablesFileActions,
    DshSlots.deliverablesReviewFileActions,
  ]) {
    offs.add(
      slots.register<DeliverablesFileActionsOwner, Widget>(
        slot.typed<DeliverablesFileActionsOwner, Widget>(),
        (owner) => FileRouteAction(
          key: ValueKey(owner.actionUrl),
          owner: owner,
          i18n: services.i18n,
        ),
        id: 'open-in-app',
      ),
    );
  }
  final shortcuts = services.shortcuts;
  if (shortcuts != null) {
    offs.add(
      shortcuts.register(
        ShortcutCommand(
          id: openLocalCommand,
          label: () => t('open.tooltip'),
          aliases: const ['open workspace locally', 'open in app'],
          defaults: {
            for (final p in [
              'desktop:macos',
              'desktop:windows',
              'desktop:linux',
            ])
              p: const ShortcutBinding('KeyO', [
                ShortcutModifier.primary,
                ShortcutModifier.alt,
              ]),
            for (final p in ['web:macos', 'web:windows'])
              p: const ShortcutBinding('KeyO', [
                ShortcutModifier.primary,
                ShortcutModifier.shift,
              ]),
          },
          resolve: (context) {
            if (controller.busy) return ShortcutBlocked(t('shortcut.busy'));
            final app = controller.enabled ? controller.currentApp() : null;
            final path = services.currentDirectory();
            if (app == null || path == null) {
              return ShortcutBlocked(t('shortcut.unavailable'));
            }
            return ShortcutHandled(() {
              unawaited(launch(null, app, path));
            });
          },
        ),
      ),
    );
  }
  return () {
    for (final off in offs.reversed) {
      off();
    }
    toasts.dismiss();
  };
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.services,
    required this.owner,
    required this.launch,
    required this.toasts,
  });

  final OpenInAppServices services;
  final SessionOwner owner;
  final Future<void> Function(
    BuildContext? context,
    String id,
    String path, {
    bool explicit,
  })
  launch;
  final DshToasts toasts;

  @override
  Widget build(BuildContext context) {
    final controller = services.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final path = owner.cwdReader?.call();
        final ids = controller.nameable;
        final preferredId = controller.currentApp();
        if (!controller.enabled ||
            path == null ||
            path.isEmpty ||
            preferredId == null) {
          return const SizedBox.shrink();
        }
        final i18n = services.i18n;
        String name(String id) =>
            i18n.t('open-in-app', applicationLabelKey[id]!);
        final entry = services.shortcuts?.registry.entry(openLocalCommand);
        return OpenTargetButton(
          applications: [
            for (final id in ids)
              OpenTargetApplication(
                id: id,
                name: name(id),
                icon: () => controller.icon(id),
              ),
          ],
          preferredId: preferredId,
          busy: controller.busy,
          shortcutKeys: entry == null || entry.keys.isEmpty ? null : entry.keys,
          labels: OpenTargetLabels(
            open: (app) =>
                i18n.t('open-in-app', 'open.title', params: {'app': app}),
            more: i18n.t('open-in-app', 'path.more'),
            defaultOf: (app) =>
                i18n.t('open-in-app', 'path.appDefault', params: {'app': app}),
          ),
          onOpen: (id, {required explicit}) =>
              launch(context, id, path, explicit: explicit),
        );
      },
    );
  }
}
