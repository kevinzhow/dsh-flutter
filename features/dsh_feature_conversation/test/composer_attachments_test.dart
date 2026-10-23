import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeActions actions;
  late Session session;
  late FakeUploadClient uploader;
  late DraftAttachments drafts;
  late FakePicker picker;
  late FakeAttachmentServices services;
  late SessionOwner owner;
  var i18n = const DshI18n(DshLocale.en);

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    actions = FakeActions();
    session = Session('s1', FakeTransport());
    uploader = FakeUploadClient();
    drafts = DraftAttachments(
      sessionId: 's1',
      uploader: uploader,
      limits: () =>
          ImageLimits.tryParse(session.projections.get('imageLimits')),
    );
    picker = FakePicker();
    services = FakeAttachmentServices(drafts, picker: picker);
    owner = testSessionOwner(
      's1',
      session: session,
      actions: actions,
      attachments: services,
    );
  });
  tearDown(() => drafts.dispose());

  Widget composer() => dshTestApp(DefaultComposer(owner: owner, i18n: i18n));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }

  Future<void> addDrafts(WidgetTester t, List<LocalFile> files) async {
    await t.runAsync(() => drafts.add(files));
    await t.pump();
  }

  final png = Uint8List.fromList([1, 2, 3]);

  testWidgets('there is no attach control without a picker', (t) async {
    owner = testSessionOwner('s1', session: session, actions: actions);
    await t.pumpWidget(composer());
    expect(find.byKey(const ValueKey('composer-attach')), findsNothing);
  });

  testWidgets('a single source opens the picker straight away', (t) async {
    picker = FakePicker(
      sources: const [AttachSource.files],
      result: [pickedBytes('a.txt', Uint8List(4))],
    );
    services = FakeAttachmentServices(drafts, picker: picker);
    owner = testSessionOwner(
      's1',
      session: session,
      actions: actions,
      attachments: services,
    );
    await t.pumpWidget(composer());
    await t.tap(find.byKey(const ValueKey('composer-attach')));
    await settle(t);
    expect(picker.picked, [AttachSource.files]);
    expect(drafts.value.items.single.name, 'a.txt');
    expect(uploader.calls, hasLength(1));
  });

  testWidgets('phones choose between photos, camera and files', (t) async {
    picker = FakePicker(
      sources: const [
        AttachSource.photos,
        AttachSource.camera,
        AttachSource.files,
      ],
      result: [pickedBytes('p.png', png, type: 'image/png')],
    );
    services = FakeAttachmentServices(drafts, picker: picker);
    owner = testSessionOwner(
      's1',
      session: session,
      actions: actions,
      attachments: services,
    );
    await t.pumpWidget(composer());
    await t.tap(find.byKey(const ValueKey('composer-attach')));
    await t.pumpAndSettle();
    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('attach-photos')));
    await t.pumpAndSettle();
    await settle(t);
    expect(picker.picked, [AttachSource.photos]);
    expect(drafts.value.items.single, isA<DraftImage>());
  });

  testWidgets('a cancelled pick adds nothing', (t) async {
    picker = FakePicker(sources: const [AttachSource.files]);
    services = FakeAttachmentServices(drafts, picker: picker);
    owner = testSessionOwner(
      's1',
      session: session,
      actions: actions,
      attachments: services,
    );
    await t.pumpWidget(composer());
    await t.tap(find.byKey(const ValueKey('composer-attach')));
    await settle(t);
    expect(drafts.value.isEmpty, isTrue);
  });

  testWidgets('files dropped on the window are added like picked ones', (
    t,
  ) async {
    await t.pumpWidget(composer());
    services.dropController.add([pickedBytes('dropped.md', Uint8List(3))]);
    await settle(t);
    expect(drafts.value.items.single.name, 'dropped.md');
  });

  testWidgets('send waits for uploads; an attachment alone can be sent', (
    t,
  ) async {
    await t.pumpWidget(composer());
    final send = find.byKey(const ValueKey('composer-send'));
    await addDrafts(t, [pickedBytes('a.txt', Uint8List(4))]);
    await t.tap(send);
    await t.pump();
    expect(actions.sent, isEmpty, reason: 'still uploading');
    uploader.calls.single.succeed(receipt: 'rc1');
    await settle(t);
    await t.tap(send);
    await settle(t);
    expect(actions.sent, ['']);
    final sent = actions.sentAttachments.single.single as OutgoingFile;
    expect(sent.receiptId, 'rc1');
    expect(drafts.value.isEmpty, isTrue, reason: 'cleared after the send');
  });

  testWidgets('images and text go together, drafts clear', (t) async {
    await t.pumpWidget(composer());
    await addDrafts(t, [pickedBytes('p.png', png, type: 'image/png')]);
    await t.enterText(find.byType(EditableText), 'look');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('composer-send')));
    await settle(t);
    expect(actions.sent, ['look']);
    final image = actions.sentAttachments.single.single as OutgoingImage;
    expect(image.bytes, png);
    expect(image.mediaType, 'image/png');
    expect(drafts.value.isEmpty, isTrue);
  });

  testWidgets('a refused send keeps the drafts and names the limit', (t) async {
    session.projections.seed(1, {
      'imageLimits': {
        'maxImageBytes': 20971520,
        'maxImagesPerMessage': 20,
        'maxMessageImageBytes': 209715200,
        'maxImagePixels': 64000000,
        'maxImageDimension': 8192,
        'mediaTypes': ['image/png'],
      },
    });
    actions.failSend = RemoteException('session/attachment-invalid', 'no', {
      'reason': 'IMAGE_TOO_LARGE',
    });
    await t.pumpWidget(composer());
    await addDrafts(t, [pickedBytes('p.png', png, type: 'image/png')]);
    await t.tap(find.byKey(const ValueKey('composer-send')));
    await settle(t);
    expect(find.text('Each image must be smaller than 20MB'), findsOneWidget);
    expect(drafts.value.items, hasLength(1));
  });

  testWidgets('an intake refusal explains the limit and adds nothing', (
    t,
  ) async {
    session.projections.seed(1, {
      'imageLimits': {
        'maxImageBytes': 2621440,
        'maxImagesPerMessage': 20,
        'maxMessageImageBytes': 209715200,
        'maxImagePixels': 64000000,
        'maxImageDimension': 8192,
        'mediaTypes': ['image/png'],
      },
    });
    picker = FakePicker(
      sources: const [AttachSource.photos],
      result: [pickedBytes('big.png', Uint8List(2621441), type: 'image/png')],
    );
    services = FakeAttachmentServices(drafts, picker: picker);
    owner = testSessionOwner(
      's1',
      session: session,
      actions: actions,
      attachments: services,
    );
    await t.pumpWidget(composer());
    await t.tap(find.byKey(const ValueKey('composer-attach')));
    await settle(t);
    expect(find.text('Each image must be smaller than 2.5MB'), findsOneWidget);
    expect(drafts.value.isEmpty, isTrue);
  });

  testWidgets('zh attach sheet', (t) async {
    i18n = const DshI18n(DshLocale.zh);
    picker = FakePicker(
      sources: const [AttachSource.photos, AttachSource.files],
    );
    services = FakeAttachmentServices(drafts, picker: picker);
    owner = testSessionOwner(
      's1',
      session: session,
      actions: actions,
      attachments: services,
    );
    await t.pumpWidget(composer());
    await t.tap(find.byKey(const ValueKey('composer-attach')));
    await t.pumpAndSettle();
    expect(find.text('相册'), findsOneWidget);
  });
}
