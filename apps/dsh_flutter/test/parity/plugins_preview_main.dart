import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_feature_documentpreview/src/pdf_body.dart';
import 'package:dsh_feature_documentpreview/src/html_body.dart';
import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/plugins_preview_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final theme = resolveTheme(
    officialPack,
    ThemeSettings(),
    const bool.fromEnvironment('PARITY_DARK') ||
            Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark'
        ? Brightness.dark
        : Brightness.light,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: theme.brightness, extensions: [theme]),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: DefaultTextStyle(
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelPrimary),
            child: Fixture(),
          ),
        ),
      ),
    ),
  );
}

class Fixture extends StatefulWidget {
  const Fixture({super.key});
  @override
  State<Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<Fixture> {
  final fixture = SyntheticPluginsPreview();
  final slots = SlotRegistry();
  final i18n = const DshI18n(DshLocale.en);
  String page = 'Plugins';
  final documents = <String, DocumentController>{};
  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
  }

  DocumentController document(String path) => documents.putIfAbsent(
    path,
    () => DocumentController(
      sessionId: 'synthetic-session',
      path: path,
      files: fixture.files,
      renderOffice: (id, path, cancellation) =>
          fixture.office.read(id, path, cancellation: cancellation),
    ),
  );
  @override
  void dispose() {
    for (final doc in documents.values) {
      doc.dispose();
    }
    unawaited(fixture.dispose());
    super.dispose();
  }

  Future<void> overlay() async {
    await showDshDialog<void>(
      context,
      label: 'Synthetic overlay',
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Synthetic overlay above preview'),
            const SizedBox(height: 20),
            DshButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close overlay'),
            ),
          ],
        ),
      ),
    );
  }

  Widget body() {
    if (page == 'Plugins') {
      return PluginManagerPage(
        model: fixture.manager,
        market: fixture.market,
        slots: slots,
        i18n: i18n,
      );
    }
    if (page == 'Inventory') {
      return PluginInventorySection(remotes: fixture.host.remotes, i18n: i18n);
    }
    final path = page == 'PDF'
        ? 'preview.pdf'
        : page == 'Office'
        ? 'preview.docx'
        : 'preview.html';
    final doc = document(path);
    return AnimatedBuilder(
      animation: doc,
      builder: (context, _) {
        if (doc.failure != null) return Center(child: Text('${doc.failure}'));
        if (!doc.hasContent) {
          return const Center(child: Text('Loading synthetic preview'));
        }
        return page == 'PDF' || page == 'Office'
            ? PdfBody(document: doc, i18n: i18n)
            : HtmlBody(
                document: doc,
                i18n: i18n,
                interactive: page == 'Interactive',
              );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 4,
          children: [
            for (final name in [
              'Plugins',
              'PDF',
              'Office',
              'HTML',
              'Interactive',
              'Inventory',
            ])
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () => setState(() => page = name),
                child: Text(name),
              ),
            DshButton(
              size: DshButtonSize.sm,
              onPressed: () => unawaited(overlay()),
              child: const Text('Overlay'),
            ),
          ],
        ),
      ),
      Expanded(child: body()),
    ],
  );
}
