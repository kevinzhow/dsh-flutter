import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:test/test.dart';

void main() {
  const png = {
    'attachmentId': 'sha256:a',
    'mediaType': 'image/png',
    'bytes': 10,
    'width': 2,
    'height': 3,
    'name': 'p.png',
  };
  const file = {'attachmentId': 'sha256:b', 'name': 'n.txt', 'bytes': 7};

  test('text joins, attachments keep their order, the rest stays', () {
    final parts = userContentParts([
      {'type': 'image', 'attachment': png},
      {'type': 'file', 'attachment': file},
      {'type': 'text', 'text': 'hello '},
      {'type': 'text', 'text': 'world'},
      {'type': 'mystery', 'x': 1},
    ]);
    expect(parts.text, 'hello world');
    expect(parts.attachments, hasLength(2));
    expect((parts.attachments[0] as MessageImage).image.name, 'p.png');
    expect((parts.attachments[1] as MessageFile).file.bytes, 7);
    expect(parts.rest, [
      {'type': 'mystery', 'x': 1},
    ]);
  });

  test('a malformed attachment is not dropped silently', () {
    final parts = userContentParts([
      {
        'type': 'image',
        'attachment': {'attachmentId': 'a', 'mediaType': 'image/png'},
      },
      {'type': 'file'},
      'not a block',
    ]);
    expect(parts.attachments, isEmpty);
    expect(parts.rest, hasLength(3));
  });

  test('MessageData exposes the same split', () {
    const data = MessageData(
      kind: 'user',
      seq: 1,
      time: 1,
      content: [
        {'type': 'text', 'text': 'x'},
        {'type': 'file', 'attachment': file},
      ],
      source: null,
    );
    expect(data.parts.attachments.single, isA<MessageFile>());
    expect(data.text, 'x');
  });
}
