import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

class _Fake implements DeliverablesClient {
  @override
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  }) {
    appCalls++;
    return appRead?.call(cancel) ?? Future.value(const []);
  }

  int summaryCalls = 0,
      diffCalls = 0,
      hostCalls = 0,
      openCalls = 0,
      appCalls = 0;
  Future<List<NativeFileApplication>> Function(DeliverablesCancel?)? appRead;
  Future<ChangesSummary> Function(DeliverablesCancel?)? summaryRead;
  Future<ChangesDiff> Function(DeliverablesCancel?)? diffRead;
  Future<PresentedHost> Function(DeliverablesCancel?)? hostRead;
  Future<void> Function(DeliverablesCancel?)? openRead;
  @override
  Future<ChangesSummary> summary(
    String id,
    num seq, {
    DeliverablesCancel? cancel,
  }) {
    summaryCalls++;
    return summaryRead?.call(cancel) ??
        Future.value(
          const ChangesSummary(
            turn: 1,
            files: [],
            total: 0,
            added: 0,
            deleted: 0,
          ),
        );
  }

  @override
  Future<ChangesDiff> diff(
    String id,
    num seq,
    int index, {
    DeliverablesCancel? cancel,
  }) {
    diffCalls++;
    return diffRead?.call(cancel) ??
        Future.value(
          const ChangesDiff(kind: 'binary', path: 'a', display: 'a'),
        );
  }

  @override
  Future<PresentedHost> host({DeliverablesCancel? cancel}) {
    hostCalls++;
    return hostRead?.call(cancel) ??
        Future.value(
          const PresentedHost(
            name: 'Synthetic remote',
            available: true,
            fileManager: 'finder',
          ),
        );
  }

  @override
  Future<void> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
    DeliverablesCancel? cancel,
  }) {
    openCalls++;
    return openRead?.call(cancel) ?? Future.value();
  }
}

Future<T> cancelled<T>(DeliverablesCancel? cancel) =>
    cancel!.whenCancelled.then((_) => throw const DeliverablesCancelled());
void main() {
  test(
    'mounted association controls share reads, refresh and final cancellation',
    () async {
      final client = _Fake();
      final active = DeliverablesModel(client);
      const file = DeliveryFile('s', 8, 0);
      final a = active.acquireApplications(file),
          b = active.acquireApplications(file);
      expect(identical(a, b), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(client.appCalls, 1);
      expect(a.state.value.phase, HostReadPhase.ready);
      active.releaseApplications(a);
      client.appRead = cancelled;
      b.refresh();
      active.releaseApplications(b);
      final next = active.acquireApplications(file);
      expect(identical(b, next), isFalse);
      active.releaseApplications(next);
      await active.dispose();
    },
  );

  test(
    'shared reads coalesce and summary failure stays missing until reset',
    () async {
      final client = _Fake(), gate = Completer<ChangesSummary>();
      client.summaryRead = (_) => gate.future;
      final model = DeliverablesModel(client);
      final first = model.summaries.load('s', 7),
          second = model.summaries.load('s', 7);
      expect(identical(first, second), isTrue);
      expect(client.summaryCalls, 1);
      gate.completeError(StateError('synthetic outage'));
      await first;
      expect(model.summaries.get('s', 7)!.phase, HostReadPhase.missing);
      await model.summaries.load('s', 7);
      expect(client.summaryCalls, 1);
      model.reset();
      client.summaryRead = null;
      await model.summaries.load('s', 7);
      expect(client.summaryCalls, 2);
      expect(model.summaries.get('s', 7)!.phase, HostReadPhase.ready);
      await model.dispose();
    },
  );
  test('diff errors retry but missing comparisons do not', () async {
    final client = _Fake();
    final active = DeliverablesModel(client);
    client.diffRead = (_) =>
        Future.error(const FormatException('synthetic invalid record'));
    await active.diffs.load('s', 7, 0);
    expect(active.diffs.get('s', 7, 0)!.phase, HostReadPhase.error);
    client.diffRead = (_) => Future.error(const DeliverablesHttpFailure(404));
    await active.diffs.load('s', 7, 0);
    expect(active.diffs.get('s', 7, 0)!.phase, HostReadPhase.missing);
    await active.diffs.load('s', 7, 0);
    expect(client.diffCalls, 2);
    await active.dispose();
  });
  test('generation replacement suppresses late old reads and disposal cancels outstanding requests', () async {
    final client = _Fake(),
        gate = Completer<ChangesSummary>(),
        model = DeliverablesModel(_Fake());
    await model.dispose();
    final active = DeliverablesModel(client);
    client.summaryRead = (_) => gate.future;
    final old = active.summaries.load('s', 7);
    active.reset();
    client.summaryRead = null;
    await active.summaries.load('s', 7);
    final current = active.summaries.get('s', 7);
    gate.complete(
      const ChangesSummary(turn: 99, files: [], total: 0, added: 0, deleted: 0),
    );
    await old;
    expect(identical(active.summaries.get('s', 7), current), isTrue);
    client.diffRead = cancelled;
    client.hostRead = cancelled;
    client.openRead = cancelled;
    final requests = [
      active.diffs.load('s', 7, 0),
      active.loadHost(),
      active.open(const DeliveryFile('s', 8, 0)),
    ];
    await active.dispose().timeout(const Duration(seconds: 2));
    await Future.wait<Object?>(requests);
    expect(active.diffs.get('s', 7, 0)!.phase, HostReadPhase.loading);
    expect(active.phases.value.values.single, NativeOpenPhase.opening);
  });
  test('native gestures coalesce, failures retry, metadata uses remote identity and success expires', () async {
    final client = _Fake(), gate = Completer<void>();
    final model = DeliverablesModel(
      client,
      successDuration: const Duration(milliseconds: 10),
    );
    client.openRead = (_) => gate.future;
    const file = DeliveryFile('s', 8, 2);
    final first = model.open(file);
    await model.open(file, action: NativeFileAction.reveal);
    expect(client.openCalls, 1);
    gate.completeError(const DeliverablesHttpFailure(422));
    expect(await first, NativeOpenFailure.openError);
    expect(
      model.phases.value[file.actionKey],
      NativeOpenPhase.nativeUnavailable,
    );
    client.openRead = null;
    expect(await model.open(file, action: NativeFileAction.reveal), isNull);
    expect(model.phases.value[file.actionKey], NativeOpenPhase.revealed);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(model.phases.value, isEmpty);
    client.hostRead = (_) => Future.error(StateError('synthetic outage'));
    await model.loadHost();
    expect(model.host.value!.phase, HostReadPhase.error);
    client.hostRead = null;
    await model.loadHost();
    expect(model.host.value!.value!.fileManager, 'finder');
    expect(client.hostCalls, 2);
    await model.dispose();
  });
}
