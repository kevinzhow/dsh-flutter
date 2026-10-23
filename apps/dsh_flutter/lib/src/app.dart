import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'app_identity.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_sheet.dart';

/// Width from which the app shows the list and the session side by side.
const double wideBreakpoint = 840;

/// Composition root widget: resolves the official theme pack under the user's
/// settings and hands the contract to every component through a ThemeExtension.
class WhaleeApp extends StatelessWidget {
  const WhaleeApp({super.key, required this.controller});

  final AppController controller;

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

  void _settings(BuildContext context) {
    final theme = context.dsh;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.color('--dsw-alias-bg-layer-2'),
      builder: (_) => SettingsSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final connected =
        controller.phase == ConnectionPhase.connected ||
        (controller.phase == ConnectionPhase.connecting &&
            controller.manager != null);
    return Scaffold(
      backgroundColor: theme.bgBase,
      body: connected
          ? LayoutBuilder(
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
                      semanticLabel: controller.i18n.t(
                        appNamespace,
                        'settings.title',
                      ),
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
    return PopScope(
      canPop: session == null,
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
          width: 0.5,
          thickness: 0.5,
          color: theme.color('--dsw-alias-border-l4'),
        ),
        Expanded(
          child: session == null
              ? const SizedBox.shrink()
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
