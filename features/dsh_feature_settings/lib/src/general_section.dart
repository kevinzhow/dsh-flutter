import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Slot<SettingsOwner, Widget> _itemSlot = DshSlots.settingsGeneralItem
    .typed<SettingsOwner, Widget>();

/// The rows features contribute to `settings.general.item`, stacked in order
/// (dsh `GeneralSection`'s `.section` column). The last row is marked as the end
/// of the column, so it draws no separator.
class GeneralColumn extends StatelessWidget {
  const GeneralColumn({super.key, required this.slots});

  final SlotRegistry slots;

  @override
  Widget build(BuildContext context) {
    final rows = slots.renderList(_itemSlot, const SettingsOwner());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          i == rows.length - 1 ? DshColumnEnd(child: rows[i]) : rows[i],
      ],
    );
  }
}

/// The General section (dsh `GeneralSection`): the [GeneralColumn] in one
/// scrolling page.
class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key, required this.slots});

  final SlotRegistry slots;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('general-section'),
      padding: const EdgeInsets.fromLTRB(
        DshSpace.lg + 8,
        0,
        DshSpace.lg + 8,
        DshSpace.xl,
      ),
      child: GeneralColumn(slots: slots),
    );
  }
}

/// The "Current version" row (dsh `CurrentVersionRow`): the release the host
/// reports, or nothing when it has none.
class CurrentVersionRow extends StatelessWidget {
  const CurrentVersionRow({
    super.key,
    required this.version,
    required this.i18n,
  });

  final String? version;
  final DshI18n i18n;

  @override
  Widget build(BuildContext context) {
    final v = version;
    if (v == null) return const SizedBox.shrink();
    final theme = context.dsh;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: DshLineText(
        i18n.t('settings', 'general.currentVersion', params: {'version': v}),
        style: theme
            .textStyle('--dsw-font-s-14')
            .copyWith(color: theme.labelPrimary),
      ),
    );
  }
}
