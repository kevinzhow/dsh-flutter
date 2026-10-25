import 'dart:convert';

import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> call(int seq, String id) => rec(
  seq,
  'tool/call',
  data: {
    'name': 'exit_plan_mode',
    'callId': id,
    'arguments': jsonEncode({'plan': '# Synthetic plan\n\nDetails'}),
  },
);

class _Services implements PlanServices {
  final transport = FakeTransport();
  int reads = 0;
  @override
  Future<String?> exitPlanMode(String sessionId) async => null;
  @override
  void openResource(
    SessionOwner owner,
    String address, {
    Map<String, Object?> params = const {},
  }) {}
  @override
  SessionHistoryRead historyRead(Map<String, Object?> address) {
    reads++;
    return SessionHistoryRead(transport, address);
  }
}

void main() {
  test('title and document share one read; only last release cancels and reopen retries', () async {
    final service = _Services();
    final feature = PlanFeature(service);
    addTearDown(feature.reset);
    final address = PlanAddress({
      'kind': 'session',
      'sessionId': 's',
    }, 'call').encoded;
    final body = feature.acquire(address)!;
    final title = feature.acquire(address)!;
    expect(identical(body, title), true);
    await pump();
    expect(service.reads, 1);
    feature.release(address, body);
    expect(service.transport.currentFollow.hasListener, true);
    feature.release(address, title);
    await pump();
    expect(service.transport.currentFollow.hasListener, false);
    expect(body.closed, true);
    final reopened = feature.acquire(address)!;
    await pump();
    expect(identical(reopened, body), false);
    expect(service.reads, 2);
    feature.release(address, reopened);
    await pump();
  });
  test(
    'settled resource survives closure and reset clears cached host data',
    () async {
      final service = _Services();
      final feature = PlanFeature(service);
      addTearDown(feature.reset);
      final address = PlanAddress({
        'kind': 'session',
        'sessionId': 's',
      }, 'wanted').encoded;
      final body = feature.acquire(address)!;
      await pump();
      service.transport.open(1, snapshot([call(2, 'wanted')]));
      await pump();
      expect(body.state.value.plan!.callId, 'wanted');
      feature.release(address, body);
      final title = feature.acquire(address)!;
      expect(identical(body, title), true);
      expect(service.reads, 1);
      feature.release(address, title);
      feature.reset();
      final fresh = feature.acquire(address)!;
      await pump();
      expect(service.reads, 2);
      expect(fresh.state.value.plan, isNull);
      feature.release(address, fresh);
      await pump();
    },
  );
  test(
    'older plan reads keep the opening snapshot cut and exact child address',
    () async {
      final transport = FakeTransport();
      final address = {
        'kind': 'subagent',
        'parentSessionId': 'p',
        'childSessionId': 'c',
        'mode': 'one-shot',
      };
      final read = SessionHistoryRead(transport, address);
      addTearDown(read.close);
      final result = readSubmittedPlan(read, 'wanted');
      await pump();
      transport.onPage = (request) async => {
        'records': [call(2, 'wanted')],
        'hasMore': false,
      };
      transport.open(
        1,
        snapshot([call(20, 'other')], cursor: 30, hasMore: true),
      );
      final plan = await result;
      expect(plan!.callId, 'wanted');
      expect(plan.title, 'Synthetic plan');
      expect(transport.followRequests.single, {'address': address});
      expect(transport.pageRequests.single, {
        'address': address,
        'throughSeq': 30,
        'beforeSeq': 20,
      });
      expect(transport.currentFollow.hasListener, false);
    },
  );
  test('canceling an unopened read closes follow instead of hanging', () async {
    final transport = FakeTransport();
    final read = SessionHistoryRead(transport, {
      'kind': 'session',
      'sessionId': 's',
    });
    final result = readSubmittedPlan(read, 'wanted');
    final rejected = expectLater(result, throwsStateError);
    await pump();
    await read.close();
    await rejected;
    expect(transport.currentFollow.hasListener, false);
    expect(transport.pageRequests, isEmpty);
  });
  test(
    'a no-progress page stops and does not request an infinite history',
    () async {
      final transport = FakeTransport();
      final read = SessionHistoryRead(transport, {
        'kind': 'session',
        'sessionId': 's',
      });
      addTearDown(read.close);
      transport.onPage = (_) async => {
        'records': [call(20, 'other')],
        'hasMore': true,
      };
      final result = readSubmittedPlan(read, 'wanted');
      await pump();
      transport.open(
        1,
        snapshot([call(20, 'other')], cursor: 30, hasMore: true),
      );
      expect(await result, isNull);
      expect(transport.pageRequests, hasLength(1));
    },
  );
  test(
    'plan resource identities keep encoded segments and reject invalid shapes',
    () {
      final target = PlanAddress({
        'kind': 'subagent',
        'parentSessionId': 'p/a',
        'childSessionId': 'c?#',
        'mode': 'continuable',
      }, 'call/% 中文');
      final parsed = PlanAddress.parse(target.encoded)!;
      expect(parsed.session, target.session);
      expect(parsed.callId, target.callId);
      for (final bad in [
        'dsh-resource://plan//call',
        'dsh-resource://plan/a/%XX',
        'dsh-resource://plan/subagent/p/c/invalid/call',
        'dsh-resource://plan/a/c?query',
      ]) {
        expect(PlanAddress.parse(bad), isNull);
      }
      expect(
        isReviewPreviewAddress(reviewPreviewAddress('s/a', 'review:key')),
        true,
      );
    },
  );
}
