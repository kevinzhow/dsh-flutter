import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> menuFamilyCases = {
  'menu-family.profiles': ParityCase(
    widgets: ['dsh_ui:DshMenuCard'],
    build: (ctx) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: DshMenuCard(
        key: const ValueKey('menu-family-card'),
        dense: ctx.props['profile'] == 'dense',
        compact: ctx.props['profile'] == 'compact',
        selectedIds: const ['checked'],
        onSelect: (_) {},
        entries: const [
          DshMenuLabel('heading', 'Actions'),
          DshMenuItem('install', 'Install package', icon: DshIcons.download),
          DshMenuItem('checked', 'Selected'),
          DshMenuSeparator('separator'),
          DshMenuItem('off', 'Unavailable', disabled: true),
          DshMenuItem('remove', 'Remove', danger: true),
        ],
      ),
    ),
  ),
};
