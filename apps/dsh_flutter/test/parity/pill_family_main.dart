// Native replay of the actual market category consumer and a disabled pill.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_client/generated_plugin_market.dart';
import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/plugins_preview_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final brightness =
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark'
      ? Brightness.dark
      : Brightness.light;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      home: Scaffold(backgroundColor: theme.bgBase, body: const _Scene()),
    ),
  );
}

class _Scene extends StatefulWidget {
  const _Scene();
  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  final fixture = SyntheticPluginsPreview();
  int disabledCalls = 0;

  @override
  void initState() {
    super.initState();
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
      ..listing = const PluginListing(
        url: url,
        query: PluginDiscoverQuery(),
        status: PluginListingStatus.ready,
        value: result,
      );
  }

  @override
  void dispose() {
    unawaited(fixture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DshPill(
            enabled: false,
            onPressed: () => setState(() => disabledCalls++),
            child: const Text('Locked category'),
          ),
          Text('Locked activations: $disabledCalls'),
          const SizedBox(height: 16),
          PluginMarketPage(
            model: fixture.market,
            manager: fixture.manager,
            i18n: const DshI18n(DshLocale.en),
            onInstall: () {},
          ),
        ],
      ),
    ),
  );
}
