import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart' show dshMarkdownPlainText;

import 'plan_resource.dart';

abstract interface class PlanServices {
  Future<String?> exitPlanMode(String sessionId);
  void openResource(
    SessionOwner owner,
    String address, {
    Map<String, Object?> params = const {},
  });
  SessionHistoryRead historyRead(Map<String, Object?> address);
}

class PlanResourceSnapshot {
  const PlanResourceSnapshot({this.plan, this.failure, this.complete = false});
  final SubmittedPlan? plan;
  final Object? failure;
  final bool complete;
}

/// A document and its title share one immutable resource read. The last
/// consumer leaving cancels a pending follow; settled values are bounded and
/// live only until the Host changes.
class PlanResourceHandle {
  PlanResourceHandle(this.address, this.read);
  final PlanAddress address;
  final SessionHistoryRead read;
  final state = Observable(const PlanResourceSnapshot());
  int consumers = 0;
  bool closed = false;
  Future<void> start() async {
    try {
      final plan = await readSubmittedPlan(read, address.callId);
      if (!closed) {
        state.set(
          plan == null
              ? PlanResourceSnapshot(
                  failure: RemoteException(
                    'plan/not-found',
                    'The submitted plan was not found in this Session.',
                  ),
                  complete: true,
                )
              : PlanResourceSnapshot(plan: plan, complete: true),
        );
      }
    } on Object catch (e) {
      if (!closed) state.set(PlanResourceSnapshot(failure: e, complete: true));
    } finally {
      await read.close();
    }
  }

  Future<void> close() async {
    closed = true;
    await read.close();
    await state.dispose();
  }
}

class PlanFeature {
  PlanFeature(this.services);
  final PlanServices? services;
  final Set<(String, String, String)> openedReviews = {};
  final Map<String, PlanResourceHandle> _resources = {};
  PlanResourceHandle? acquire(String address) {
    final target = PlanAddress.parse(address);
    final services = this.services;
    if (target == null || services == null) return null;
    var value = _resources[address];
    if (value == null) {
      value = PlanResourceHandle(target, services.historyRead(target.session));
      _resources[address] = value;
      unawaited(value.start());
    }
    value.consumers++;
    return value;
  }

  void release(String address, PlanResourceHandle handle) {
    handle.consumers--;
    if (handle.consumers > 0) return;
    if (!handle.state.value.complete) {
      if (identical(_resources[address], handle)) _resources.remove(address);
      unawaited(handle.close());
    }
    while (_resources.length > 64) {
      final inactive = _resources.entries
          .where((e) => e.value.consumers <= 0)
          .firstOrNull;
      if (inactive == null) break;
      _resources.remove(inactive.key);
      unawaited(inactive.value.close());
    }
  }

  void reset() {
    openedReviews.clear();
    for (final handle in _resources.values) {
      unawaited(handle.close());
    }
    _resources.clear();
  }

  void openPlan(SessionOwner owner, String callId) => services?.openResource(
    owner,
    PlanAddress(owner.session.address, callId).encoded,
  );
  void openReview(PlanReviewOwner owner) {
    final callId = owner.callId;
    if (callId != null) {
      openPlan(owner.session, callId);
      return;
    }
    final first = dshMarkdownPlainText(owner.markdown, mode: 'first-line');
    services?.openResource(
      owner.session,
      reviewPreviewAddress(owner.session.sessionId, owner.requestKey),
      params: {
        'planReview': {'markdown': owner.markdown, 'title': first},
      },
    );
  }
}
