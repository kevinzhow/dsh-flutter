import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'panel.dart';
import 'state.dart';

/// The guide tab's body (dsh `GuideBody`): a muted compass over one card per
/// tab type that contributed one, in order, centred in the pane. Picking a card
/// opens that type in the guide's place, so the guide is a doorway.
class GuideBody extends StatelessWidget {
  const GuideBody({
    super.key,
    required this.state,
    required this.tabId,
    required this.owner,
    required this.slots,
  });

  final SidebarState state;
  final String tabId;
  final SessionOwner owner;
  final SlotRegistry slots;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final cards = <Widget>[];
    for (final type in slots.sidebarTabs.guideTypes) {
      final card = slots.renderKeyed(
        guideEntrySlot,
        type.kind,
        SidebarGuideOwner(
          session: owner,
          kind: type.kind,
          tabId: tabId,
          actions: state,
        ),
      );
      if (card != null) cards.add(card);
    }
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            // The column rises 5% of the pane above the middle (the guide's
            // `::after` spacer takes 10% of the height).
            padding: EdgeInsets.fromLTRB(24, 0, 24, box.maxHeight * 0.1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The compass rides the neutral ramp of the theme, not a label
                // alias: its bluish cast shows at this size.
                DshCompassGlyph(
                  size: 56,
                  color: theme.brightness == Brightness.dark
                      ? theme.color('--dsw-static-neutral-700')
                      : theme.color('--dsw-static-neutral-200'),
                ),
                const SizedBox(height: 30),
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  cards[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
