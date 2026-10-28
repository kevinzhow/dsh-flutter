// Native route-adoption proof, not Web pairing/camera/network parity.
// F6/F7 push the real repair/scanner routes. F8 returns to pairing for setup.
// Every accepted action uses its real production DshButton and callback.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_flutter/src/screens/pairing_screen.dart';
import 'package:dsh_flutter/src/screens/qr_scanner_screen.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  runApp(
    IconActionsNativeApp(brightness: dark ? Brightness.dark : Brightness.light),
  );
}

class IconActionsNativeApp extends StatefulWidget {
  const IconActionsNativeApp({super.key, required this.brightness});
  final Brightness brightness;

  @override
  State<IconActionsNativeApp> createState() => _IconActionsNativeAppState();
}

class _Trace extends ChangeNotifier {
  int settings = 0, back = 0, close = 0, network = 0;
  String route = 'pairing';
  bool setup = false, _pending = false, _disposed = false;

  void changed() {
    if (_pending || _disposed) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _Routes extends NavigatorObserver {
  _Routes(this.trace);
  final _Trace trace;

  String name(Route<dynamic>? route) => switch (route?.settings.name) {
    '/' => 'pairing',
    'fixture.repair' => 'repair',
    'fixture.scanner' => 'scanner',
    _ => 'settings',
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    trace.route = name(route);
    trace.changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!trace.setup) {
      if (route.settings.name == 'fixture.repair') trace.back++;
      if (route.settings.name == 'fixture.scanner') trace.close++;
    }
    trace.route = name(previousRoute);
    trace.changed();
  }
}

class _Controller extends AppController {
  _Controller(this.trace, HostBackend backend)
    : super(backend: backend, locale: DshLocale.en);
  final _Trace trace;

  @override
  void openSettings({String? section}) {
    trace.settings++;
    trace.changed();
    super.openSettings(section: section);
  }
}

// Only constructor-time offline services are supplied. Any unexpected host
// operation fails instead of opening a socket or masquerading as network proof.
class _OfflineBackend implements HostBackend {
  _OfflineBackend(this.trace);
  final _Trace trace;
  final terminals = FakeTerminalHost();
  @override
  final trust = HostTrust();
  @override
  final DeliverablesClient deliverables = _UnusedDeliverables();
  @override
  final OpenInAppClient openInApp = _UnusedApplications();
  @override
  TerminalHost get terminalHost => terminals.terminalHost;
  @override
  Stream<ConnectionStatus> get statuses => const Stream.empty();
  @override
  Future<void> dispose() => terminals.close();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    trace.network++;
    trace.changed();
    throw StateError('Outside icon-action fixture: ${invocation.memberName}');
  }
}

class _UnusedDeliverables implements DeliverablesClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Deliverables are outside the icon-action fixture');
}

class _UnusedApplications implements OpenInAppClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Application launch is outside the icon-action fixture');
}

class _Camera implements QrCamera {
  const _Camera();
  @override
  Widget preview(
    BuildContext context, {
    required void Function(String raw) onCode,
    required Widget Function(CameraProblem problem) problem,
  }) => ColoredBox(
    color: context.dsh.bgBase,
    child: const Center(child: Text('Synthetic camera preview')),
  );
}

class _IconActionsNativeAppState extends State<IconActionsNativeApp> {
  final _trace = _Trace();
  late final _controller = _Controller(_trace, _OfflineBackend(_trace));
  late final _routes = _Routes(_trace);

  void _pairing() {
    _trace.setup = true;
    _controller.navigatorKey.currentState!.popUntil((route) => route.isFirst);
    _trace.setup = false;
  }

  void _push(bool scanner) {
    _pairing();
    unawaited(
      _controller.navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            name: scanner ? 'fixture.scanner' : 'fixture.repair',
          ),
          builder: (_) => scanner
              ? QrScannerScreen(
                  camera: const _Camera(),
                  i18n: const DshI18n(DshLocale.en),
                  openSystemSettings: () {},
                )
              : RepairRoute(controller: _controller),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _trace.dispose();
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
        const SingleActivator(LogicalKeyboardKey.f6): () => _push(false),
        const SingleActivator(LogicalKeyboardKey.f7): () => _push(true),
        const SingleActivator(LogicalKeyboardKey.f8): _pairing,
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: _controller.navigatorKey,
        navigatorObservers: [_routes],
        theme: ThemeData(brightness: widget.brightness, extensions: [theme]),
        home: RootScreen(controller: _controller),
        builder: (context, child) => Stack(
          children: [
            child!,
            // Passive diagnostics paint after Navigator semantics. There is
            // no substitute action button or production test-flag branch.
            Positioned(
              top: DshIconActionRecipe.height * 2,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SafeArea(
                  bottom: false,
                  child: AnimatedBuilder(
                    animation: _trace,
                    builder: (_, _) => Semantics(
                      container: true,
                      liveRegion: true,
                      child: DefaultTextStyle(
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(color: theme.labelPrimary),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Native actions: settings=${_trace.settings} '
                              'back=${_trace.back} close=${_trace.close}',
                            ),
                            Text(
                              'Native route: ${_trace.route}; '
                              'network=${_trace.network}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
