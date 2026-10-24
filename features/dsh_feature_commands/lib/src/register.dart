import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_client/dsh_client.dart' show EmitEvent;
import 'package:dsh_models/dsh_models.dart' show HostRemotes;
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'command_source.dart';
import 'popup_view.dart';

final Slot<SessionOwner, Widget> _overlay = DshSlots.conversationInputOverlay
    .typed<SessionOwner, Widget>();

/// What the feature keeps for the app.
class CommandsFeature {
  CommandsFeature._(this.source, this._offs);

  /// The `/` source and its directory cache.
  final CommandSource source;
  final List<void Function()> _offs;

  /// Withdraw the source and the popup entry.
  void dispose() {
    for (final off in _offs) {
      off();
    }
    source.dispose();
  }
}

/// Register the `/` command source into the trigger [triggers], follow the
/// Host's catalog events, and occupy `conversation.input.overlay` with the
/// popupSelect shell (id `command-popup`, order 1, as in dsh).
CommandsFeature registerCommandsFeature(
  SlotRegistry slots, {
  required InputTriggerRegistry triggers,
  required CommandUiRegistry commandUi,
  required HostRemotes remotes,
  required InputSessionPort sessions,
  required DshI18n Function() i18n,
}) {
  final source = CommandSource(
    registry: commandUi,
    triggers: triggers,
    commands: remotes.commands,
    sessions: sessions,
    i18n: i18n,
  );
  final offs = <void Function()>[
    triggers.registerSource(source),
    commandUi.onDismiss(source.dismissCommand),
    slots.register<SessionOwner, Widget>(
      _overlay,
      (owner) => PopupSelectOverlay(
        key: ValueKey('command-popup-${owner.sessionId}'),
        sessionId: owner.sessionId,
        controller: source.popupFor(owner.sessionId),
        i18n: i18n(),
      ),
      id: 'command-popup',
      order: 1,
    ),
  ];
  final events = remotes.hostEvents.listen((e) {
    if (e is! EmitEvent) return;
    switch (e.event) {
      case 'commands/change':
        source.onCommandsChanged();
      case 'agent-preset/selected':
        final id = e.args.isEmpty ? null : e.args[0];
        if (id is String) source.onPresetSelected(id);
    }
  });
  final generations = remotes.generations.listen((g) {
    if (g != null) source.onConnectionReset();
  });
  offs
    ..add(() => unawaited(events.cancel()))
    ..add(() => unawaited(generations.cancel()));
  return CommandsFeature._(source, offs);
}
