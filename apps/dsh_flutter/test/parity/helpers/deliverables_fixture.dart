import 'package:dsh_client/dsh_client.dart';

const syntheticDeliveryHunks = [
  ChangesHunk(
    oldStart: 1,
    oldLines: 2,
    newStart: 1,
    newLines: 2,
    lines: [
      ' const name = "Synthetic";',
      '-const old = true;',
      '+const report = "Synthetic report";',
    ],
  ),
];

class SyntheticDeliverables implements DeliverablesClient {
  bool refuse = false;
  int opens = 0;
  @override
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  }) async => const [
    NativeFileApplication(
      id: 'synthetic.editor',
      name: 'Synthetic editor',
      isDefault: true,
    ),
  ];
  @override
  Future<ChangesSummary> summary(
    String sessionId,
    num seq, {
    DeliverablesCancel? cancel,
  }) async => ChangesSummary(
    turn: 1,
    total: 5,
    added: 5,
    deleted: 1,
    files: [
      for (var i = 0; i < 5; i++)
        ChangedFile(
          path: '/synthetic/file$i.dart',
          display: 'file$i.dart',
          added: 1,
          deleted: i == 0 ? 1 : 0,
        ),
    ],
  );
  @override
  Future<ChangesDiff> diff(
    String sessionId,
    num seq,
    int index, {
    DeliverablesCancel? cancel,
  }) async => ChangesDiff(
    kind: 'text',
    path: '/synthetic/file$index.dart',
    display: 'file$index.dart',
    before: true,
    after: true,
    hunks: syntheticDeliveryHunks,
  );
  @override
  Future<PresentedHost> host({DeliverablesCancel? cancel}) async =>
      const PresentedHost(
        name: 'Synthetic remote',
        available: true,
        fileManager: 'directory',
      );
  @override
  Future<void> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
    DeliverablesCancel? cancel,
  }) async {
    opens++;
    if (refuse) {
      refuse = false;
      throw const DeliverablesHttpFailure(500);
    }
  }
}
