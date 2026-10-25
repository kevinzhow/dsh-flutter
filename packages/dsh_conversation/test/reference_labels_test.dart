import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:test/test.dart';

ViewNode message(int seq, {String kind = 'user'}) => ViewNode(
  key: '$kind-$seq',
  kind: kind,
  id: '$seq',
  target: chatTarget,
  anchorSeq: seq,
  location: const SessionLocation(),
  visible: true,
  data: MessageData(
    kind: kind,
    seq: seq,
    time: 1000,
    content: const [],
    source: const {'kind': 'user'},
  ),
);
ViewNode recall(int seq, Object? refs, {String source = 'session-reference'}) =>
    ViewNode(
      key: 'context-$seq',
      kind: 'context',
      id: '$seq',
      target: chatTarget,
      anchorSeq: seq,
      location: const SessionLocation(),
      visible: true,
      data: MessageData(
        kind: 'context',
        seq: seq,
        time: 1000,
        content: const [],
        source: {'kind': source, 'references': refs},
      ),
    );
List<String> labels(ChatSnapshotBuilder b, String key) =>
    (b.current.nodes[key]!.data as MessageData).referenceLabels;
void main() {
  test(
    'only exactly adjacent sourced recall supplies unique nonempty labels',
    () {
      final b = ChatSnapshotBuilder();
      b.replace([
        message(1),
        message(3, kind: 'steering'),
        recall(2, [
          {'label': 'Synthetic'},
          {'label': ''},
          {'label': 'Synthetic'},
          null,
          {'label': 7},
          {'label': 'Long label'},
        ]),
        recall(5, [
          {'label': 'Not adjacent'},
        ]),
      ], ConversationTimeline.empty);
      expect(labels(b, 'user-1'), ['Synthetic', 'Long label']);
      expect(labels(b, 'steering-3'), isEmpty);
    },
  );
  test('recall arriving later patches its message, then a changed source clears it', () {
    final b = ChatSnapshotBuilder();
    b.replace([message(1), message(10)], ConversationTimeline.empty);
    final untouched = b.current.nodes['user-10'];
    b.apply([
      recall(2, [
        {'label': 'One'},
      ]),
    ], ConversationTimeline.empty);
    expect(labels(b, 'user-1'), ['One']);
    expect(identical(untouched, b.current.nodes['user-10']), isTrue);
    final first = b.current.nodes['user-1'];
    b.apply([
      recall(2, [
        {'label': 'One'},
      ]),
    ], ConversationTimeline.empty);
    expect(identical(first, b.current.nodes['user-1']), isTrue);
    b.apply([
      recall(2, [
        {'label': 'Two'},
      ]),
    ], ConversationTimeline.empty);
    expect(labels(b, 'user-1'), ['Two']);
    b.apply([
      recall(2, [
        {'label': 'Ignored'},
      ], source: 'other'),
    ], ConversationTimeline.empty);
    expect(labels(b, 'user-1'), isEmpty);
  });
  test(
    'recall can precede its message; replacement clears old associations',
    () {
      final b = ChatSnapshotBuilder();
      b.replace([
        recall(2, [
          {'label': 'One'},
        ]),
      ], ConversationTimeline.empty);
      b.apply([message(1)], ConversationTimeline.empty);
      expect(labels(b, 'user-1'), ['One']);
      b.replace([message(1)], ConversationTimeline.empty);
      expect(labels(b, 'user-1'), isEmpty);
    },
  );
}
