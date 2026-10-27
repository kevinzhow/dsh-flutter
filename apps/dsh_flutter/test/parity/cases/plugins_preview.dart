import 'dart:async';

import 'package:dsh_client/generated_plugin_market.dart';
import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
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
        switchEnabled: ctx.props['switchEnabled'] as bool? ?? true,
        switchLocked: ctx.props['switchLocked'] as bool? ?? false,
        category: ctx.props['category'] as String?,
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
    required this.switchEnabled,
    required this.switchLocked,
    required this.category,
    required this.i18n,
  });
  final String family, name;
  final double width, height;
  final bool switchEnabled;
  final bool switchLocked;
  final String? category;
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
    fixture.enabled = widget.switchEnabled;
    fixture.locked = widget.switchLocked;
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
    if (widget.family == 'market' && widget.name == 'categories') {
      const url = 'https://synthetic.example/index.json';
      const result = MarketSearchResult(
        url: url,
        title: 'Synthetic market',
        metadata: MarketIndexMetadata(
          categories: {'tools': MarketDeclaration(title: 'Tools')},
          labels: {},
          sortKeys: {},
        ),
        fetchedAt: 1000,
        entries: [],
        total: 0,
        nextOffset: null,
      );
      fixture.host.handlers['pluginMarket/search'] = (_) => result.toJson();
      fixture.market
        ..status = PluginDiscoverStatus.ready
        ..indexes = const [
          MarketIndexSummary(url: url, title: 'Synthetic market'),
        ]
        ..selected = url
        ..listing = PluginListing(
          url: url,
          query: PluginDiscoverQuery(category: widget.category),
          status: PluginListingStatus.ready,
          value: result,
        );
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
