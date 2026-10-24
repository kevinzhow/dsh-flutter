import 'package:desktop_drop/desktop_drop.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'app_identity.dart';
import 'platform/pickers.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_screen.dart';
import 'screens/new_session_screen.dart';
import 'screens/sessions_screen.dart';

/// Width from which the app shows the list and the session side by side.
const double wideBreakpoint = 840;

/// Composition root widget: resolves the official theme pack under the user's
/// settings and hands the contract to every component through a ThemeExtension.
class WhaleeApp extends StatefulWidget {
  const WhaleeApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<WhaleeApp> createState() => _WhaleeAppState();
}

class _WhaleeAppState extends State<WhaleeApp> with WidgetsBindingObserver {
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Only a resumed app is in front of the user: from every other state a
  /// session that needs them is told through a notification.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      controller.setForeground(state == AppLifecycleState.resumed);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final platform =
            MediaQuery.maybePlatformBrightnessOf(context) ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        final dsh = resolveTheme(
          officialPack,
          controller.themeSettings,
          platform,
        );
        return MaterialApp(
          navigatorKey: controller.navigatorKey,
          title: appDisplayName,
          debugShowCheckedModeBanner: false,
          locale: Locale(controller.locale.name),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
            brightness: dsh.brightness,
            scaffoldBackgroundColor: dsh.bgBase,
            canvasColor: dsh.bgBase,
            extensions: [dsh],
          ),
          // Above the navigator, so sheets and the lightbox highlight too.
          builder: (context, child) => DshCodeHighlighting(
            highlighter: controller.highlighter,
            child: child ?? const SizedBox.shrink(),
          ),
          home: RootScreen(controller: controller),
        );
      },
    );
  }
}

/// Chooses the screen by connection state and form factor.
class RootScreen extends StatelessWidget {
  const RootScreen({super.key, required this.controller});

  final AppController controller;

  void _settings(BuildContext context) => controller.openSettings();

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    // The sessions stay on screen for as long as they exist: while the
    // connection is retried, and while the user pairs again after a restart
    // (their unsent messages live in this tree).
    final connected =
        controller.manager != null &&
        controller.phase != ConnectionPhase.disconnected;
    return Scaffold(
      backgroundColor: theme.bgBase,
      body: connected
          ? _DropArea(
              controller: controller,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= wideBreakpoint;
                  return wide
                      ? _Wide(
                          controller: controller,
                          onSettings: () => _settings(context),
                        )
                      : _Narrow(
                          controller: controller,
                          onSettings: () => _settings(context),
                        );
                },
              ),
            )
          : Stack(
              children: [
                PairingScreen(controller: controller),
                Positioned(
                  right: DshSpace.sm,
                  top: DshSpace.sm,
                  child: SafeArea(
                    child: DshIconButton(
                      key: const ValueKey('pairing-settings'),
                      icon: Icons.tune,
                      plain: true,
                      semanticLabel: controller.i18n.t('settings', 'trigger'),
                      onPressed: () => _settings(context),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Phone layout: the list, and a session pushed over it.
class _Narrow extends StatelessWidget {
  const _Narrow({required this.controller, required this.onSettings});

  final AppController controller;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final session = controller.openSession;
    final fresh = session == null && controller.newSessionPending;
    return PopScope(
      canPop: session == null && !fresh,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.closeSession();
      },
      child: session != null
          ? SessionView(
              key: ValueKey('session-${session.sessionId}'),
              controller: controller,
              session: session,
              onBack: controller.closeSession,
            )
          : fresh
          ? NewSessionView(
              controller: controller,
              onBack: controller.closeSession,
            )
          : SessionsPane(
              controller: controller,
              onOpen: controller.open,
              onSettings: onSettings,
            ),
    );
  }
}

/// Tablet and desktop layout: the list on the left, the session on the right.
class _Wide extends StatelessWidget {
  const _Wide({required this.controller, required this.onSettings});

  final AppController controller;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final session = controller.openSession;
    return Row(
      children: [
        SizedBox(
          width: 340,
          child: SessionsPane(
            controller: controller,
            onOpen: controller.open,
            onSettings: onSettings,
          ),
        ),
        VerticalDivider(
          width: dshHairlineOf(context),
          thickness: dshHairlineOf(context),
          color: theme.color('--dsw-alias-border-l4'),
        ),
        Expanded(
          child: session == null
              ? (controller.newSessionPending
                    ? NewSessionView(controller: controller)
                    : const SizedBox.shrink())
              : SessionView(
                  key: ValueKey('session-${session.sessionId}'),
                  controller: controller,
                  session: session,
                ),
        ),
      ],
    );
  }
}

/// Desktop windows take files dropped anywhere on them: the composer of the
/// session in view adds them, and an overlay invites the drop meanwhile (dsh
/// `ComposerAttachments` drop target). Phones have no drag and drop: the child
/// is returned as is.
class _DropArea extends StatefulWidget {
  const _DropArea({required this.controller, required this.child});

  final AppController controller;
  final Widget child;

  @override
  State<_DropArea> createState() => _DropAreaState();
}

class _DropAreaState extends State<_DropArea> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.platform.acceptsDrops) return widget.child;
    final session = controller.openSession;
    final accepting = session != null && !session.readOnly;
    final limits = session == null
        ? null
        : ImageLimits.tryParse(session.session.projections.get('imageLimits'));
    String c(String key, [Map<String, Object?> params = const {}]) =>
        controller.i18n.t('conversation', key, params: params);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        if (!accepting) return;
        final files = [for (final f in details.files) await pickedFromXFile(f)];
        controller.dropFiles(files);
      },
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_dragging)
            Positioned.fill(
              child: DshDropOverlay(
                title: accepting
                    ? c('attachment.dropTitle')
                    : c('attachment.dropBlocked'),
                desc: accepting && limits != null
                    ? c('attachment.dropDesc', {
                        'count': limits.maxImagesPerMessage,
                        'size': imageSizeText(limits.maxImageBytes),
                      })
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// dsh `imageSizeText`: bytes as megabytes (`10MB`, `2.5MB`).
String imageSizeText(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb == mb.truncateToDouble() ? mb.toInt() : mb.toStringAsFixed(1)}MB';
}
