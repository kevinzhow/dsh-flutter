@Tags(['live'])
library;

// Live check of the attachment surfaces against a real `dsh web` host, started
// by `tool/live_spike/bin/live_app.dart --test test/live/live_attachments_test.dart`
// (a separate instance on 127.0.0.1 sharing ~/.dsh; the launch URL is read from a
// mode-600 file and never printed). It drives the real AppController + LiveBackend:
// upload an image and a text file through the host's raw upload route with progress,
// send them, read them back (durable images, workspace files, binary reads, watches,
// downloads), and asks the agent to read files. At most five short prompts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_feature_files/dsh_feature_files.dart';
import 'package:dsh_feature_tool/dsh_feature_tool.dart'
    show imageCardModel, readCardModel;
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_flutter/src/platform/file_actions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter_test/flutter_test.dart';

final launchFile = Platform.environment['DSH_LIVE_LAUNCH_FILE'];
final resultFile = Platform.environment['DSH_LIVE_RESULT'];
final workspace = Platform.environment['DSH_LIVE_WORKSPACE'];

final results = <Map<String, Object?>>[];

Future<T> step<T>(
  String name,
  Future<T> Function() body, {
  String Function(T)? detail,
}) async {
  final sw = Stopwatch()..start();
  try {
    final value = await body();
    results.add({
      'check': name,
      'state': 'pass',
      'ms': sw.elapsedMilliseconds,
      'detail': detail?.call(value) ?? '',
    });
    return value;
  } on Object catch (e) {
    results.add({
      'check': name,
      'state': 'FAIL',
      'ms': sw.elapsedMilliseconds,
      'detail': '$e',
    });
    rethrow;
  }
}

/// Like [step] but a failure is recorded and the run goes on (model-dependent
/// checks: the agent has to choose to call the tool).
Future<void> bestEffort(String name, Future<String> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    results.add({
      'check': name,
      'state': 'pass',
      'ms': sw.elapsedMilliseconds,
      'detail': await body(),
    });
  } on Object catch (e) {
    results.add({
      'check': name,
      'state': 'not reached',
      'ms': sw.elapsedMilliseconds,
      'detail': '$e',
    });
  }
}

Future<void> until(
  String what,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// A small RGB PNG (a diagonal gradient), encoded here so no image package is needed.
Uint8List png(int width, int height) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      raw
        ..addByte((x * 255) ~/ width)
        ..addByte((y * 255) ~/ height)
        ..addByte(160);
    }
  }
  final crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  int crc(List<int> bytes) {
    var c = 0xffffffff;
    for (final b in bytes) {
      c = crcTable[(c ^ b) & 0xff] ^ (c >> 8);
    }
    return c ^ 0xffffffff;
  }

  List<int> chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    final len = ByteData(4)..setUint32(0, data.length);
    final sum = ByteData(4)..setUint32(0, crc(body));
    return [...len.buffer.asUint8List(), ...body, ...sum.buffer.asUint8List()];
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  return Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    ...chunk('IHDR', header.buffer.asUint8List()),
    ...chunk('IDAT', ZLibCodec().encode(raw.toBytes())),
    ...chunk('IEND', const []),
  ]);
}

LocalFile local(String name, Uint8List bytes, {String? type}) => LocalFile(
  name: name,
  size: bytes.length,
  mediaType: type,
  open: () => Stream.fromIterable([
    for (var i = 0; i < bytes.length; i += 4096)
      bytes.sublist(i, i + 4096 > bytes.length ? bytes.length : i + 4096),
  ]),
  read: () async => bytes,
);

void main() {
  test(
    'the attachment surfaces against a live dsh host',
    () async {
      final launch = File(launchFile!).readAsStringSync().trim();
      final controller = AppController(
        backend: LiveBackend(),
        locale: DshLocale.en,
      );
      final ws = workspace!;
      try {
        await step('pair from the launch link', () async {
          expect(await controller.pair(launch), isTrue);
          return controller.hostOrigin;
        }, detail: (o) => 'connected to $o');
        await step(
          'create a session in the scratch workspace and open it',
          () async {
            await controller.createSession();
            final sc = controller.openSession!;
            await sc.open();
            await until('cwd', () => sc.owner.cwd != null);
            expect(sc.owner.cwd, ws);
            return sc.sessionId;
          },
          detail: (_) => 'session opened in the scratch directory',
        );
        final sc = controller.openSession!;
        final session = sc.session;
        final drafts = sc.owner.attachments!.drafts;
        final backend = controller.backend as LiveBackend;
        final chat = sc.conversation.chat;
        bool turnClosedAfter(num seq) => session.eventSource.window.entries.any(
          (e) => !e.transient && e.type == 'turn/end' && e.seq > seq,
        );
        num lastSeq() => session.eventSource.window.entries
            .where((e) => !e.transient)
            .fold<num>(-1, (a, e) => e.seq > a ? e.seq : a);
        List<ViewNode> nodes(String kind) =>
            chat.value.visibleNodes.where((n) => n.kind == kind).toList();

        // ---- limits as the host projects them ----------------------------
        final limits = await step(
          'the host projects its image limits',
          () async {
            await until(
              'imageLimits',
              () => session.projections.get('imageLimits') != null,
            );
            final l = ImageLimits.tryParse(
              session.projections.get('imageLimits'),
            )!;
            expect(l.maxImagesPerMessage, 20);
            expect(l.mediaTypes, imageMediaTypes);
            return l;
          },
          detail: (l) =>
              '${l.maxImagesPerMessage} images, ${l.maxImageBytes ~/ (1024 * 1024)} MiB each, ${l.maxMessageImageBytes ~/ (1024 * 1024)} MiB total',
        );
        await step(
          'intake refuses the 21st image before anything is staged',
          () async {
            final many = [
              for (var i = 0; i <= limits.maxImagesPerMessage; i++)
                local('i$i.png', png(2, 2), type: 'image/png'),
            ];
            final r = await drafts.add(many);
            expect(r.refusal, IntakeRefusal.tooManyImages);
            expect(drafts.value.isEmpty, isTrue);
            return r.limit;
          },
          detail: (n) => 'refused with the limit $n',
        );

        // ---- upload: errors first, then the real thing ---------------------
        await step(
          'an upload for an unknown session is refused with its code',
          () async {
            try {
              await backend.uploader.upload(
                sessionId: 'session-does-not-exist',
                data: Stream.value([1, 2, 3]),
                name: 'x.txt',
              );
              fail('the host accepted an upload for an unknown session');
            } on RemoteException catch (e) {
              expect(e.code, 'session/not-found');
              return e.code;
            }
          },
          detail: (c) => c,
        );
        await step('cancelling a large upload aborts it', () async {
          final token = UploadCancelToken();
          final chunks = StreamController<List<int>>();
          final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
            chunks.add(Uint8List(65536));
          });
          final progress = <int>[];
          final result = backend.uploader.upload(
            sessionId: sc.sessionId,
            data: chunks.stream,
            name: 'big.bin',
            cancel: token,
            onProgress: (p) => progress.add(p.loaded),
          );
          await until(
            'some bytes sent',
            () => progress.isNotEmpty && progress.last > 200000,
          );
          token.cancel();
          timer.cancel();
          await expectLater(result, throwsA(isA<UploadCancelled>()));
          await chunks.close();
          return progress.last;
        }, detail: (n) => 'aborted after ${n ~/ 1024} KiB');

        final picture = png(96, 64);
        final secret = 'The secret word is TANGERINE.\nSecond line.\n';
        final note = Uint8List.fromList(utf8.encode(secret));
        await step(
          'picked image and file become drafts; the file uploads with progress',
          () async {
            final r = await drafts.add([
              local('shot.png', picture, type: 'image/png'),
              local('notes (1).txt', note, type: 'text/plain'),
            ]);
            expect(r.refusal, isNull);
            expect(drafts.value.items, hasLength(2));
            final image = drafts.value.items[0] as DraftImage;
            expect(image.mediaType, 'image/png');
            final file = drafts.value.items[1] as DraftFile;
            await until(
              'upload settles',
              () => drafts.value.uploads[file.id] is! FileUploading,
            );
            final state = drafts.value.uploads[file.id];
            expect(state, isA<FileReady>(), reason: '$state');
            final receipt = (state! as FileReady).receipt;
            expect(receipt.bytes, note.length);
            expect(receipt.name, 'notes (1).txt');
            return receipt.receiptId;
          },
          detail: (_) => 'file staged, receipt held',
        );

        await step(
          'the host refuses a prompt citing an unknown receipt',
          () async {
            try {
              await session.prompt(
                'x',
                attachments: const [
                  OutgoingFile(
                    name: 'x.txt',
                    size: 1,
                    receiptId: 'not-a-receipt',
                  ),
                ],
              );
              fail('accepted');
            } on RemoteException catch (e) {
              expect(e.code, 'session/attachment-invalid');
              expect(attachmentRefusalReason(e), 'FILE_NOT_STAGED');
              return attachmentRefusalReason(e);
            }
          },
          detail: (r) => 'refused: $r',
        );
        await step(
          'the host refuses bytes that are not the image they claim',
          () async {
            try {
              await session.prompt(
                'x',
                attachments: [
                  OutgoingImage(
                    name: 'fake.png',
                    bytes: Uint8List.fromList([1, 2, 3, 4]),
                    mediaType: 'image/png',
                  ),
                ],
              );
              fail('accepted');
            } on RemoteException catch (e) {
              return '${e.code} ${attachmentRefusalReason(e)}';
            }
          },
          detail: (r) => r,
        );
        expect(session.snapshot.value.pendingSubmissions, isEmpty);

        // ---- prompt 1: send the drafts, ask the agent to read them ---------
        await step('send: the user message carries the image and the file', () async {
          final base = lastSeq();
          final attachments = drafts.freeze();
          await sc.send(
            'Read the attached text file with your tools and tell me the secret word it contains, '
            'in one short sentence.',
            attachments: attachments,
          );
          drafts.clear();
          await until(
            'user message with attachments',
            () => nodes('user').any(
              (n) => (n.data! as MessageData).parts.attachments.length == 2,
            ),
          );
          await until('turn end', () => turnClosedAfter(base));
          final parts = (nodes('user').last.data! as MessageData).parts;
          expect(parts.attachments[0], isA<MessageImage>());
          expect(parts.attachments[1], isA<MessageFile>());
          expect(
            (parts.attachments[1] as MessageFile).file.name,
            'notes (1).txt',
          );
          expect(session.snapshot.value.pendingSubmissions, isEmpty);
          return '${parts.attachments.length} attachments in the durable message';
        }, detail: (s) => s);

        ImageRef? sentImage;
        await step('the durable image reads back byte for byte (gallery source)', () async {
          final parts = (nodes('user').last.data! as MessageData).parts;
          sentImage = (parts.attachments[0] as MessageImage).image;
          final bytes = await session.images.load(sentImage!);
          expect(bytes.take(8), [
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]);
          expect(sentImage!.width, 96);
          expect(sentImage!.height, 64);
          expect(
            identical(await session.images.load(sentImage!), bytes),
            isTrue,
          );
          return '${bytes.length} bytes, ${sentImage!.width}x${sentImage!.height}';
        }, detail: (s) => s);

        await bestEffort('the agent read the file and answered with its content', () async {
          final answers = nodes('assistant-step')
              .map(
                (n) => [
                  for (final b in (n.data! as AssistantData).blocks)
                    if (b is TextBlock) b.text,
                ].join(),
              )
              .join('\n');
          expect(answers.toLowerCase(), contains('tangerine'));
          final tools = nodes('tool-call')
              .map((n) => (n.data! as ToolData).root.name)
              .toList();
          return 'answered; tools used: ${tools.isEmpty ? 'none' : tools.join(', ')}';
        });

        // ---- workspace files ------------------------------------------------
        File('$ws/shot.png').writeAsBytesSync(picture);
        File('$ws/hello.dart').writeAsStringSync(
          '// a comment\nconst answer = 42;\nString greet(String name) => "hi \$name";\n',
        );
        File('$ws/README.md').writeAsStringSync(
          '# Title\n\nSome **bold** text\n\n```ts\nconst x = 1\n```\n',
        );
        File('$ws/doc.pdf').writeAsBytesSync(
          Uint8List.fromList(List.generate(300000, (i) => i % 251)),
        );
        Directory('$ws/sub').createSync();
        File('$ws/sub/deep.txt').writeAsStringSync('deep');
        final files = backend.files;
        await step('list: the workspace root, directories and sizes', () async {
          final l = await files.list(sc.sessionId, ws);
          final names = {for (final e in l.entries) e.name: e.type};
          expect(names['sub'], WorkspaceEntryType.directory);
          expect(names['shot.png'], WorkspaceEntryType.file);
          return '${l.entries.length} entries';
        }, detail: (s) => s);
        await step(
          'read: a text page, and a binary file is refused as text',
          () async {
            final page = await files.read(sc.sessionId, 'hello.dart');
            expect(page.lines, 3);
            expect(page.eof, isTrue);
            try {
              await files.read(sc.sessionId, 'shot.png');
              fail('read a png as text');
            } on RemoteException catch (e) {
              expect(e.code, 'workspace-file/not-text');
            }
            return 'page of ${page.lines} lines, png refused as not-text';
          },
          detail: (s) => s,
        );
        await step(
          'readBytes: a multipart answer decodes to the exact bytes',
          () async {
            final whole = await files.readBytes(sc.sessionId, 'shot.png');
            expect(whole.data, picture);
            final window = await files.readBytes(
              sc.sessionId,
              'doc.pdf',
              range: const ByteRange(offset: 1000, length: 5000),
            );
            expect(window.data.length, 5000);
            expect(window.eof, isFalse);
            expect(window.bytes, 300000);
            return '${whole.data.length} bytes whole, 5000 byte window';
          },
          detail: (s) => s,
        );
        await step('the sidebar tabs open: image preview, source, markdown, binary download', () async {
          final owner = sc.owner;
          Future<DocumentController> doc(String path) async {
            final c = DocumentController(
              sessionId: sc.sessionId,
              path: path,
              files: files,
            );
            await until(
              '$path loaded',
              () => c.hasContent || c.failure != null || c.candidates.isEmpty,
            );
            addTearDown(c.dispose);
            return c;
          }

          final image = await doc('shot.png');
          expect(image.selected!.id, 'image');
          expect(image.bytes, picture);
          final code = await doc('hello.dart');
          expect(code.selected!.id, 'code');
          expect(code.lines.length, 3);
          final md = await doc('README.md');
          expect(md.candidates.map((r) => r.id), ['markdown', 'code', 'text']);
          final pdf = await doc('doc.pdf');
          expect(pdf.candidates, isEmpty);
          final dir = await Directory.systemTemp.createTemp('whalee-download-');
          addTearDown(() => dir.delete(recursive: true));
          final actions = PlatformFileActions(directory: dir);
          final download = FileDownload(
            sessionId: sc.sessionId,
            path: 'doc.pdf',
            name: 'doc.pdf',
            files: files,
            actions: _NoOpen(actions),
            windowBytes: 64 * 1024,
          );
          await download.open();
          expect(download.error, isNull);
          expect(download.done, isTrue);
          final saved = Directory(dir.path)
              .listSync(recursive: true)
              .whereType<File>()
              .single;
          expect(
            saved.readAsBytesSync(),
            File('$ws/doc.pdf').readAsBytesSync(),
          );
          expect(owner.files, isNotNull);
          return 'image/code/markdown/binary all resolved; 300000 byte file downloaded in windows';
        }, detail: (s) => s);
        await step('the file tree follows the directory watch', () async {
          final tree = FilesController(
            sessionId: sc.sessionId,
            root: ws,
            files: files,
            debounce: const Duration(milliseconds: 50),
          );
          addTearDown(tree.dispose);
          await until('root listed', () => tree.levels[ws] is FilesLevelLoaded);
          File('$ws/appeared.txt').writeAsStringSync('new');
          await until('the new entry shows', () {
            final l = tree.levels[ws];
            return l is FilesLevelLoaded &&
                l.entries.any((e) => e.name == 'appeared.txt');
          }, timeout: const Duration(seconds: 20));
          return 'appeared.txt listed after the watch fired';
        }, detail: (s) => s);
        await step('a preview follows a change to its file', () async {
          final c = DocumentController(
            sessionId: sc.sessionId,
            path: 'hello.dart',
            files: files,
          );
          addTearDown(c.dispose);
          await until('loaded', () => c.hasContent);
          await Future<void>.delayed(const Duration(milliseconds: 500));
          File('$ws/hello.dart').writeAsStringSync('changed\n');
          await until(
            'reloaded',
            () => c.lines.isNotEmpty && c.lines.first == 'changed',
            timeout: const Duration(seconds: 20),
          );
          return 'reloaded after the host observed the write';
        }, detail: (s) => s);

        // ---- prompts 2 and 3: the read_image and read cards -----------------
        await bestEffort('prompt: read_image returns an image the gallery can load', () async {
          final base = lastSeq();
          await sc.send(
            'Use the read_image tool on shot.png in the working directory, then reply "seen".',
          );
          await until(
            'turn end',
            () => turnClosedAfter(base),
            timeout: const Duration(seconds: 150),
          );
          final calls = nodes('tool-call')
              .map((n) => (n.data! as ToolData).root)
              .where((c) => c.name == 'read_image')
              .toList();
          if (calls.isEmpty) {
            throw StateError('the model did not call read_image');
          }
          final card = imageCardModel(calls.last);
          if (card == null) {
            final last = calls.last;
            throw StateError(
              'read_image settled without an image card: '
              '${last is ToolResult ? (last.isError ? 'error result' : 'no image block') : 'not settled'}',
            );
          }
          final bytes = await session.images.load(card.images.first);
          expect(bytes.take(4), [0x89, 0x50, 0x4e, 0x47]);
          return 'card for ${card.path}: ${card.images.length} image, ${bytes.length} bytes loaded';
        });
        await bestEffort('prompt: the read tool result becomes a highlighted read card', () async {
          final base = lastSeq();
          await sc.send(
            'Use the read tool on README.md in the working directory and reply with the first heading only.',
          );
          await until(
            'turn end',
            () => turnClosedAfter(base),
            timeout: const Duration(seconds: 150),
          );
          final calls = nodes('tool-call')
              .map((n) => (n.data! as ToolData).root)
              .where((c) => c.name == 'read')
              .toList();
          if (calls.isEmpty) throw StateError('the model did not call read');
          final card = readCardModel(calls.last, cwd: ws);
          if (card == null) throw StateError('read result has no card');
          return 'card ${card.label}: ${card.lines.length} lines, lang ${card.lang}';
        });
      } finally {
        await controller.backend.disconnect();
        File(resultFile!).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(results),
        );
      }
    },
    skip: launchFile == null
        ? 'needs tool/live_spike/bin/live_app.dart (a live host)'
        : null,
    timeout: const Timeout(Duration(minutes: 12)),
    tags: ['live'],
  );
}

/// Records opens without launching a viewer (there is none on the test host).
class _NoOpen implements HostFileActions {
  _NoOpen(this.inner);
  final HostFileActions inner;

  @override
  bool get canOpen => true;
  @override
  bool get canSave => false;
  @override
  Future<HostFileSink> begin(String name) async =>
      _Sink(await inner.begin(name));
}

class _Sink implements HostFileSink {
  _Sink(this.inner);
  final HostFileSink inner;
  @override
  Future<void> add(Uint8List bytes) => inner.add(bytes);
  @override
  Future<void> finish() => inner.finish();
  @override
  Future<bool> open() async => true;
  @override
  Future<bool> save() async => true;
  @override
  Future<void> discard() async {}
}
