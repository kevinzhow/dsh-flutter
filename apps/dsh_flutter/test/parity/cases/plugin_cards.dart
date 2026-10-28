import 'dart:async';

import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../helpers/plugin_card_fixture.dart';

final Map<String, ParityCase> pluginCardCases = {
  'plugin-cards.manager': ParityCase(
    widgets: [
      'dsh_feature_plugins:PluginManagerPage loaded cards',
      'dsh_ui:DshPluginCard',
      'dsh_ui:DshPluginCardList',
    ],
    framed: false,
    notes: 'Actual manager with shared offline data. Published-bundle source runner required; no source-TS substitution. SVG image formats, highlight and sticky touch hover remain pending.',
    build: (ctx) => PluginCardCaptureSurface(
      scenario: (ctx.props['scenario'] as Map).cast<String, Object?>(),
      i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
    ),
  ),
};

/// Full actual manager; no card layout, metric or paint is supplied by this
/// fixture. The only outer paint is the normal application theme canvas.
class PluginCardCaptureSurface extends StatefulWidget {
  const PluginCardCaptureSurface({
    super.key,
    required this.scenario,
    required this.i18n,
    this.onFixture,
  });
  final Map<String, Object?> scenario;
  final DshI18n i18n;
  final void Function(SyntheticPluginCardFixture)? onFixture;

  @override
  State<PluginCardCaptureSurface> createState() =>
      _PluginCardCaptureSurfaceState();
}

class _PluginCardCaptureSurfaceState extends State<PluginCardCaptureSurface> {
  late final fixture = SyntheticPluginCardFixture(widget.scenario);
  final slots = SlotRegistry();

  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    widget.onFixture?.call(fixture);
  }

  @override
  void dispose() {
    unawaited(fixture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('plugin-cards-capture'),
    color: context.dsh.bgBase,
    child: DefaultTextStyle(
      style: context.dsh
          .textStyle('--dsw-font-s-14')
          .copyWith(color: context.dsh.labelPrimary),
      child: PluginManagerPage(
        model: fixture.manager,
        market: fixture.market,
        slots: slots,
        i18n: widget.i18n,
      ),
    ),
  );
}
