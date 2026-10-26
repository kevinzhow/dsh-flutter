import 'dart:async';
import 'dart:convert';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'document_controller.dart';

/// Complete, authorized bytes only: PDFium receives neither a Host URL nor a
/// cookie. Replacing source bytes retires the viewer and its rendering work.
class PdfBody extends StatefulWidget {
  const PdfBody({super.key, required this.document, required this.i18n});
  final DocumentController document;
  final DshI18n i18n;
  @override
  State<PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends State<PdfBody> {
  final viewer = PdfViewerController();
  String t(String key, [Map<String, Object?> p = const {}]) =>
      widget.i18n.t('sidebarPdf', key, params: p);
  Future<void> _fonts() async {
    final i18n = widget.i18n;
    final fonts = List<String>.of(widget.document.missingFonts);
    await showDshDialog<void>(
      context,
      width: 420,
      label: i18n.t('sidebarOffice', 'missingFontsTitle'),
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i18n.t('sidebarOffice', 'missingFontsTitle')),
            const SizedBox(height: 12),
            Text(i18n.t('sidebarOffice', 'missingFontsDescription')),
            const SizedBox(height: 12),
            for (final font in fonts) Text(font),
            const SizedBox(height: 20),
            DshButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(i18n.t('sidebarOffice', 'closeDetails')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final bytes = doc.bytes;
    if (bytes == null) return Center(child: Text(t('unsupported')));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () =>
                    viewer.isReady ? unawaited(viewer.zoomDown()) : null,
                child: Text(t('zoomOut')),
              ),
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () => viewer.isReady
                    ? unawaited(
                        viewer.setZoom(
                          viewer.centerPosition,
                          viewer.coverScale,
                        ),
                      )
                    : null,
                child: Text(t('zoomFitWidth')),
              ),
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () =>
                    viewer.isReady ? unawaited(viewer.zoomUp()) : null,
                child: Text(t('zoomIn')),
              ),
              if (doc.missingFonts.isNotEmpty)
                DshButton(
                  size: DshButtonSize.sm,
                  onPressed: () => unawaited(_fonts()),
                  child: Text(
                    widget.i18n.t(
                      'sidebarOffice',
                      'viewMissingFonts',
                      params: {'count': doc.missingFonts.length},
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PdfViewer.data(
            bytes,
            key: ObjectKey(bytes),
            sourceName: jsonEncode([
              doc.sessionId,
              doc.path,
              doc.version,
              doc.officeGeneration,
            ]),
            controller: viewer,
            useProgressiveLoading: false,
            params: PdfViewerParams(
              backgroundColor: context.dsh.bgBase,
              loadingBannerBuilder: (context, _, _) =>
                  Center(child: Text(t('loading'))),
              errorBannerBuilder: (context, error, stack, documentRef) =>
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t('failed', {'message': '$error'})),
                        DshButton(
                          onPressed: () => unawaited(doc.reload()),
                          child: Text(t('retry')),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}
