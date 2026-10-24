import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dsh_feature_layout/dsh_feature_layout.dart';
import 'package:dsh_feature_shortcuts/dsh_feature_shortcuts.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'app_identity.dart';
import 'platform/pickers.dart';
import 'screens/pairing_screen.dart';

/// Composition root widget: resolves the official theme pack under the user's
/// settings and hands the contract to every component through a ThemeExtension.
/// `WHALEE_PLATFORM_BRIGHTNESS=dark|light` stands in for the system setting (a
/// Linux desktop session without a settings daemon cannot be switched): for
/// the visual parity captures, which need both themes; unset in normal use.
final Brightness? _brightnessOverride =
    switch (Platform.environment['WHALEE_PLATFORM_BRIGHTNESS']) {
      'dark' => Brightness.dark,
      'light' => Brightness.light,
      _ => null,
    };

class WhaleeApp extends StatefulWidget {
  WhaleeApp({
    super.key,
    required this.controller,
    ValueListenable<ShellChrome>? chrome,
    this.onTitle,
  }) : chrome = chrome ?? ValueNotifier(const ShellChrome());

  final AppController controller;

  /// The window chrome the frame draws around itself (see `platform/window_chrome.dart`).
  final ValueListenable<ShellChrome> chrome;

  /// Called with the window title (the open session's title and the product
  /// name) whenever it changes; the desktop window shows it.
  final ValueChanged<String>? onTitle;

  @override
  State<WhaleeApp> createState() => _WhaleeAppState();
}

class _WhaleeAppState extends State<WhaleeApp> with WidgetsBindingObserver {
  AppController get controller => widget.controller;

  String? _title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_syncTitle);
    _syncTitle();
  }

  /// dsh's `DocumentTitle`: the session's title before the product name while
  /// the Conversation is in view.
  void _syncTitle() {
    final id = controller.openSessionId;
    final title = id == null ? null : controller.sessionTitleOf(id);
    final next = title == null ? appDisplayName : '$title — $appDisplayName';
    if (next == _title) return;
    _title = next;
    widget.onTitle?.call(next);
  }

  @override
  void dispose() {
    controller.removeListener(_syncTitle);
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
            _brightnessOverride ??
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
          builder: (context, child) {
            Widget body = DshCodeHighlighting(
              highlighter: controller.highlighter,
              child: child ?? const SizedBox.shrink(),
            );
            final shortcuts = controller.shortcuts;
            if (shortcuts != null) {
              body = ShortcutKeyboardHost(service: shortcuts, child: body);
            }
            return body;
          },
          home: ValueListenableBuilder<ShellChrome>(
            valueListenable: widget.chrome,
            builder: (context, chrome, _) =>
                RootScreen(controller: controller, chrome: chrome),
          ),
        );
      },
    );
  }
}

/// Chooses the screen by connection state and form factor.
class RootScreen extends StatelessWidget {
  const RootScreen({
    super.key,
    required this.controller,
    this.chrome = const ShellChrome(),
  });

  final AppController controller;

  /// The window chrome of the desktop frame.
  final ShellChrome chrome;

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
              // dsh's frame at every width: the three columns from 1024 px, the
              // rail below, and on a phone (under 600 px) a top bar with the
              // sidebar as a drawer.
              child: AppFrame(
                layout: controller.layout,
                slots: controller.slots,
                chrome: chrome,
                phoneNewSession: () => unawaited(controller.startSession()),
                phoneMenuLabel: controller.i18n.t('sidebar', 'toggle.open'),
                phoneNewSessionLabel: controller.i18n.t(
                  'sidebar',
                  'session.new.label',
                ),
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
                      icon: CharcoalIcons.sliders,
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
