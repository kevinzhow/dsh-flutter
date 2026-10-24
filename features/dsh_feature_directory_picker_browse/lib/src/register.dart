import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_client/generated_directory_picker.dart'
    show DirectoryPickerRemote;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'flow.dart';

final Slot<DirectoryFlowOwner, Widget> _heroFlow = DshSlots
    .conversationHeroWorkspaceDirectoryFlow
    .typed<DirectoryFlowOwner, Widget>();
final Slot<DirectoryFlowOwner, Widget> _sidebarFlow = DshSlots
    .sidebarWorkspacesDirectoryFlow
    .typed<DirectoryFlowOwner, Widget>();

/// The Host's business message when a failure carries one, else the error's
/// own text (dsh `failureText`).
String directoryFailureText(Object error) {
  if (error is RemoteException && error.message.isNotEmpty) {
    return error.message;
  }
  return '$error';
}

/// Fill both directory-flow holes with the browse flow (dsh `apply`): the
/// workspace picker of the blank-session hero and the sidebar's add action each
/// get their own browser, driving `directoryPicker/list` and
/// `directoryPicker/createDirectory`. Returns the disposer.
void Function() registerDirectoryPickerBrowseFeature(
  SlotRegistry slots, {
  required DirectoryPickerRemote remote,
  required DshI18n Function() i18n,
}) {
  Widget build(DirectoryFlowOwner owner, String id) => BrowseDirectoryFlow(
    key: ValueKey('directory-flow-$id'),
    owner: owner,
    // The Remote caller has no per-call abort: a superseded scan's answer is
    // dropped by the model's sequence guard instead of being cancelled.
    list: (path, signal) => remote.list(path),
    create: (path, name) => remote.createDirectory(path, name),
    i18n: i18n(),
    failureText: directoryFailureText,
  );
  final offs = <void Function()>[
    slots.register<DirectoryFlowOwner, Widget>(
      _heroFlow,
      (owner) => build(owner, 'hero'),
    ),
    slots.register<DirectoryFlowOwner, Widget>(
      _sidebarFlow,
      (owner) => build(owner, 'sidebar'),
    ),
  ];
  return () {
    for (final off in offs) {
      off();
    }
  };
}
