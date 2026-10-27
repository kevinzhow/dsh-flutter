// Native input replay of the real shared risk route, with source copy.
import 'dart:io' show Platform;

import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

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
  final copy = DshI18n(DshLocale.fromTag('en'));
  final normalFocus = FocusNode(debugLabel: 'normal risk opener');
  final longFocus = FocusNode(debugLabel: 'long risk opener');
  final disabledFocus = FocusNode(debugLabel: 'disabled risk opener');
  String decision = 'No decision';
  int opened = 0;

  @override
  void dispose() {
    normalFocus.dispose();
    longFocus.dispose();
    disabledFocus.dispose();
    super.dispose();
  }

  Future<void> open({bool long = false, bool disabled = false}) async {
    String text(String key) => copy.t('permission.access', key);
    setState(() => opened++);
    final confirmed = await showDshRiskDialog(
      context,
      title: text('confirm.title'),
      description: List.filled(
        long ? 15 : 1,
        text('confirm.description'),
      ).join(' '),
      acknowledgeLabel: text('confirm.acknowledge'),
      cancelLabel: text('confirm.cancel'),
      closeLabel: text('close'),
      confirmLabel: text('confirm.enable'),
      disabled: disabled,
      restoreFocus: disabled
          ? disabledFocus
          : long
          ? longFocus
          : normalFocus,
    );
    if (mounted) {
      setState(() => decision = confirmed ? 'Confirmed' : 'Canceled');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DshButton(
            key: const ValueKey('open-risk-normal'),
            focusNode: normalFocus,
            onPressed: open,
            child: const Text('Open risk confirmation'),
          ),
          const SizedBox(height: 20),
          DshButton(
            key: const ValueKey('open-risk-long'),
            focusNode: longFocus,
            onPressed: () => open(long: true),
            child: const Text('Open long risk confirmation'),
          ),
          const SizedBox(height: 20),
          DshButton(
            key: const ValueKey('open-risk-disabled'),
            focusNode: disabledFocus,
            onPressed: () => open(disabled: true),
            child: const Text('Open disabled risk confirmation'),
          ),
          const SizedBox(height: 20),
          Text('Decision: $decision'),
          const SizedBox(height: 12),
          Text('Opened: $opened'),
        ],
      ),
    ),
  );
}
