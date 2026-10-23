import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_attachment/dsh_feature_attachment.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  late SlotRegistry slots;
  late FakeTransport transport;
  late FakeUploadClient uploader;
  late DraftAttachments drafts;
  late SessionOwner owner;
  var i18n = const DshI18n(DshLocale.en);

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerAttachmentFeature(slots, i18n: () => i18n);
    transport = FakeTransport();
    uploader = FakeUploadClient();
    drafts = DraftAttachments(
      sessionId: 's1',
      uploader: uploader,
      limits: () => null,
    );
    owner = testSessionOwner(
      's1',
      session: Session('s1', transport),
      attachments: FakeAttachmentServices(drafts),
    );
  });

  tearDown(() => drafts.dispose());

  Widget rail() => dshTestApp(
    slots.renderSingle(
      DshSlots.conversationInputAttachments.typed<SessionOwner, Widget>(),
      owner,
    )!,
  );

  final image = Uint8List.fromList(base64Decode(_png));

  testWidgets('the rail is empty until something is added', (t) async {
    await t.pumpWidget(rail());
    expect(find.byKey(const ValueKey('composer-attachments')), findsNothing);
  });

  testWidgets(
    'images are thumbnails, files are cards with their upload state',
    (t) async {
      await t.pumpWidget(rail());
      await t.runAsync(
        () => drafts.add([
          pickedBytes('shot.png', image, type: 'image/png'),
          pickedBytes('notes.txt', Uint8List(2048), type: 'text/plain'),
        ]),
      );
      await t.pump();
      expect(find.byKey(const ValueKey('draft-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('file-card')), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('Uploading…'), findsOneWidget);

      uploader.calls.single.progress(1024);
      await t.pump();
      expect(find.byType(DshProgressTrack), findsOneWidget);
      expect(
        t.widget<DshProgressTrack>(find.byType(DshProgressTrack)).progress,
        0.5,
      );

      uploader.calls.single.succeed();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
      expect(find.text('Uploading…'), findsNothing);
      expect(find.text('TXT 2.0KB'), findsOneWidget);
    },
  );

  testWidgets('a failed upload is one retry control; retry uploads again', (
    t,
  ) async {
    await t.pumpWidget(rail());
    await t.runAsync(() => drafts.add([pickedBytes('a.txt', Uint8List(10))]));
    await t.pump();
    uploader.calls.single.fail(RemoteException('session/not-found', 'gone'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
    expect(find.text('Upload failed; click to retry'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('file-card-retry')));
    await t.pump();
    expect(uploader.calls, hasLength(2));
    expect(find.text('Uploading…'), findsOneWidget);
  });

  testWidgets('remove cancels an active upload and drops the card', (t) async {
    await t.pumpWidget(rail());
    await t.runAsync(() => drafts.add([pickedBytes('a.txt', Uint8List(10))]));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('file-card-remove')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('file-card')), findsNothing);
    expect(uploader.calls.single.cancel!.isCancelled, isTrue);
  });

  testWidgets('removing a thumbnail', (t) async {
    await t.pumpWidget(rail());
    await t.runAsync(
      () => drafts.add([pickedBytes('shot.png', image, type: 'image/png')]),
    );
    await t.pump();
    await t.tap(find.byKey(const ValueKey('draft-image-remove')));
    await t.pump();
    expect(drafts.value.items, isEmpty);
  });

  testWidgets('a thumbnail opens the lightbox, which closes again', (t) async {
    await t.pumpWidget(rail());
    await t.runAsync(
      () => drafts.add([
        pickedBytes('a.png', image, type: 'image/png'),
        pickedBytes('b.png', image, type: 'image/png'),
      ]),
    );
    await t.pump();
    await t.tap(find.byKey(const ValueKey('draft-image')).first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('lightbox-close')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('lightbox-close')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('lightbox-close')), findsNothing);
  });

  testWidgets('zh copy', (t) async {
    i18n = const DshI18n(DshLocale.zh);
    await t.pumpWidget(rail());
    await t.runAsync(() => drafts.add([pickedBytes('a.txt', Uint8List(10))]));
    await t.pump();
    expect(find.text('上传中…'), findsOneWidget);
  });

  group('image groups', () {
    ImageRef ref(String id) => ImageRef(
      attachmentId: id,
      mediaType: 'image/png',
      bytes: 70,
      width: 320,
      height: 200,
      name: 'p.png',
    );

    Widget gallery(List<GalleryImage> images, {bool compact = false}) =>
        dshTestApp(
          slots.renderSingle(
            DshSlots.conversationChatUserImages
                .typed<ImageGalleryOwner, Widget>(),
            ImageGalleryOwner(
              session: owner,
              images: images,
              compact: compact,
              alignEnd: true,
            ),
          )!,
        );

    testWidgets('a durable image loads through the session once', (t) async {
      transport.onAttachment = (s, id) async => {'data': _png};
      await t.pumpWidget(gallery([DurableGalleryImage(ref('sha256:a'))]));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(transport.attachmentReads, ['s1/sha256:a']);
      // A lone image is framed at its fit: 240 wide for 320x200.
      final size = t.getSize(find.byKey(const ValueKey('image-open')));
      expect(size.width, 240);
      expect(size.height, 150);
    });

    testWidgets('several images are 64 tiles', (t) async {
      transport.onAttachment = (s, id) async => {'data': _png};
      await t.pumpWidget(
        gallery([DurableGalleryImage(ref('a')), DurableGalleryImage(ref('b'))]),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
      for (final tile in t.widgetList(
        find.byKey(const ValueKey('image-open')),
      )) {
        expect(tile, isNotNull);
      }
      expect(
        t.getSize(find.byKey(const ValueKey('image-open')).first),
        const Size(64, 64),
      );
    });

    testWidgets('a failed load shows the retry control and retries', (t) async {
      var n = 0;
      transport.onAttachment = (s, id) async {
        n++;
        if (n == 1) throw RemoteException('transport/http-500', 'boom');
        return {'data': _png};
      };
      await t.pumpWidget(gallery([DurableGalleryImage(ref('x'))]));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
      expect(find.byKey(const ValueKey('image-retry')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('image-retry')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
      expect(find.byKey(const ValueKey('image-retry')), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a local preview shows without any read', (t) async {
      await t.pumpWidget(
        gallery([
          PreviewGalleryImage(image, name: 'p.png', width: 1, height: 1),
        ]),
      );
      await t.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(transport.attachmentReads, isEmpty);
    });

    testWidgets('tapping opens the lightbox on the original', (t) async {
      transport.onAttachment = (s, id) async => {'data': _png};
      await t.pumpWidget(gallery([DurableGalleryImage(ref('sha256:a'))]));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('image-open')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('lightbox-image')), findsOneWidget);
    });
  });
}
