import 'dart:async';

import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../helpers/plugins_preview_fixture.dart';

final Map<String, ParityCase> pluginsPreviewCases = {
  for (final family in ['manager', 'inventory', 'market'])
    'plugins-preview.$family': ParityCase(
      widgets: ['dsh_feature_plugins:$family'],
      build: (ctx) => _Surface(
        family: family,
        name: ctx.props['name'] as String,
        width: (ctx.props['width'] as num).toDouble(),
        height: (ctx.props['height'] as num).toDouble(),
        i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
      ),
    ),
};

class _Surface extends StatefulWidget {
  const _Surface({
    required this.family,
    required this.name,
    required this.width,
    required this.height,
    required this.i18n,
  });
  final String family, name;
  final double width, height;
  final DshI18n i18n;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  final fixture = SyntheticPluginsPreview();
  final slots = SlotRegistry();
  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    if (widget.name == 'empty' || widget.name == 'install') {
      fixture.host.handlers['pluginManager/listBundles'] = (_) => <Object?>[];
      fixture.host.handlers['pluginInventory/list'] = (_) => {
        'managementAvailable': true,
        'entries': <Object?>[],
        'agentPresets': <Object?>[],
      };
    }
    if (widget.name == 'unavailable') {
      fixture.host.handlers['pluginInventory/list'] = (_) => {
        'entries': <Object?>[],
      };
    }
    if (widget.family == 'inventory') {
      fixture.host.handlers['pluginInventory/list'] = (_) => {
        'managementAvailable': true,
        'entries': widget.name == 'empty'
            ? <Object?>[]
            : [
                {
                  'entryId': 'synthetic-entry',
                  'moduleName': '@synthetic/reader',
                  'enabled': true,
                  'fiberPhase': 'active',
                },
              ],
        'agentPresets': <Object?>[],
      };
    }
    if (widget.family == 'market' && widget.name == 'empty') {
      fixture.host.handlers['pluginMarket/listIndexes'] = (_) => [
        {
          'url': 'https://synthetic.example/index.json',
          'status': 'ready',
          'title': 'Synthetic market',
          'description': 'Synthetic index',
          'fetchedAt': 1000,
          'entryCount': 0,
        },
      ];
      fixture.host.handlers['pluginMarket/search'] = (_) => {
        'url': 'https://synthetic.example/index.json',
        'fetchedAt': 1000,
        'title': 'Synthetic market',
        'description': 'Synthetic index',
        'metadata': {
          'categories': <String, Object?>{},
          'labels': <String, Object?>{},
          'sortKeys': <String, Object?>{},
        },
        'entries': <Object?>[],
        'total': 0,
        'nextOffset': null,
      };
    }
    if (widget.name == 'install') {
      unawaited(
        fixture.manager.load().then((_) => fixture.manager.installer.show()),
      );
    }
  }

  @override
  void dispose() {
    unawaited(fixture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('plugins-preview-surface'),
    width: widget.width,
    height: widget.height,
    child: DefaultTextStyle(
      style: context.dsh
          .textStyle('--dsw-font-s-14')
          .copyWith(color: context.dsh.labelPrimary),
      child: switch (widget.family) {
        'inventory' => PluginInventorySection(
          remotes: fixture.host.remotes,
          i18n: widget.i18n,
        ),
        'market' => PluginMarketPage(
          model: fixture.market,
          manager: fixture.manager,
          i18n: widget.i18n,
          onInstall: () {},
        ),
        _ => PluginManagerPage(
          model: fixture.manager,
          market: fixture.market,
          slots: slots,
          i18n: widget.i18n,
        ),
      },
    ),
  );
}
