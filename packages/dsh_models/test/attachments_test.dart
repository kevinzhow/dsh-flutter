import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

/// A scriptable upload transport: tests complete, fail or stall each call.
class FakeUploader implements FileUploadClient {
  final List<UploadCall> calls = [];

  @override
  Future<FileUploadReceipt> upload({
    required String sessionId,
    required Stream<List<int>> data,
    int? length,
    String? name,
    UploadCancelToken? cancel,
    void Function(UploadProgress progress)? onProgress,
  }) {
    final call = UploadCall(sessionId, name, length, cancel, onProgress);
    calls.add(call);
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (!call.done.isCompleted) {
          call.done.completeError(const UploadCancelled());
        }
      }),
    );
    return call.done.future;
  }
}

class UploadCall {
  UploadCall(
    this.sessionId,
    this.name,
    this.length,
    this.cancel,
    this.onProgress,
  );
  final String sessionId;
  final String? name;
  final int? length;
  final UploadCancelToken? cancel;
  final void Function(UploadProgress)? onProgress;
  final Completer<FileUploadReceipt> done = Completer();

  void succeed({String receipt = 'rcpt', int? bytes}) => done.complete(
    FileUploadReceipt(
      receiptId: receipt,
      attachmentId: 'sha256:$receipt',
      name: name ?? 'f',
      bytes: bytes ?? length ?? 0,
    ),
  );
  void fail(Object e) => done.completeError(e);
}

LocalFile file(String name, int size, {String? type, Uint8List? bytes}) =>
    LocalFile(
      name: name,
      size: size,
      mediaType: type,
      open: () => Stream.value(bytes ?? Uint8List(size)),
      read: () async => bytes ?? Uint8List(size),
    );

const limits = ImageLimits(
  maxImageBytes: 1000,
  maxImagesPerMessage: 3,
  maxMessageImageBytes: 2000,
  maxImagePixels: 64000000,
  maxImageDimension: 8192,
  mediaTypes: imageMediaTypes,
);

void main() {
  group('classification', () {
    test('only png, jpeg, webp and gif are images', () {
      expect(isImageMediaType('image/png'), isTrue);
      expect(isImageMediaType('image/jpeg'), isTrue);
      expect(isImageMediaType('image/webp'), isTrue);
      expect(isImageMediaType('image/gif'), isTrue);
      expect(isImageMediaType('image/heic'), isFalse);
      expect(isImageMediaType('image/svg+xml'), isFalse);
      expect(isImageMediaType('application/pdf'), isFalse);
      expect(isImageMediaType(null), isFalse);
    });

    test('a picker without a MIME type is classified by extension', () {
      expect(file('a.PNG', 1).imageType, 'image/png');
      expect(file('a.jpeg', 1, type: '').imageType, 'image/jpeg');
      expect(file('a.heic', 1).imageType, isNull);
      expect(file('a.txt', 1).imageType, isNull);
      // A declared non-image type wins over the extension (dsh: file.type).
      expect(file('a.png', 1, type: 'text/plain').imageType, isNull);
    });

    test('references parse strictly', () {
      final ok = ImageRef.tryParse({
        'attachmentId': 'sha256:a',
        'mediaType': 'image/png',
        'bytes': 10,
        'width': 3,
        'height': 4,
        'name': 'x.png',
      });
      expect(ok?.width, 3);
      expect(ok?.name, 'x.png');
      expect(
        ImageRef.tryParse({
          'attachmentId': 'a',
          'mediaType': 'image/heic',
          'bytes': 1,
          'width': 1,
          'height': 1,
        }),
        isNull,
      );
      expect(
        ImageRef.tryParse({
          'attachmentId': '',
          'mediaType': 'image/png',
          'bytes': 1,
          'width': 1,
          'height': 1,
        }),
        isNull,
      );
      expect(
        ImageRef.tryParse({
          'attachmentId': 'a',
          'mediaType': 'image/png',
          'bytes': 1,
          'width': 0,
          'height': 1,
        }),
        isNull,
      );
      expect(ImageRef.tryParse('x'), isNull);
      expect(
        FileRef.tryParse({'attachmentId': 'a', 'name': 'n.txt', 'bytes': 0})
            ?.name,
        'n.txt',
      );
      expect(FileRef.tryParse({'attachmentId': 'a', 'name': 'n'}), isNull);
    });

    test('limits parse from the projection', () {
      final l = ImageLimits.tryParse({
        'maxImageBytes': 20971520,
        'maxImagesPerMessage': 20,
        'maxMessageImageBytes': 209715200,
        'maxImagePixels': 64000000,
        'maxImageDimension': 8192,
        'mediaTypes': ['image/png'],
      });
      expect(l?.maxImagesPerMessage, 20);
      expect(ImageLimits.tryParse({'maxImageBytes': 1}), isNull);
      expect(ImageLimits.tryParse(null), isNull);
    });
  });

  group('DraftAttachments', () {
    late FakeUploader up;
    late DraftAttachments drafts;
    ImageLimits? current = limits;

    setUp(() {
      up = FakeUploader();
      current = limits;
      drafts = DraftAttachments(
        sessionId: 'sess',
        uploader: up,
        limits: () => current,
        probe: (bytes) async => (width: 7, height: 5),
      );
    });
    tearDown(() => drafts.dispose());

    test('images become inline drafts with probed dimensions, files upload at once', () async {
      final r = await drafts.add([
        file('a.png', 10, type: 'image/png'),
        file('notes.txt', 20, type: 'text/plain'),
      ]);
      expect(r.refusal, isNull);
      expect(r.added, hasLength(2));
      final image = drafts.value.items[0] as DraftImage;
      expect(image.width, 7);
      expect(image.mediaType, 'image/png');
      expect(drafts.value.items[1], isA<DraftFile>());
      expect(up.calls, hasLength(1));
      expect(up.calls.single.name, 'notes.txt');
      expect(up.calls.single.length, 20);
      expect(
        drafts.value.uploads[drafts.value.items[1].id],
        isA<FileUploading>(),
      );
      expect(drafts.value.uploadsPending, isTrue);
    });

    test('the upload progress, receipt and freeze keep pick order', () async {
      await drafts.add([
        file('a.txt', 100),
        file('b.png', 10, type: 'image/png'),
        file('c.txt', 50),
      ]);
      up.calls[0].onProgress!(const UploadProgress(40, 100));
      final id = drafts.value.items[0].id;
      final p = drafts.value.uploads[id]! as FileUploading;
      expect(p.fraction, 0.4);
      expect(() => drafts.freeze(), throwsStateError);
      up.calls[0].succeed(receipt: 'r1');
      up.calls[1].succeed(receipt: 'r2');
      await pumpEvents();
      expect(drafts.value.uploadsPending, isFalse);
      final out = drafts.freeze();
      expect(out.map((a) => a.runtimeType.toString()), [
        'OutgoingFile',
        'OutgoingImage',
        'OutgoingFile',
      ]);
      expect((out[0] as OutgoingFile).receiptId, 'r1');
      expect((out[2] as OutgoingFile).receiptId, 'r2');
    });

    test('at most two uploads run; the queue is FIFO', () async {
      await drafts.add([
        file('1', 1),
        file('2', 1),
        file('3', 1),
        file('4', 1),
      ]);
      expect(up.calls.map((c) => c.name), ['1', '2']);
      up.calls[0].succeed();
      await pumpEvents();
      expect(up.calls.map((c) => c.name), ['1', '2', '3']);
      up.calls[1].succeed();
      await pumpEvents();
      expect(up.calls.map((c) => c.name), ['1', '2', '3', '4']);
    });

    test(
      'removing an active upload cancels it, a queued one is skipped',
      () async {
        await drafts.add([file('1', 1), file('2', 1), file('3', 1)]);
        final active = drafts.value.items[0].id;
        final queued = drafts.value.items[2].id;
        drafts.remove(queued);
        drafts.remove(active);
        await pumpEvents();
        expect(up.calls[0].cancel!.isCancelled, isTrue);
        up.calls[1].succeed();
        await pumpEvents();
        // The removed queued file never started.
        expect(up.calls.map((c) => c.name), ['1', '2']);
        expect(drafts.value.items.map((a) => a.name), ['2']);
        expect(drafts.value.uploads.keys, [drafts.value.items.single.id]);
      },
    );

    test('a failed upload holds Send and retry uploads again', () async {
      await drafts.add([file('a.txt', 5)]);
      final id = drafts.value.items.single.id;
      up.calls[0].fail(RemoteException('session/not-found', 'gone'));
      await pumpEvents();
      expect(drafts.value.uploads[id], isA<FileFailed>());
      expect(drafts.value.hasFailedUpload, isTrue);
      expect(drafts.value.uploadsPending, isTrue);
      drafts.retry(id);
      expect(drafts.value.uploads[id], isA<FileUploading>());
      expect(up.calls, hasLength(2));
      up.calls[1].succeed(receipt: 'again');
      await pumpEvents();
      expect((drafts.freeze().single as OutgoingFile).receiptId, 'again');
    });

    test('retry does nothing unless the upload failed', () async {
      await drafts.add([file('a.txt', 5)]);
      drafts.retry(drafts.value.items.single.id);
      expect(up.calls, hasLength(1));
    });

    test('a stale completion after removal writes nothing', () async {
      await drafts.add([file('a.txt', 5)]);
      final id = drafts.value.items.single.id;
      drafts.remove(id);
      up.calls[0].succeed();
      await pumpEvents();
      expect(drafts.value.items, isEmpty);
      expect(drafts.value.uploads, isEmpty);
    });

    test('image count limit refuses the whole batch', () async {
      await drafts.add([file('1.png', 1), file('2.png', 1)]);
      final r = await drafts.add([file('3.png', 1), file('4.png', 1)]);
      expect(r.refusal, IntakeRefusal.tooManyImages);
      expect(r.limit, 3);
      expect(r.added, isEmpty);
      expect(drafts.value.items, hasLength(2));
    });

    test(
      'a single image over the byte limit refuses the batch, files unaffected',
      () async {
        final r = await drafts.add([
          file('big.jpg', 1001),
          file('x.txt', 5000),
        ]);
        expect(r.refusal, IntakeRefusal.imageTooLarge);
        expect(r.limit, 1000);
        expect(drafts.value.items, isEmpty);
        expect(up.calls, isEmpty);
      },
    );

    test('the aggregate image size counts existing drafts', () async {
      await drafts.add([file('1.png', 900), file('2.png', 900)]);
      final r = await drafts.add([file('3.png', 300)]);
      expect(r.refusal, IntakeRefusal.imagesTooLarge);
      expect(r.limit, 2000);
    });

    test('generic files carry no client-side limit', () async {
      final r = await drafts.add([
        for (var i = 0; i < 30; i++) file('f$i', 10 << 20),
      ]);
      expect(r.refusal, isNull);
      expect(drafts.value.items, hasLength(30));
    });

    test('without projected limits nothing is pre-checked (the host decides at send)', () async {
      current = null;
      final r = await drafts.add([
        for (var i = 0; i < 25; i++) file('$i.png', 5 << 20),
      ]);
      expect(r.refusal, isNull);
      expect(drafts.value.items, hasLength(25));
    });

    test('clear drops the drafts and cancels what is left', () async {
      await drafts.add([file('a', 1), file('b', 1), file('c', 1)]);
      drafts.clear();
      await pumpEvents();
      expect(drafts.value.isEmpty, isTrue);
      expect(up.calls[0].cancel!.isCancelled, isTrue);
    });
  });

  group('prompt content', () {
    late FakeTransport t;
    late Session session;
    setUp(() {
      t = FakeTransport();
      session = Session('sess', t);
    });
    tearDown(() => session.dispose());

    test('attachments come first in pick order, then the text', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 250]);
      await session.prompt(
        'look',
        attachments: [
          OutgoingImage(name: 'p.png', bytes: bytes, mediaType: 'image/png'),
          const OutgoingFile(name: 'n.txt', size: 3, receiptId: 'rcpt-9'),
          OutgoingImage(name: '', bytes: bytes, mediaType: 'image/jpeg'),
        ],
      );
      final content = (t.prompts.single['content']! as List)
          .cast<Map<String, Object?>>();
      expect(content[0], {
        'type': 'image',
        'mediaType': 'image/png',
        'data': base64Encode(bytes),
        'name': 'p.png',
      });
      expect(content[1], {'type': 'file', 'receiptId': 'rcpt-9'});
      expect(content[2].containsKey('name'), isFalse);
      expect(content[3], {'type': 'text', 'text': 'look'});
      final echo = session.snapshot.value.pendingSubmissions.single;
      expect(echo.attachments, hasLength(3));
    });

    test('an attachment-only prompt has no text part', () async {
      await session.prompt(
        '',
        attachments: [const OutgoingFile(name: 'n', size: 1, receiptId: 'r')],
      );
      expect(t.prompts.single['content'], [
        {'type': 'file', 'receiptId': 'r'},
      ]);
    });

    test('a refused prompt removes its echo', () async {
      t.onPrompt = (_) => throw RemoteException(
        'session/attachment-invalid',
        'no',
        {'reason': 'TOO_MANY_IMAGES'},
      );
      await expectLater(
        session.prompt(
          'x',
          attachments: [
            OutgoingImage(
              name: 'a',
              bytes: Uint8List(1),
              mediaType: 'image/png',
            ),
          ],
        ),
        throwsA(isA<RemoteException>()),
      );
      expect(session.snapshot.value.pendingSubmissions, isEmpty);
      expect(
        attachmentRefusalReason(session.snapshot.value.promptError!),
        'TOO_MANY_IMAGES',
      );
    });
  });

  group('SessionImages', () {
    late FakeTransport t;
    late Session session;
    setUp(() {
      t = FakeTransport();
      session = Session('sess', t);
    });
    tearDown(() => session.dispose());

    ImageRef ref(String id) => ImageRef(
      attachmentId: id,
      mediaType: 'image/png',
      bytes: 10,
      width: 1,
      height: 1,
    );

    test('decodes base64, reads once and caches', () async {
      t.onAttachment = (s, id) async => {
        'attachment': {},
        'data': base64Encode([9, 8, 7]),
      };
      final a = await session.images.load(ref('sha256:x'));
      final b = await session.images.load(ref('sha256:x'));
      expect(a, [9, 8, 7]);
      expect(identical(a, b), isTrue);
      expect(t.attachmentReads, ['sess/sha256:x']);
      expect(session.images.peek('sha256:x'), [9, 8, 7]);
    });

    test('concurrent loads share one read', () async {
      final c = Completer<Map<String, Object?>>();
      t.onAttachment = (s, id) => c.future;
      final f1 = session.images.load(ref('a'));
      final f2 = session.images.load(ref('a'));
      c.complete({
        'data': base64Encode([1]),
      });
      expect(await f1, [1]);
      expect(await f2, [1]);
      expect(t.attachmentReads, hasLength(1));
    });

    test('a failed read is not cached, so retry reads again', () async {
      var n = 0;
      t.onAttachment = (s, id) async {
        n++;
        if (n == 1) throw RemoteException('transport/http-500', 'boom');
        return {
          'data': base64Encode([5]),
        };
      };
      await expectLater(
        session.images.load(ref('a')),
        throwsA(isA<RemoteException>()),
      );
      await pumpEvents();
      expect(await session.images.load(ref('a')), [5]);
      expect(t.attachmentReads, hasLength(2));
    });

    test('the cache is bounded by bytes, least recently used first', () async {
      final small = SessionImages(
        's',
        (s, id) async => {'data': base64Encode(Uint8List(100))},
        maxCachedBytes: 250,
      );
      await small.load(ref('1'));
      await small.load(ref('2'));
      await small.load(ref('1')); // touch
      await small.load(ref('3'));
      await pumpEvents();
      expect(small.peek('2'), isNull);
      expect(small.peek('1'), isNotNull);
      expect(small.peek('3'), isNotNull);
    });
  });
}

Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 10));
