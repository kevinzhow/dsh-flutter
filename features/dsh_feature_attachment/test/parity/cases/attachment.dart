// dsh's attachment surfaces (ui-attachment) with the Flutter widgets of dsh_ui, labelled from the real conversation
// dictionary the way the feature does. Props are the React host's (tool/parity-ext/build-attachment.py):
//   attachment.chip     DshFileCard
//   attachment.draft    DshDraftImage and DshFileCard on the composer rail's geometry (padding 2/10, 64 high, 10 apart)
//   attachment.gallery  DshImageGroup of DshImageFrame, the variant chosen by dsh's rule (thumbnail, else compact or
//                       several images: tile, else single)
import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_feature_attachment/dsh_feature_attachment.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

DshI18n _i18n(ParityContext ctx) => DshI18n(DshLocale.fromTag(ctx.locale));

String _c(DshI18n i18n, String key, [Map<String, Object?> params = const {}]) =>
    i18n.t('conversation', key, params: params);

DshFileCardState _state(String? name) => switch (name) {
  'uploading' => DshFileCardState.uploading,
  'error' => DshFileCardState.error,
  _ => DshFileCardState.ready,
};

DshFileCard _fileCard(DshI18n i18n, Map<String, dynamic> item) {
  final name = item['name'] as String;
  return DshFileCard(
    name: name,
    bytes: (item['bytes'] as num).toInt(),
    state: _state(item['state'] as String?),
    progress: (item['progress'] as num?)?.toDouble(),
    labels: DshFileCardLabels(
      label: _c(i18n, 'file.pending'),
      remove: _c(i18n, 'file.remove', {'name': name}),
      uploading: _c(i18n, 'file.uploading'),
      failed: _c(i18n, 'file.uploadFailed'),
      retry: _c(i18n, 'file.retry', {'name': name}),
    ),
    onRemove: () {},
    onRetry: () {},
  );
}

Uint8List _bytes(Object? base64) => base64Decode(base64 as String);

final Map<String, ParityCase> attachmentCases = {
  'attachment.chip': ParityCase(
    widgets: const ['dsh_ui:DshFileCard'],
    interact: (tester, ctx) => precacheTreeImages(tester),
    build: (ctx) {
      final i18n = _i18n(ctx);
      return ParityStack(
        layout: ctx.layout,
        children: [
          for (final item
              in (ctx.props['items'] as List).cast<Map<String, dynamic>>())
            parityItem(item['id'] as String, _fileCard(i18n, item)),
        ],
      );
    },
  ),
  'attachment.draft': ParityCase(
    widgets: const ['dsh_ui:DshDraftImage', 'dsh_ui:DshFileCard'],
    notes:
        'The rail container is the case: padding 2/10, 64 high, 10 apart, '
        'rails 12 - 6 apart (the -6 margin of dsh ComposerAttachments).',
    interact: (tester, ctx) => precacheTreeImages(tester),
    build: (ctx) {
      final i18n = _i18n(ctx);
      final images = (ctx.props['images'] as Map).cast<String, dynamic>();
      final rails = (ctx.props['rails'] as List).cast<Map<String, dynamic>>();
      Widget rail(List<Map<String, dynamic>> items) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
        child: SizedBox(
          height: 64,
          child: Row(
            spacing: 10,
            children: [
              for (final item in items)
                parityItem(
                  item['id'] as String,
                  item['kind'] == 'image'
                      ? DshDraftImage(
                          bytes: _bytes(images[item['image']]),
                          name: item['name'] as String,
                          openLabel: _c(i18n, 'image.openOriginal'),
                          removeLabel: _c(i18n, 'image.remove', {
                            'name': item['name'],
                          }),
                          onOpen: () {},
                          onRemove: () {},
                        )
                      : _fileCard(i18n, item),
                ),
            ],
          ),
        ),
      );
      return SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: ctx.layout.gap - 6,
          children: [
            for (final r in rails)
              rail((r['items'] as List).cast<Map<String, dynamic>>()),
          ],
        ),
      );
    },
  ),
  'attachment.gallery': ParityCase(
    widgets: const ['dsh_ui:DshImageGroup', 'dsh_ui:DshImageFrame'],
    interact: (tester, ctx) => precacheTreeImages(tester),
    build: (ctx) {
      final i18n = _i18n(ctx);
      final labels = imageLabels(i18n);
      final images = (ctx.props['images'] as Map).cast<String, dynamic>();
      return ParityStack(
        layout: ctx.layout,
        children: [
          for (final g
              in (ctx.props['galleries'] as List).cast<Map<String, dynamic>>())
            () {
              final items = (g['items'] as List).cast<Map<String, dynamic>>();
              final variant = g['thumbnail'] == true
                  ? DshImageVariant.thumbnail
                  : g['compact'] == true || items.length > 1
                  ? DshImageVariant.tile
                  : DshImageVariant.single;
              return DshImageGroup(
                alignEnd: g['align'] == 'end',
                children: [
                  for (final item in items)
                    parityItem('${g['id']}-${item['id']}', () {
                      final source = (images[item['image']] as Map)
                          .cast<String, dynamic>();
                      final state = item['state'] as String;
                      return DshImageFrame(
                        variant: variant,
                        labels: labels,
                        bytes: state == 'loaded'
                            ? _bytes(source['base64'])
                            : null,
                        failed: state == 'failed',
                        width: (source['width'] as num).toInt(),
                        height: (source['height'] as num).toInt(),
                        name: item['name'] as String?,
                        onOpen: () {},
                        onRetry: () {},
                      );
                    }()),
                ],
              );
            }(),
        ],
      );
    },
  ),
};
