import 'package:dsh_client/generated_commands.dart' show CommandDescriptor;
import 'package:dsh_i18n/dsh_i18n.dart';

/// The first-party command definitions (dsh `ui-commands` `resolution.ts`),
/// keyed by the stable definition id the Host descriptor carries. The client
/// selects their localized titles, descriptions, icons and input spellings by
/// identity; a Host description can never change that selection.
const Map<String, String> builtinDefinitions = {
  'goal': '@deepseek-ai/dsh-command-goal',
  'plan': '@deepseek-ai/dsh-plan-mode',
  'feedback': '@deepseek-ai/dsh-command-feedback',
  'compact': '@deepseek-ai/dsh-command-compact',
  'permission': '@deepseek-ai/dsh-permission-presets',
  'export': '@deepseek-ai/dsh-session-log-export',
};

/// The first-party name of [descriptor], or null for another definition.
String? builtinCommandName(CommandDescriptor descriptor) {
  for (final e in builtinDefinitions.entries) {
    if (descriptor.definitionId == e.value) return e.key;
  }
  return null;
}

/// The input spelling of a menu-picked command: the localized token of a known
/// definition, otherwise the registered name.
String claimToken(CommandDescriptor descriptor, DshI18n i18n) {
  final name = builtinCommandName(descriptor);
  return name == null ? descriptor.name : i18n.t('command', 'token.$name');
}

final Map<String, String> _tokenAliases = () {
  final out = <String, String>{};
  for (final name in builtinDefinitions.keys) {
    for (final locale in DshLocale.values) {
      out[DshI18n(locale).t('command', 'token.$name')] = name;
    }
  }
  return out;
}();

/// Resolve a typed spelling against the session's effective definitions. An
/// exact name wins; a localized alias selects only the first-party definition,
/// never an unrelated scoped override.
CommandDescriptor? resolveCommand(
  String token,
  List<CommandDescriptor> descriptors,
) {
  for (final d in descriptors) {
    if (d.name == token) return d;
  }
  final name = _tokenAliases[token];
  if (name == null) return null;
  for (final d in descriptors) {
    if (d.definitionId == builtinDefinitions[name]) return d;
  }
  return null;
}
