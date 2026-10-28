// Actual migrated manager with offline synthetic model data. The toolbar and
// function keys select data/setup only; all card/switch/navigation actions are
// the real feature widgets. Highlight/sticky hover/image formats stay pending.
import 'dart:async';
import 'dart:io';

import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'helpers/plugin_card_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No metadata image can create an external request in this synthetic app.
  HttpOverrides.global = _OfflineHttpOverrides();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  runApp(
    PluginCardsNativeApp(brightness: dark ? Brightness.dark : Brightness.light),
  );
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

class _OfflineHttpClient implements HttpClient {
  @override
  bool autoUncompress = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) => Future.error(
    StateError('Synthetic card fixture denies external image requests'),
  );
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Network operation is outside the synthetic card fixture',
  );
}

class PluginCardsNativeApp extends StatefulWidget {
  const PluginCardsNativeApp({super.key, required this.brightness});
  final Brightness brightness;

  @override
  State<PluginCardsNativeApp> createState() => _PluginCardsNativeAppState();
}

class _PluginCardsNativeAppState extends State<PluginCardsNativeApp> {
  static const scenes = <String, String>{
    'Default': 'default',
    'Locked': 'error-disabled',
    'Refused': 'refused-toggle',
    'Wrap': 'long-tags',
    'Image': 'image-failed',
    'No description': 'no-description',
    'Metadata': 'metadata-error',
  };
  final _scope = FocusScopeNode(debugLabel: 'actual loaded-card manager');
  final _slots = SlotRegistry();
  final _i18n = const DshI18n(DshLocale.en);
  late SyntheticPluginCardFixture _fixture;
  StreamSubscription<int>? _subscription;
  String _scenario = 'default';
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      _slots.declare(slot);
    }
    _attach();
  }

  void _attach() {
    _fixture = SyntheticPluginCardFixture.fromId(_scenario);
    _subscription = _fixture.manager.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
  }

  void _select(String id) {
    final old = _fixture;
    unawaited(_subscription?.cancel());
    setState(() {
      _scenario = id;
      _generation++;
      _attach();
    });
    unawaited(old.dispose());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_fixture.dispose());
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = resolveTheme(
      officialPack,
      ThemeSettings(),
      widget.brightness,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f6): () => _select('default'),
        const SingleActivator(LogicalKeyboardKey.f7): () =>
            _select('error-disabled'),
        const SingleActivator(LogicalKeyboardKey.f8): () =>
            _select('refused-toggle'),
        const SingleActivator(LogicalKeyboardKey.f9): () =>
            _select('long-tags'),
        const SingleActivator(LogicalKeyboardKey.f10): () =>
            _select('image-failed'),
        const SingleActivator(LogicalKeyboardKey.f11): () =>
            _select('no-description'),
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            _select('metadata-error'),
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: widget.brightness, extensions: [theme]),
        home: Scaffold(
          backgroundColor: theme.bgBase,
          body: SafeArea(
            child: DefaultTextStyle(
              style: theme
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(color: theme.labelPrimary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeFocus(
                    child: Padding(
                      padding: const EdgeInsets.all(DshSpace.sm),
                      child: Wrap(
                        spacing: DshSpace.xs,
                        runSpacing: DshSpace.xs,
                        children: [
                          for (final entry in scenes.entries)
                            DshButton(
                              key: ValueKey('card-scene-${entry.value}'),
                              size: DshButtonSize.sm,
                              onPressed: () => _select(entry.value),
                              child: Text(entry.key),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text('Card scenario: $_scenario', maxLines: 1),
                  ),
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text(
                      'Requests: ${_fixture.attempts} refused: ${_fixture.refusals} '
                      'enabled: ${_fixture.enabled ? 'on' : 'off'}',
                      maxLines: 1,
                    ),
                  ),
                  const Text('Services: synthetic offline', maxLines: 1),
                  Expanded(
                    child: FocusScope(
                      node: _scope,
                      child: DshSurface(
                        color: theme.bgBase,
                        child: PluginManagerPage(
                          key: ValueKey('actual-card-manager-$_generation'),
                          model: _fixture.manager,
                          market: _fixture.market,
                          slots: _slots,
                          i18n: _i18n,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
