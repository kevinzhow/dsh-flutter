import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_open_in_app/src/file_route_action.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements DeliverablesClient {
  int reads = 0;
  @override
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  }) async {
    reads++;
    return const [
      NativeFileApplication(
        id: 'first',
        name: 'Synthetic editor',
        isDefault: false,
      ),
      NativeFileApplication(
        id: 'preferred',
        name: 'Preferred editor',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<void> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
    DeliverablesCancel? cancel,
  }) async {}
  @override
  Future<ChangesSummary> summary(
    String id,
    num seq, {
    DeliverablesCancel? cancel,
  }) async => throw UnimplementedError();
  @override
  Future<ChangesDiff> diff(
    String id,
    num seq,
    int index, {
    DeliverablesCancel? cancel,
  }) async => throw UnimplementedError();
  @override
  Future<PresentedHost> host({DeliverablesCancel? cancel}) async =>
      throw UnimplementedError();
}

void main() {
  testWidgets(
    'shared actions name the Host associations and forward the selected operation',
    (t) async {
      final client = _Client(), model = DeliverablesModel(_Client());
      await model.dispose();
      final active = DeliverablesModel(client),
          session = testSessionOwner('original');
      addTearDown(active.dispose);
      addTearDown(session.conversation.dispose);
      final gestures = <(NativeFileAction, String?)>[];
      const file = DeliveryFile('original', 8, 3);
      final owner = DeliverablesFileActionsOwner(
        session: session,
        actionUrl: file.actionKey,
        available: true,
        pending: false,
        acquireApplications: () => active.acquireApplications(file),
        releaseApplications: active.releaseApplications,
        onAction: (action, [app]) async {
          gestures.add((action, app));
          return null;
        },
      );
      await t.pumpWidget(
        dshTestApp(
          Row(
            children: [
              FileRouteAction(owner: owner, i18n: const DshI18n(DshLocale.en)),
              FileRouteAction(owner: owner, i18n: const DshI18n(DshLocale.en)),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(client.reads, 1);
      expect(gestures, isEmpty);
      await t.tap(find.bySemanticsLabel('Open in Preferred editor').first);
      await t.pumpAndSettle();
      expect(gestures, [(NativeFileAction.open, null)]);
      await t.tap(find.bySemanticsLabel('More ways to open').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Synthetic editor'));
      await t.pumpAndSettle();
      expect(gestures.last, (NativeFileAction.open, 'first'));
      await t.tap(find.bySemanticsLabel('More ways to open').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Show file location'));
      await t.pumpAndSettle();
      expect(gestures.last, (NativeFileAction.reveal, null));
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
