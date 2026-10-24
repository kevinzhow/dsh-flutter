import 'package:dsh_client/generated_commands.dart' show CommandDescriptor;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';

import 'resolution.dart';

/// Row names per section, highest usage first; rows outside both lists close
/// the Commands section in catalog order.
const Map<String, List<String>> _sectionRows = {
  'add': ['file', 'goal', 'plan', 'feedback'],
  'commands': ['compact', 'permission', 'model', 'export'],
};

/// The glyph key of each first-party Host command.
const Map<String, String> _hostIcons = {
  'goal': 'goal',
  'plan': 'plan',
  'feedback': 'feedback',
  'compact': 'compact',
  'permission': 'permission',
  'export': 'export',
};

/// The localized menu face of a catalog row: title, description and glyph of a
/// first-party command; null for any other row, which keeps its catalog
/// description.
({String label, String description, String icon})? builtinRowFace(
  CommandDescriptor descriptor,
  DshI18n i18n,
) {
  final name = builtinCommandName(descriptor);
  if (name == null) return null;
  return (
    label: i18n.t('command', 'label.$name'),
    description: i18n.t('command', 'description.$name'),
    icon: _hostIcons[name]!,
  );
}

/// Arrange the empty-query menu: the Add section, then the Commands section,
/// each in usage order, with unlisted rows closing Commands in their input
/// order; each row carries its section heading.
List<InputTriggerCandidate> sectionRows(
  List<InputTriggerCandidate> rows,
  DshI18n i18n,
) {
  final listed = {..._sectionRows['add']!, ..._sectionRows['commands']!};
  final byName = {for (final r in rows) r.name: r};
  List<InputTriggerCandidate> pick(List<String> names) => [
    for (final n in names)
      if (byName[n] case final row?) row,
  ];
  final add = [
    for (final r in pick(_sectionRows['add']!))
      r.copyWith(section: i18n.t('command', 'section.add')),
  ];
  final commands = [
    for (final r in [
      ...pick(_sectionRows['commands']!),
      ...rows.where((r) => !listed.contains(r.name)),
    ])
      r.copyWith(section: i18n.t('command', 'section.commands')),
  ];
  return [...add, ...commands];
}
