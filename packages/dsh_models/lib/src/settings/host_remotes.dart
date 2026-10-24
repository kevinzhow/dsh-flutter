import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_client/generated_commands.dart' as commands_ns;
import 'package:dsh_client/generated_directory_picker.dart' as directory_ns;
import 'package:dsh_client/generated_file_references.dart' as file_ref_ns;
import 'package:dsh_client/generated_permission_presets.dart' as permission_ns;
import 'package:dsh_client/generated_session_reference_resolver.dart'
    as session_ref_ns;
import 'package:dsh_client/generated_settings.dart' as settings_ns;
import 'package:dsh_client/generated_workspace.dart' as workspace_ns;

/// The unary Remote namespaces the settings-side features call, as dsh's
/// `ctx.remote` carries them, and the forwarded host events they subscribe to.
///
/// Built over one [RemoteCaller], so the real app passes the connection's and a
/// test passes a scripted fake; every call and every decoded type is the
/// generated one (`tool/codegen`).
class HostRemotes {
  HostRemotes({
    required RemoteCaller caller,
    required this.hostEvents,
    required this.generations,
    ConnectionGeneration? Function()? currentGeneration,
  }) : currentGeneration = currentGeneration ?? (() => null),
       session = session_ns.SessionRemote(caller),
       settings = settings_ns.SettingsRemote(caller),
       permissionPresets = permission_ns.PermissionPresetsRemote(caller),
       commands = commands_ns.CommandsRemote(caller),
       fileReferences = file_ref_ns.FileReferencesRemote(caller),
       sessionReferences = session_ref_ns.SessionReferenceResolverRemote(
         caller,
       ),
       workspace = workspace_ns.WorkspaceRemote(caller),
       directoryPicker = directory_ns.DirectoryPickerRemote(caller),
       caller = caller;

  /// `session` (model catalog, `selectModel`).
  final session_ns.SessionRemote session;

  /// `settings` (`describe`, `mutate`, ...).
  final settings_ns.SettingsRemote settings;

  /// `permissionPresets` (`catalog`).
  final permission_ns.PermissionPresetsRemote permissionPresets;

  /// `commands` (`execute`, the `/permission <preset>` write path).
  final commands_ns.CommandsRemote commands;

  /// `fileReferences` (`list`, the `@` file candidates).
  final file_ref_ns.FileReferencesRemote fileReferences;

  /// `sessionReferenceResolver` (`candidates`, the `@` session candidates).
  final session_ref_ns.SessionReferenceResolverRemote sessionReferences;

  /// `workspace` (`create`, the Workspace registry verbs).
  final workspace_ns.WorkspaceRemote workspace;

  /// `directoryPicker` (`list`, `createDirectory`: the browse flow).
  final directory_ns.DirectoryPickerRemote directoryPicker;

  /// The caller the namespaces above run over (streams open on the connection
  /// through the composition root).
  final RemoteCaller caller;

  /// Every forwarded host event (`settings/document-updated`, ...).
  final Stream<HostEvent> hostEvents;

  /// The live connection generation; null while none is live. A new object is
  /// a Host reconnect (`connection/reset` in dsh).
  final Stream<ConnectionGeneration?> generations;

  /// The generation live now (dsh's `connection.generation.getSnapshot()`).
  final ConnectionGeneration? Function() currentGeneration;

  /// The forwarded `emit` events named [event].
  Stream<EmitEvent> emitted(String event) => hostEvents
      .where((e) => e is EmitEvent && e.event == event)
      .cast<EmitEvent>();
}

/// Whether [error] is a refusal the Host answered (`{ok:false}`, for example
/// `settings/conflict`), as opposed to a failure of the transport itself, which
/// dsh's callers see as a rejected promise rather than an error result.
bool isHostRefusal(Object error) =>
    error is RemoteException &&
    !error.code.startsWith('transport/') &&
    !error.code.startsWith('connection/');
